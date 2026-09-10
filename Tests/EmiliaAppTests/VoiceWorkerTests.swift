import XCTest
import EmiliaCore
@testable import Emilia

final class VoiceWorkerTests: XCTestCase {
    func testMissingBundleIsUnavailable() async throws {
        let worker = VoiceDetector(bundle: URL(fileURLWithPath: "/nonexistent-emilia-test"))
        let version = try await worker.load()
        XCTAssertNil(version)
    }
    func testResponseIDsAreCheckedAndShutdownRejectsWork() async throws {
        let python = VoiceDetector.python
        guard FileManager.default.isExecutableFile(atPath: python) else { throw XCTSkip("Local configured Python required for protocol fixture") }
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("{\"model_id\":\"promotion-v8-reconstruction-20260910\",\"window_samples\":48000}".utf8).write(to: directory.appending(path: "bundle.json"))
        let fixture = """
        import sys,json
        for line in sys.stdin:
            request=json.loads(line)
            if request['id']=='ready':
                print(json.dumps({'id':'ready','error':'Need three complete seconds; no padding'}),flush=True)
            else:
                print(json.dumps({'id':'wrong-id','error':'fixture'}),flush=True)
        """
        try Data(fixture.utf8).write(to: directory.appending(path: "v8_inference.py"))
        let worker = VoiceDetector(bundle: directory, python: python)
        defer { worker.stop() }
        let version = try await worker.load(); XCTAssertNotNil(version)
        let window = VoicePCMWindow(samples: [Float](repeating: 0, count: 48000), sampleRate: 16000, channels: 1, end: 3)
        do { _ = try await worker.score(window, bandwidth: .wideband); XCTFail("Mismatched ID accepted") }
        catch { XCTAssertTrue(error.localizedDescription.contains("ID mismatch")) }
        worker.stop()
        do { _ = try await worker.score(window, bandwidth: .wideband); XCTFail("Stopped worker accepted work") }
        catch { XCTAssertTrue(error.localizedDescription.contains("unavailable")) }
        let restarted = try await worker.load(); XCTAssertNotNil(restarted)
    }
}
