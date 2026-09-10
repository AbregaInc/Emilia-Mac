import XCTest
import AVFoundation
import CoreML
import EmiliaCore
@testable import Emilia

final class BaselineTests: XCTestCase {
    func testBaselineAndEmiliaKeepDifferentWindowContracts() {
        XCTAssertEqual(VoiceDetectorChoice.baseline.windowSeconds, 5)
        XCTAssertEqual(VoiceDetectorChoice.emilia.windowSeconds, 3)
        var accumulator = VoicePCMAccumulator(windowSeconds: 5)
        XCTAssertTrue(accumulator.append([Float](repeating: 0, count: 48000), sampleRate: 16000, channels: 1, start: 0, source: "mic").isEmpty)
        let windows = accumulator.append([Float](repeating: 0.2, count: 32000), sampleRate: 16000, channels: 1, start: 3, source: "mic")
        XCTAssertEqual(windows.count, 1); XCTAssertEqual(windows[0].samples.count, 80000)
        XCTAssertEqual(windows[0].samples[0], 0); XCTAssertEqual(windows[0].end, 5)
    }
    func testBaselineParityAndLifecycle() async throws {
        let source = URL(fileURLWithPath: "Models/AASISTBaseline/aasist-l.mlmodel")
        guard FileManager.default.fileExists(atPath: source.path) else { throw XCTSkip("Run setup-baseline.sh to enable baseline inference test") }
        let compiled = try await MLModel.compileModel(at: source)
        defer { try? FileManager.default.removeItem(at: compiled) }
        let detector = BaselineDetector()
        try await detector.load(url: compiled)
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: ".deps/whisper.cpp/samples/jfk.wav"))
        let pcm = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 80000)!
        try file.read(into: pcm, frameCount: 80000)
        let samples = try CapturedBuffer(pcm: pcm, time: 0).interleavedFloatPCM()
        let window = VoicePCMWindow(samples: samples, sampleRate: 16000, channels: 1, end: 5)
        let score = try await detector.score(window)
        XCTAssertEqual(score, 0.9923725128173828, accuracy: 0.00001)
        let stereo = samples.flatMap { [$0,$0] }
        let downmixed = try await detector.score(VoicePCMWindow(samples: stereo, sampleRate: 16000, channels: 2, end: 5))
        XCTAssertEqual(downmixed, score, accuracy: 0.00001)
        let captureRate = samples.flatMap { [$0,$0,$0,$0,$0,$0] }
        let resampled = try await detector.score(VoicePCMWindow(samples: captureRate, sampleRate: 48000, channels: 2, end: 5))
        XCTAssertTrue(resampled.isFinite)
        XCTAssertEqual(resampled >= 0.5, score >= 0.5)
        // This human sample false-flags; parity is not an accuracy claim.
        do { _ = try await detector.score(VoicePCMWindow(samples: [0], sampleRate: 16000, channels: 1, end: 1)); XCTFail("Incomplete window accepted") } catch {}
        await detector.stop()
        do { _ = try await detector.score(window); XCTFail("Stopped model accepted work") } catch {}
        try await detector.load(url: compiled)
        let restarted = try await detector.score(window)
        XCTAssertEqual(restarted, score, accuracy: 0.00001)
        await detector.stop()
    }
    func testBaselineEvidenceIsExplicitAndExpires() {
        var window = VoiceEvidenceWindow()
        window.appendBaseline(score: 0.8, audioEnd: 5)
        window.appendBaseline(score: 0.9, audioEnd: 10)
        let summary = window.summary(at: 10)!
        XCTAssertEqual(summary.detectorKind, "aasist_l_baseline")
        XCTAssertEqual(summary.modelVersion, BaselineDetector.version)
        XCTAssertEqual(summary.meanBaselineScore!, 0.85, accuracy: 0.001)
        XCTAssertNil(summary.meanHumanMargin)
        XCTAssertTrue(summary.supportsSynthetic)
        XCTAssertNil(window.summary(at: 21))
        let request = AstraClient.requestBody(transcript: "Mom, it's your daughter.", voiceEvidence: summary)
        let input = request["input"] as! [[String:String]]
        XCTAssertTrue(input.last!["content"]!.contains("aasist_l_baseline"))
        XCTAssertTrue(AstraClient.instructions.contains("NOT Emilia v8"))
        window.clear(); XCTAssertNil(window.summary(at: 10))
    }
    func testLiveAstraBaselinePolicy() async throws {
        guard ProcessInfo.processInfo.environment["EMILIA_TEST_ASTRA_BASELINE"] == "1" else { throw XCTSkip("Opt-in paid baseline policy check") }
        var window = VoiceEvidenceWindow()
        window.appendBaseline(score: 0.99994, audioEnd: 5)
        window.appendBaseline(score: 0.99994, audioEnd: 10)
        let summary = window.summary(at: 10)!
        let client = AstraClient(); let key = Environment.readKey()
        let benign = try await client.assess(transcript: "This is an automated reminder. Your appointment is tomorrow at ten. No action is needed.", key: key, voiceEvidence: summary)
        XCTAssertFalse(benign.warning)
        let family = "Mom, it's your daughter. This is my new phone number. I wanted to talk with you about our family."
        let result = try await client.assess(transcript: family, key: key, voiceEvidence: summary)
        XCTAssertTrue(result.warning); XCTAssertEqual(result.usesVoiceEvidence, true)
        XCTAssertTrue(WarningPolicy.grounded(result, in: family))
    }
}
