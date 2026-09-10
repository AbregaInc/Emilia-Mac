import AVFoundation
import CWhisperBridge
import EmiliaCore

/// One native Whisper context on a serial worker. Audio remains in memory.
final class SpeechPipeline: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.abrega.emilia.whisper", qos: .userInitiated)
    private let lock = NSLock()
    private var context: OpaquePointer?
    private var stopped = false
    private var busy = false
    private var onTranscript: (@Sendable (TranscriptSegment) -> Void)?
    private var onError: (@Sendable (String) -> Void)?
    private var ring = AudioRing(capacity: 16000 * 12)
    private var lastSubmission = 0.0
    private var phraseStart = 0.0
    private var silence = 0.0
    private var hadSpeech = false
    private var audioEnd: Double?
    private let converter = PCMConverter(outputFormat: AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!)
    private(set) var dropped = 0
    private let mode: TranscriptionMode
    private let key: String
    private var realtime: RealtimeTranscriber?
    private var realtimeContinuation: AsyncStream<RealtimeAudioPacket>.Continuation?
    private let realtimeConverter = PCMConverter(outputFormat: AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24000, channels: 1, interleaved: false)!)
    init(mode: TranscriptionMode = .local, key: String = "") { self.mode = mode; self.key = key }

    static var modelURL: URL {
        if let path = ProcessInfo.processInfo.environment["EMILIA_WHISPER_MODEL"] { return URL(fileURLWithPath: path) }
        if let bundled = Bundle.main.url(forResource: "ggml-base.en", withExtension: "bin") { return bundled }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appending(path: "Models/ggml-base.en.bin")
    }
    func prepare(onTranscript: @escaping @Sendable (TranscriptSegment) -> Void,
                 onError: @escaping @Sendable (String) -> Void) async throws {
        self.onTranscript = onTranscript; self.onError = onError
        if mode == .realtime {
            let client = RealtimeTranscriber(); realtime = client
            let pair = AsyncStream<RealtimeAudioPacket>.makeStream(bufferingPolicy: .bufferingNewest(64))
            realtimeContinuation = pair.continuation
            try await withTaskCancellationHandler {
                try await client.connect(key: key, packets: pair.stream, onTranscript: onTranscript, onError: onError)
            } onCancel: { Task { await client.stop() } }
            return
        }
        let path = Self.modelURL.path
        guard FileManager.default.fileExists(atPath: path) else {
            throw NSError(domain: "Whisper", code: 1, userInfo: [NSLocalizedDescriptionKey: "Whisper model missing. Run scripts/setup-whisper.sh and rebuild the app."])
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                let loaded = emilia_whisper_create(path)
                lock.lock(); context = loaded; let cancelled = stopped; lock.unlock()
                if cancelled, let loaded { emilia_whisper_cancel(loaded) }
                if loaded == nil { continuation.resume(throwing: NSError(domain: "Whisper", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not load local Whisper model."])) }
                else { continuation.resume() }
            }
        }
    }
    // Called only by the serial capture consumer; never by the audio callback.
    func append(_ input: CapturedBuffer) throws {
        if mode == .realtime {
            let buffer = try realtimeConverter.convert(input.pcm)
            guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            let rms = sqrt(samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(samples.count))
            let packet = RealtimeAudioPacket(pcm16: RealtimeAudioPacket.encode(samples), end: input.time + Double(samples.count) / 24000, speech: rms > 0.004)
            if case .dropped = realtimeContinuation?.yield(packet) { throw RealtimeError.backlog }
            return
        }
        let buffer = try converter.convert(input.pcm)
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        let duration = Double(samples.count) / 16000
        let rms = sqrt(samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(samples.count))
        if rms > 0.004 { hadSpeech = true; silence = 0 } else { silence += duration }
        if let previous = audioEnd, input.time - previous > 0.25 {
            ring.clear(); phraseStart = input.time; hadSpeech = rms > 0.004; silence = 0
            audioEnd = input.time
        }
        let end = (audioEnd ?? input.time) + duration
        audioEnd = end
        ring.append(samples)
        let phraseEnded = silence >= 0.7 && hadSpeech
        guard hadSpeech, end - lastSubmission >= (phraseEnded ? 1 : 3), ring.count >= 16000 else { return }
        lock.lock()
        guard !stopped, !busy else { lock.unlock(); return }
        busy = true; lock.unlock()
        lastSubmission = end
        let audio = ring.suffix(16000 * 12)
        let start = max(phraseStart, end - Double(audio.count) / 16000)
        if phraseEnded { ring.clear(); phraseStart = end; hadSpeech = false; silence = 0 }
        queue.async { [self] in
            defer { lock.lock(); busy = false; lock.unlock() }
            lock.lock(); let ctx = context; let cancelled = stopped; lock.unlock()
            guard !cancelled, let ctx else { return }
            let result = audio.withUnsafeBufferPointer { emilia_whisper_transcribe(ctx, $0.baseAddress, Int32($0.count)) }
            guard let result else {
                lock.lock(); let cancelled = stopped; lock.unlock()
                if !cancelled { onError?("Local Whisper could not transcribe this audio window.") }
                return
            }
            defer { emilia_whisper_free_text(result) }
            let text = String(cString: result).trimmingCharacters(in: .whitespacesAndNewlines)
            lock.lock(); let cancelledNow = stopped; lock.unlock()
            if !cancelledNow { onTranscript?(TranscriptSegment(start: start, end: end, text: text)) }
        }
    }
    func stop() {
        realtimeContinuation?.finish(); realtimeContinuation = nil
        if let realtime { Task { await realtime.stop() }; self.realtime = nil }
        lock.lock(); stopped = true; if let context { emilia_whisper_cancel(context) }; lock.unlock()
        queue.async { [self] in
            lock.lock(); let ctx = context; context = nil; lock.unlock()
            if let ctx { emilia_whisper_free(ctx) }
        }
    }
}
