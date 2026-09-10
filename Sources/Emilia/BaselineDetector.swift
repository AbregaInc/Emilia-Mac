import AVFoundation
import CoreML
import EmiliaCore

enum VoiceDetectorChoice: String, CaseIterable {
    case baseline, emilia
    var label: String { self == .baseline ? "AASIST-L baseline · included" : "Emilia v8 · external research model" }
    var windowSeconds: Int { self == .baseline ? 5 : 3 }
}

/// Separate from Emilia's frozen three-second worker contract. No Python at runtime.
actor BaselineDetector {
    static let version = "aasist-l-a04c986-coreml-v1"
    private var model: MLModel?
    func load(url: URL? = nil) throws {
        let path = url ?? Bundle.main.url(forResource: "aasist-l", withExtension: "mlmodelc")
        guard let path else { throw failure("Bundled AASIST-L baseline is missing.") }
        let configuration = MLModelConfiguration(); configuration.computeUnits = .cpuOnly
        model = try MLModel(contentsOf: path, configuration: configuration)
    }
    func stop() { model = nil }
    func score(_ window: VoicePCMWindow) throws -> Double {
        guard let model else { throw failure("AASIST-L baseline is unavailable.") }
        guard window.samples.count == window.sampleRate * 5 * window.channels,
              window.samples.allSatisfy(\.isFinite) else { throw failure("Baseline requires five complete seconds of finite PCM.") }
        var mono = [Float](repeating: 0, count: window.samples.count / window.channels)
        for frame in mono.indices {
            for channel in 0..<window.channels { mono[frame] += window.samples[frame * window.channels + channel] / Float(window.channels) }
        }
        if window.sampleRate != 16000 {
            let inputFormat = AVAudioFormat(standardFormatWithSampleRate: Double(window.sampleRate), channels: 1)!
            let outputFormat = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
            let pcm = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(mono.count))!
            pcm.frameLength = AVAudioFrameCount(mono.count)
            mono.withUnsafeBufferPointer { pcm.floatChannelData![0].update(from: $0.baseAddress!, count: mono.count) }
            let converted = try PCMConverter(outputFormat: outputFormat).convert(pcm)
            mono = Array(UnsafeBufferPointer(start: converted.floatChannelData![0], count: Int(converted.frameLength)))
        }
        // Converted graph accepts 80,000 values but uses only the official 64,600 prefix.
        // Never pad an incomplete model prefix; the unused graph tail is zero initialized.
        guard mono.count >= 64600 else { throw failure("Baseline resampling produced an incomplete prefix.") }
        let input = try MLMultiArray(shape: [1, 80000], dataType: .float32)
        let pointer = input.dataPointer.bindMemory(to: Float.self, capacity: 80000)
        pointer.initialize(repeating: 0, count: 80000)
        for i in 0..<64600 { pointer[i] = mono[i] }
        let prediction = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["audio": input]))
        guard let value = prediction.featureValue(for: "synthetic_score")?.multiArrayValue?[0].doubleValue,
              value.isFinite, (0...1).contains(value) else { throw failure("Baseline returned an invalid score.") }
        return value
    }
    private func failure(_ text: String) -> NSError { NSError(domain: "AASISTBaseline", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
}
