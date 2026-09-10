import XCTest
import AVFoundation
@testable import Emilia
import EmiliaCore

final class AudioTests: XCTestCase {
    func testConverterDownmixesAndResamplesToWhisperFormat() throws {
        let stereo = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: false)!
        let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        let input = AVAudioPCMBuffer(pcmFormat: stereo, frameCapacity: 4800)!
        input.frameLength = 4800
        for i in 0..<4800 { input.floatChannelData![0][i] = 0.2; input.floatChannelData![1][i] = 0.2 }
        let converter = PCMConverter(outputFormat: mono)
        let converted = try converter.convert(input)
        XCTAssertEqual(converted.format.sampleRate, 16000)
        XCTAssertEqual(converted.format.channelCount, 1)
        // The streaming FIR retains a bounded startup tail; subsequent packets preserve cadence.
        XCTAssertGreaterThan(converted.frameLength, 1300)
        XCTAssertLessThanOrEqual(converted.frameLength, 1632)
        XCTAssertEqual(converted.floatChannelData![0][500], 0.2, accuracy: 0.01)
        var total = Int(converted.frameLength)
        for _ in 1..<20 { total += Int(try converter.convert(input).frameLength) }
        XCTAssertGreaterThanOrEqual(total, 32000 - 300)
        XCTAssertLessThanOrEqual(total, 32000)
    }
    func testLocalWhisperPipelineTranscribesObservedAudio() async throws {
        guard ProcessInfo.processInfo.environment["EMILIA_TEST_WHISPER"] == "1" else { throw XCTSkip("Opt-in local model integration test") }
        let pipeline = SpeechPipeline()
        defer { pipeline.stop() }
        let received = expectation(description: "Whisper transcript")
        received.assertForOverFulfill = false
        try await pipeline.prepare(onTranscript: { segment in
            if segment.text.lowercased().contains("country") {
                XCTAssertLessThanOrEqual(segment.end, 12.1)
                received.fulfill()
            }
        }, onError: { message in XCTFail(message) })
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: ".deps/whisper.cpp/samples/jfk.wav"))
        let pcm = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16000 * 12)!
        try file.read(into: pcm, frameCount: 16000 * 12)
        try pipeline.append(CapturedBuffer(pcm: pcm, time: 0))
        await fulfillment(of: [received], timeout: 30)
    }
    @MainActor func testStopClearsUserVisibleEvidence() {
        let model = AppModel()
        model.transcript = "private text"
        model.listening = true
        model.synthetic = true
        model.stop()
        XCTAssertFalse(model.listening)
        XCTAssertFalse(model.synthetic)
        XCTAssertTrue(model.transcript.isEmpty)
        XCTAssertNil(model.warning)
    }
    func testVoiceModelLoadsAndScoresActualLocalAudio() async throws {
        guard ProcessInfo.processInfo.environment["EMILIA_TEST_VOICE"] == "1" else { throw XCTSkip("Opt-in external model check") }
        let detector = VoiceDetector()
        defer { detector.stop() }
        let version = try await detector.load()
        XCTAssertNotNil(version)
        let file = try AVAudioFile(forReading: VoiceDetector.directory.appending(path: "reference.wav"))
        let frames = AVAudioFrameCount(file.processingFormat.sampleRate * 3)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames)!
        try file.read(into: buffer, frameCount: frames)
        let pcm = try CapturedBuffer(pcm: buffer, time: 0).interleavedFloatPCM()
        let window = VoicePCMWindow(samples: pcm, sampleRate: Int(buffer.format.sampleRate), channels: Int(buffer.format.channelCount), end: 3)
        let result = try await detector.score(window, bandwidth: .wideband)
        XCTAssertEqual(result.humanMargin!, 0.06209803647790091, accuracy: 1e-8)
        XCTAssertEqual(result.artifactScore, 6.047003626183e-08, accuracy: 1e-10)
        XCTAssertEqual(result.route, "v6"); XCTAssertEqual(result.syntheticFlag, false)
        let unknown = try await detector.score(window, bandwidth: .unknown)
        XCTAssertNil(unknown.syntheticFlag); XCTAssertNil(unknown.humanMargin)
        XCTAssertEqual(unknown.bandwidthDecisions.count, 2)
        detector.stop()
        do { _ = try await detector.score(window, bandwidth: .wideband); XCTFail("Stopped worker accepted audio") } catch {}
    }
}
