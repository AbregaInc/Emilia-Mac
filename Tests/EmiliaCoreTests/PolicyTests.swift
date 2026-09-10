import XCTest
@testable import EmiliaCore

final class PolicyTests: XCTestCase {
    let transcript = "Please read me the verification code. Keep this call secret."
    var risk: RiskAssessment { RiskAssessment(warning: true, category: .credentialRequest, reason: "The caller requested your verification code.", quotes: ["read me the verification code"]) }
    func testHumanScamCanWarnWithoutVoiceScore() {
        var policy = WarningPolicy()
        XCTAssertTrue(policy.consider(risk, transcript: transcript, now: 3))
    }
    func testFabricatedOrRetractedEvidenceDoesNotWarn() {
        var policy = WarningPolicy()
        XCTAssertFalse(policy.consider(risk, transcript: "Never share your code with anyone.", now: 3))
        XCTAssertFalse(policy.consider(RiskAssessment(warning: true, category: .none, reason: "Something", quotes: ["Keep this call secret"]), transcript: transcript, now: 3))
    }
    func testAbstentionCannotTriggerAndRepeatedCategoryStaysSuppressed() {
        var policy = WarningPolicy()
        XCTAssertFalse(policy.consider(RiskAssessment(warning: false, category: .none, reason: "", quotes: []), transcript: transcript, now: 1))
        XCTAssertTrue(policy.consider(risk, transcript: transcript, now: 3))
        XCTAssertFalse(policy.consider(risk, transcript: transcript, now: 100))
    }
    func testNewCategoryRequiresCooldown() {
        var policy = WarningPolicy()
        XCTAssertTrue(policy.consider(risk, transcript: transcript, now: 3))
        let another = RiskAssessment(warning: true, category: .secrecy, reason: "Secrecy requested", quotes: ["Keep this call secret"])
        XCTAssertFalse(policy.consider(another, transcript: transcript, now: 6))
        XCTAssertTrue(policy.consider(another, transcript: transcript, now: 20))
    }
    func testRevisionReplacesAndRetentionExpiresDuringSilence() {
        var window = TranscriptWindow(retention: 10, characterLimit: 100)
        window.update(TranscriptSegment(start: 0, end: 3, text: "share your code"))
        window.update(TranscriptSegment(start: 0, end: 4, text: "never share your code"))
        XCTAssertEqual(window.text, "never share your code")
        window.prune(at: 15)
        XCTAssertTrue(window.text.isEmpty)
    }
    func testLongSegmentIsBoundedAndRingWrapsChronologically() {
        var window = TranscriptWindow(characterLimit: 12)
        window.update(TranscriptSegment(start: 0, end: 1, text: String(repeating: "a", count: 100)))
        XCTAssertEqual(window.text.count, 12)
        var ring = AudioRing(capacity: 4)
        ring.append([1, 2, 3, 4, 5, 6])
        XCTAssertEqual(ring.suffix(9), [3, 4, 5, 6])
        ring.clear(); XCTAssertEqual(ring.suffix(4), [])
    }
    func testResponseEnvelopeAndRefusal() throws {
        let resultData = try JSONEncoder().encode(risk)
        let object: [String: Any] = ["status": "completed", "output": [["type": "message", "content": [["type": "output_text", "text": String(decoding: resultData, as: UTF8.self)]]]]]
        XCTAssertEqual(try AstraClient.decode(JSONSerialization.data(withJSONObject: object)), risk)
        let refused: [String: Any] = ["status": "completed", "output": [["content": [["type": "refusal", "refusal": "No"]]]]]
        XCTAssertThrowsError(try AstraClient.decode(JSONSerialization.data(withJSONObject: refused)))
        XCTAssertThrowsError(try AstraClient.decode(Data("{\"status\":\"incomplete\"}".utf8)))
    }
    func testRequestUsesAstraAndDoesNotStoreTranscript() throws {
        let body = AstraClient.requestBody(transcript: String(repeating: "x", count: 8000))
        XCTAssertEqual(body["model"] as? String, "gpt-6-astra")
        XCTAssertEqual(body["store"] as? Bool, false)
        let input = try XCTUnwrap(body["input"] as? [[String: String]])
        XCTAssertEqual(input.first?["content"]?.count, 6000)
        XCTAssertNil(body["tools"])
    }
}
