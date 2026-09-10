import AppKit
import AVFoundation
import CoreAudio

enum CaptureMode: String, CaseIterable, Identifiable {
    case microphone = "Microphone"
    case system = "System audio"
    var id: String { rawValue }
    var detail: String {
        self == .microphone ? "Listen to a nearby call on speakerphone." : "Listen to audio from all apps. Microphone is excluded."
    }
}

enum CaptureError: LocalizedError {
    case coreAudio(String, OSStatus), format
    var errorDescription: String? {
        switch self {
        case let .coreAudio(operation, status): return "\(operation) failed (\(status)). Check System Settings → Privacy & Security → Screen & System Audio Recording."
        case .format: return "The selected app's audio format is unavailable. Start audio playback and try again."
        }
    }
}

struct CapturedBuffer: @unchecked Sendable {
    let pcm: AVAudioPCMBuffer
    let time: Double
    func interleavedFloatPCM() throws -> [Float] {
        let channels = Int(pcm.format.channelCount), frames = Int(pcm.frameLength)
        guard channels > 0 else { throw CaptureError.format }
        var output = [Float](repeating: 0, count: frames * channels)
        for frame in 0..<frames { for channel in 0..<channels {
            let plane = pcm.format.isInterleaved ? 0 : channel
            let index = pcm.format.isInterleaved ? frame * channels + channel : frame
            switch pcm.format.commonFormat {
            case .pcmFormatFloat32: output[frame * channels + channel] = pcm.floatChannelData![plane][index]
            case .pcmFormatInt16: output[frame * channels + channel] = Float(pcm.int16ChannelData![plane][index]) / 32768
            case .pcmFormatInt32: output[frame * channels + channel] = Float(pcm.int32ChannelData![plane][index]) / 2147483648
            default: throw CaptureError.format
            }
        } }
        return output
    }
}

final class AudioCapture {
    private var microphone: AVAudioEngine?
    private var tap: AudioObjectID = 0
    private var device: AudioObjectID = 0
    private var io: AudioDeviceIOProcID?
    private var continuation: AsyncStream<CapturedBuffer>.Continuation?
    private let queue = DispatchQueue(label: "com.abrega.emilia.capture", qos: .userInitiated)
    private let lock = NSLock()
    private var dropped = 0
    var droppedBuffers: Int { lock.lock(); defer { lock.unlock() }; return dropped }

    func start(mode: CaptureMode) async throws -> AsyncStream<CapturedBuffer> {
        stop()
        if mode == .microphone {
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                throw NSError(domain: "Microphone", code: 1, userInfo: [NSLocalizedDescriptionKey: "Microphone access is off. Enable Emilia in System Settings → Privacy & Security → Microphone."])
            }
            try Task.checkCancellation()
            let engine = AVAudioEngine()
            let node = engine.inputNode
            let format = node.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw CaptureError.format }
            let pair = AsyncStream<CapturedBuffer>.makeStream(bufferingPolicy: .bufferingNewest(32))
            continuation = pair.continuation; dropped = 0
            let epoch = ProcessInfo.processInfo.systemUptime
            node.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] pcm, _ in
                guard let buffer = AVAudioPCMBuffer(pcmFormat: pcm.format, frameCapacity: pcm.frameLength) else { return }
                buffer.frameLength = pcm.frameLength
                let src = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: pcm.audioBufferList))
                let dst = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
                for i in src.indices {
                    if let a = src[i].mData, let b = dst[i].mData { memcpy(b, a, Int(src[i].mDataByteSize)) }
                }
                let time = max(0, ProcessInfo.processInfo.systemUptime - epoch - Double(pcm.frameLength) / format.sampleRate)
                if case .dropped = pair.continuation.yield(CapturedBuffer(pcm: buffer, time: time)) {
                    guard let self else { return }; self.lock.lock(); self.dropped += 1; self.lock.unlock()
                }
            }
            microphone = engine
            do { try engine.start() } catch { stop(); throw error }
            return pair.stream
        }
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.name = "Emilia — System Audio"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        description.isProcessRestoreEnabled = true
        try check(AudioHardwareCreateProcessTap(description, &tap), "Audio capture permission")
        do {
            var asbd = AudioStreamBasicDescription()
            var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            try check(AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &asbd), "Read audio format")
            guard let format = AVAudioFormat(streamDescription: &asbd), asbd.mBytesPerFrame > 0 else { throw CaptureError.format }
            let config: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Emilia Capture",
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]]
            ]
            try check(AudioHardwareCreateAggregateDevice(config as CFDictionary, &device), "Create capture device")
            let pair = AsyncStream<CapturedBuffer>.makeStream(bufferingPolicy: .bufferingNewest(32))
            continuation = pair.continuation
            dropped = 0
            let epoch = ProcessInfo.processInfo.systemUptime
            try check(AudioDeviceCreateIOProcIDWithBlock(&io, device, queue) { [weak self] _, input, _, _, _ in
                let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
                guard let first = list.first, first.mDataByteSize > 0 else { return }
                let frames = first.mDataByteSize / asbd.mBytesPerFrame
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
                buffer.frameLength = frames
                let output = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
                guard output.count == list.count else { return }
                for index in output.indices {
                    guard let src = list[index].mData, let dst = output[index].mData else { return }
                    memcpy(dst, src, min(Int(output[index].mDataByteSize), Int(list[index].mDataByteSize)))
                }
                let item = CapturedBuffer(pcm: buffer, time: max(0, ProcessInfo.processInfo.systemUptime - epoch - Double(frames) / format.sampleRate))
                if case .dropped = pair.continuation.yield(item) { self?.lock.lock(); self?.dropped += 1; self?.lock.unlock() }
            }, "Install audio callback")
            try check(AudioDeviceStart(device, io), "Start capture")
            return pair.stream
        } catch { stop(); throw error }
    }
    func stop() {
        if let microphone { microphone.inputNode.removeTap(onBus: 0); microphone.stop(); self.microphone = nil }
        if let io, device != 0 { AudioDeviceStop(device, io); AudioDeviceDestroyIOProcID(device, io) }
        io = nil
        if device != 0 { AudioHardwareDestroyAggregateDevice(device); device = 0 }
        if tap != 0 { AudioHardwareDestroyProcessTap(tap); tap = 0 }
        continuation?.finish(); continuation = nil
    }
    deinit { stop() }
    private func check(_ status: OSStatus, _ operation: String) throws { if status != noErr { throw CaptureError.coreAudio(operation, status) } }
}

final class PCMConverter {
    private var converter: AVAudioConverter?
    let outputFormat: AVAudioFormat
    init(outputFormat: AVAudioFormat) { self.outputFormat = outputFormat }
    func convert(_ input: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        if input.format == outputFormat { return input }
        if converter?.inputFormat != input.format {
            converter = AVAudioConverter(from: input.format, to: outputFormat)
            converter?.primeMethod = .none
        }
        guard let converter else { throw CaptureError.format }
        let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * outputFormat.sampleRate / input.format.sampleRate)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { throw CaptureError.format }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            if supplied { state.pointee = .noDataNow; return nil }
            supplied = true; state.pointee = .haveData; return input
        }
        if let error { throw error }
        guard status != .error else { throw CaptureError.format }
        return output
    }
}
