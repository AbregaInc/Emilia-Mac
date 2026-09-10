import XCTest
@testable import EmiliaCore

final class VoiceEvidenceTests: XCTestCase {
    func testLiveAstraCombinedEvidence() async throws {
        guard ProcessInfo.processInfo.environment["EMILIA_TEST_ASTRA_FUSION"] == "1" else { throw XCTSkip("Opt-in paid Astra policy integration") }
        let env = try String(contentsOfFile: ".env", encoding: .utf8)
        let key = env.components(separatedBy: .newlines).first { $0.hasPrefix("OPENAI_API_KEY=") }.map { String($0.dropFirst(15)) } ?? ""
        // Explicit test metadata, not recorded model output or a detection-accuracy claim.
        var evidence = VoiceEvidenceWindow()
        evidence.append(result(true), audioEnd: 3); evidence.append(result(true), audioEnd: 6)
        let summary = evidence.summary(at: 7)
        let family = "Mom, it's your daughter. This is my new phone number. I wanted to talk with you about our family."
        let cases: [(String, String, VoiceEvidenceSummary?, Bool)] = [
            ("family-no-voice", family, nil, false),
            ("family-with-voice", family, summary, true),
            ("disclosed-assistive", "Mom, it's your daughter. I am using an assistive synthetic voice because I cannot speak today. Please call me on my usual number to verify.", summary, false),
            ("benign-synthetic", "This is an automated appointment reminder. Your appointment is tomorrow at ten.", summary, false),
            ("human-code-scam", "Please read me the login verification code so I can log into your bank account.", nil, true)
        ]
        for (name, transcript, voice, expected) in cases {
            let answer = try await AstraClient().assess(transcript: transcript, key: key, voiceEvidence: voice)
            print("Fusion policy \(name): warning=\(answer.warning), usesVoiceEvidence=\(answer.usesVoiceEvidence == true), reason=\(answer.reason)")
            XCTAssertEqual(WarningPolicy.grounded(answer, in: transcript), expected, name)
            if name == "family-with-voice" { XCTAssertEqual(answer.usesVoiceEvidence, true) }
        }
    }
    func result(_ flag: Bool, band: VoiceBandwidth = .wideband) -> VoiceModelResult {
        let decision = VoiceBandDecision(humanMargin: flag ? -0.2 : 0.05, syntheticFlag: flag, threshold: 0.9)
        return VoiceModelResult(modelId: "promotion-v8-reconstruction-20260910-seed-1", seed: 1, windowSeconds: 3, route: "v6", bandwidth: band, artifactScore: 0.001, bandwidthDecisions: ["wideband": decision, "narrowband": decision], humanMargin: band == .unknown ? nil : decision.humanMargin, syntheticFlag: band == .unknown ? nil : flag)
    }
    func testEvidenceExpiresResetsAndPreservesUnknown() {
        var evidence = VoiceEvidenceWindow()
        evidence.append(result(true), audioEnd: 3); evidence.append(result(true), audioEnd: 6)
        XCTAssertEqual(evidence.summary(at: 7)?.flaggedCount, 2)
        XCTAssertTrue(evidence.summary(at: 7)!.supportsSynthetic)
        XCTAssertNil(evidence.summary(at: 17))
        evidence.append(result(true, band: .unknown), audioEnd: 18)
        XCTAssertNil(evidence.summary(at: 18)?.flaggedCount)
        XCTAssertFalse(evidence.summary(at: 18)!.supportsSynthetic)
        evidence.clear(); XCTAssertNil(evidence.summary(at: 18))
    }
    func testNegativeLatestResultClearsSupportAndCountIsBounded() {
        var evidence = VoiceEvidenceWindow()
        for i in 1...20 { evidence.append(result(true), audioEnd: Double(i * 3)) }
        XCTAssertEqual(evidence.summary(at: 60)?.observationCount, 6)
        evidence.append(result(false), audioEnd: 63)
        XCTAssertFalse(evidence.summary(at: 63)!.supportsSynthetic)
    }
    func testThreeSecondWindowsPreserveSilenceAndSeparateSources() {
        var buffer = VoicePCMAccumulator()
        XCTAssertTrue(buffer.append([0,0,0,0], sampleRate: 2, channels: 1, start: 0, source: "mic").isEmpty)
        let windows = buffer.append([1,2], sampleRate: 2, channels: 1, start: 2, source: "mic")
        XCTAssertEqual(windows.first?.samples, [0,0,0,0,1,2]); XCTAssertEqual(windows.first?.end, 3)
        XCTAssertTrue(windows.first!.hasSignal)
        XCTAssertFalse(VoicePCMWindow(samples: [0,0,0], sampleRate: 1, channels: 1, end: 3).hasSignal)
        _ = buffer.append([9,9], sampleRate: 2, channels: 1, start: 3, source: "mic")
        XCTAssertTrue(buffer.append([1,1,1,1], sampleRate: 2, channels: 1, start: 4, source: "system").isEmpty)
        XCTAssertTrue(buffer.append([1,1], sampleRate: 2, channels: 1, start: 10, source: "system").isEmpty)
    }
    func testAstraGetsSignedEvidenceSeparateFromTranscript() throws {
        var evidence = VoiceEvidenceWindow(); evidence.append(result(true), audioEnd: 3)
        let body = AstraClient.requestBody(transcript: "Mom, it is your daughter.", voiceEvidence: evidence.summary(at: 4))
        let input = try XCTUnwrap(body["input"] as? [[String: String]])
        XCTAssertEqual(input[0]["content"], "Mom, it is your daughter.")
        XCTAssertEqual(input[1]["role"], "developer")
        XCTAssertTrue(input[1]["content"]!.contains("meanHumanMargin"))
        XCTAssertFalse(input[1]["content"]!.contains("artifactScore"))
    }
}
