import Foundation
import EmiliaCore

/// One persistent, checksum-verifying original-v8 CPU worker. No model files are bundled.
final class VoiceDetector: @unchecked Sendable {
    static var directory: URL {
        if let path = ProcessInfo.processInfo.environment["EMILIA_V8_BUNDLE"] { return URL(fileURLWithPath: path) }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/Emilia/VoiceModel-v8")
    }
    static var python: String {
        ProcessInfo.processInfo.environment["EMILIA_V8_PYTHON"] ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/Emilia/VoiceModel-v8-python").path
    }
    private struct Worker { let process: Process; let input: Pipe; let output: Pipe }
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "emilia.v8.inference", qos: .userInitiated)
    private var worker: Worker?
    private var generation = UUID()
    private let bundle: URL
    private let executable: String
    init(bundle: URL = VoiceDetector.directory, python: String = VoiceDetector.python) { self.bundle = bundle; executable = python }
    deinit { stop() }
    func stop() {
        lock.lock(); let old = worker; worker = nil; generation = UUID(); lock.unlock()
        if let old, old.process.isRunning {
            old.process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if old.process.isRunning { kill(old.process.processIdentifier, SIGKILL) }
            }
        }
    }
    private func current() -> Worker? { lock.lock(); defer { lock.unlock() }; return worker }
    private func loadGeneration() -> UUID { lock.lock(); defer { lock.unlock() }; return generation }
    private func install(_ value: Worker, generation expected: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard generation == expected else { return false }
        worker = value; return true
    }
    func load() async throws -> String? {
        stop()
        let token = loadGeneration()
        guard FileManager.default.fileExists(atPath: bundle.appending(path: "bundle.json").path) else { return nil }
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: bundle.appending(path: "bundle.json"))) as? [String: Any]
        guard manifest?["model_id"] as? String == "promotion-v8-reconstruction-20260910",
              manifest?["window_samples"] as? Int == 48000 else { throw failure("Expected the recovered original Emilia v8 bundle.") }
        let process = Process(); let input = Pipe(); let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = [bundle.appending(path: "v8_inference.py").path, "--bundle", bundle.path, "--seed", "1", "--bandwidth", "unknown", "--serve"]
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.standardError
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "OPENAI_API_KEY")
        environment["PYTHONUNBUFFERED"] = "1"; environment["HF_HUB_OFFLINE"] = "1"
        process.environment = environment
        try process.run()
        let value = Worker(process: process, input: input, output: output)
        guard install(value, generation: token) else { process.terminate(); throw failure("Emilia worker startup cancelled.") }
        do {
            let reply = try await exchange(["id": "ready", "pcm_f32le_base64": "", "sample_rate": 16000, "channels": 1], worker: value, timeout: 60)
            guard (reply["error"] as? String)?.contains("three complete seconds") == true else { throw failure("Unexpected Emilia worker startup response.") }
            return "Emilia v8 · seed 1 · CPU"
        } catch { if current()?.process === value.process { stop() }; throw error }
    }
    func score(_ window: VoicePCMWindow, bandwidth: VoiceBandwidth) async throws -> VoiceModelResult {
        guard let worker = current(), worker.process.isRunning else { throw failure("Emilia v8 worker is unavailable.") }
        guard window.samples.count == window.sampleRate * 3 * window.channels else { throw failure("Emilia v8 requires three complete seconds.") }
        let data = window.samples.withUnsafeBytes { Data($0) }
        let id = UUID().uuidString
        let reply = try await exchange(["id": id, "pcm_f32le_base64": data.base64EncodedString(), "sample_rate": window.sampleRate, "channels": window.channels, "bandwidth": bandwidth.rawValue], worker: worker, timeout: 15)
        if let error = reply["error"] as? String { throw failure(String(error.prefix(250))) }
        guard let object = reply["result"] else { throw failure("Emilia worker returned no result.") }
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let result = try decoder.decode(VoiceModelResult.self, from: JSONSerialization.data(withJSONObject: object))
        guard result.isValid, result.bandwidth == bandwidth else { throw failure("Emilia worker returned an invalid model contract.") }
        return result
    }
    private func exchange(_ request: [String: Any], worker: Worker, timeout: Double) async throws -> [String: Any] {
        let bytes = try JSONSerialization.data(withJSONObject: request) + Data([10])
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let deadline = DispatchWorkItem { if worker.process.isRunning { kill(worker.process.processIdentifier, SIGKILL) } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
                defer { deadline.cancel() }
                do {
                    guard self.current()?.process === worker.process, worker.process.isRunning else { throw self.failure("Emilia worker stopped.") }
                    try worker.input.fileHandleForWriting.write(contentsOf: bytes)
                    var line = Data()
                    while line.count < 65536 {
                        guard let byte = try worker.output.fileHandleForReading.read(upToCount: 1), !byte.isEmpty else { throw self.failure("Emilia worker exited or timed out. Restart listening to retry.") }
                        if byte[0] == 10 { break }; line.append(byte)
                    }
                    guard let reply = try JSONSerialization.jsonObject(with: line) as? [String: Any], reply["id"] as? String == request["id"] as? String else { throw self.failure("Emilia worker response ID mismatch.") }
                    continuation.resume(returning: reply)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    private func failure(_ text: String) -> NSError { NSError(domain: "EmiliaV8", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
}
