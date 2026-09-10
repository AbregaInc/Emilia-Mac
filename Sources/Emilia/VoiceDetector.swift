import Foundation
import CoreML
import CryptoKit

/// Optional local waveform model. No research checkpoint is implicitly licensed by this adapter.
actor VoiceDetector {
    struct Manifest: Codable {
        let modelVersion: String
        let modelFile: String
        let sha256: String
        let inputName: String
        let outputName: String
        let sampleRate: Int
        let sampleCount: Int
        let threshold: Double
        let license: String
        let sourceURL: String
        let deploymentPermission: String
    }
    private var model: MLModel?
    private var manifest: Manifest?
    static var directory: URL {
        if let path = ProcessInfo.processInfo.environment["EMILIA_VOICE_MODEL_DIR"] { return URL(fileURLWithPath: path) }
        let development = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().appending(path: "Models/VoiceModel")
        if FileManager.default.fileExists(atPath: development.appending(path: "manifest.json").path) { return development }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/Emilia/VoiceModel")
    }
    func load() throws -> String? {
        let url = Self.directory.appending(path: "manifest.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
        guard manifest.sampleRate == 16000, manifest.sampleCount == 80000,
              (0...1).contains(manifest.threshold), !manifest.license.isEmpty,
              !manifest.deploymentPermission.isEmpty,
              manifest.modelFile == URL(fileURLWithPath: manifest.modelFile).lastPathComponent,
              manifest.modelFile.hasSuffix(".mlmodel") else { throw invalid("Invalid model contract or missing permission record.") }
        let modelURL = Self.directory.appending(path: manifest.modelFile)
        let digest = SHA256.hash(data: try Data(contentsOf: modelURL)).map { String(format: "%02x", $0) }.joined()
        guard digest == manifest.sha256 else { throw invalid("Voice model checksum does not match manifest.") }
        let compiled = try MLModel.compileModel(at: modelURL)
        defer { try? FileManager.default.removeItem(at: compiled) }
        let config = MLModelConfiguration(); config.computeUnits = .cpuAndNeuralEngine
        let loaded = try MLModel(contentsOf: compiled, configuration: config)
        guard loaded.modelDescription.inputDescriptionsByName[manifest.inputName] != nil,
              loaded.modelDescription.outputDescriptionsByName[manifest.outputName] != nil else { throw invalid("Voice model input/output names do not match.") }
        self.model = loaded; self.manifest = manifest
        return manifest.modelVersion
    }
    func score(_ samples: [Float]) throws -> (Double, Bool)? {
        guard let model, let manifest, samples.count == manifest.sampleCount else { return nil }
        let array = try MLMultiArray(shape: [1, NSNumber(value: samples.count)], dataType: .float32)
        let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: samples.count)
        samples.withUnsafeBufferPointer { pointer.update(from: $0.baseAddress!, count: samples.count) }
        let input = try MLDictionaryFeatureProvider(dictionary: [manifest.inputName: MLFeatureValue(multiArray: array)])
        let output = try model.prediction(from: input)
        guard let value = output.featureValue(for: manifest.outputName) else { throw invalid("Missing voice score.") }
        let score = value.multiArrayValue.map { $0[0].doubleValue } ?? value.doubleValue
        guard score.isFinite, (0...1).contains(score) else { throw invalid("Voice score must be a finite scalar between zero and one.") }
        return (score, score >= manifest.threshold)
    }
    private func invalid(_ message: String) -> NSError { NSError(domain: "VoiceModel", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
