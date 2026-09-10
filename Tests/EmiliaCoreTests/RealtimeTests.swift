import XCTest
@testable import EmiliaCore

final class RealtimeTests: XCTestCase {
    func testPCMEncodingClipsAndHandlesNonfiniteValues() {
        let data = RealtimeAudioPacket.encode([-2, 0, 2, .nan, .infinity, .greatestFiniteMagnitude])
        XCTAssertEqual(Array(data), [0, 128, 0, 0, 255, 127, 0, 0, 0, 0, 255, 127])
    }
    func testPartialFinalReconciliationAndOutOfOrderCompletions() {
        var state = RealtimeTranscriptState()
        var window = TranscriptWindow()
        _ = state.receive(["type": "input_audio_buffer.speech_started", "item_id": "a", "audio_start_ms": 0.0], audioEnd: 0)
        if let partial = state.receive(["type": "conversation.item.input_audio_transcription.delta", "item_id": "a", "delta": "Never share"], audioEnd: 3) { window.update(partial) }
        _ = state.receive(["type": "input_audio_buffer.speech_stopped", "item_id": "a", "audio_end_ms": 3000.0], audioEnd: 3)
        _ = state.receive(["type": "input_audio_buffer.speech_started", "item_id": "b", "audio_start_ms": 2700.0], audioEnd: 4)
        let b = state.receive(["type": "conversation.item.input_audio_transcription.completed", "item_id": "b", "transcript": "Call your bank."], audioEnd: 6)!
        window.update(b)
        let a = state.receive(["type": "conversation.item.input_audio_transcription.completed", "item_id": "a", "transcript": "Never share your code."], audioEnd: 6)!
        window.update(a)
        XCTAssertEqual(window.text, "Never share your code. Call your bank.")
        let late = state.receive(["type": "conversation.item.input_audio_transcription.delta", "item_id": "a", "delta": "incorrect late delta"], audioEnd: 7)!
        XCTAssertEqual(late.text, "Never share your code.")
    }
    func testConfigurationUsesLiveModelAndManualTurnDetection() throws {
        let config = RealtimeTranscriber.configuration()
        let data = try JSONSerialization.data(withJSONObject: config)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("gpt-live-transcribe"))
        XCTAssertTrue(text.contains("\"turn_detection\":null"))
        XCTAssertTrue(text.contains("24000"))
    }
}
