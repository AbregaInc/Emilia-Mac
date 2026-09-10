import Foundation

public struct TranscriptSegment: Equatable, Sendable {
    public var id: String?
    public var start: Double
    public var end: Double
    public var text: String
    public init(start: Double, end: Double, text: String, id: String? = nil) {
        self.start = start; self.end = end; self.text = text; self.id = id
    }
}

/// Revisions replace overlapping audio intervals; retained context is bounded in time and size.
public struct TranscriptWindow: Sendable {
    public private(set) var segments: [TranscriptSegment] = []
    public let retention: Double
    public let characterLimit: Int
    public init(retention: Double = 120, characterLimit: Int = 6000) {
        self.retention = retention; self.characterLimit = characterLimit
    }
    public mutating func update(_ segment: TranscriptSegment) {
        guard segment.start.isFinite, segment.end.isFinite, segment.end >= segment.start else { return }
        if let id = segment.id { segments.removeAll { $0.id == id } }
        else { segments.removeAll { $0.start < segment.end && $0.end > segment.start || $0.start == segment.start } }
        segments.append(segment)
        segments.sort { $0.start < $1.start }
        prune(at: segments.map(\.end).max() ?? segment.end)
    }
    public mutating func prune(at time: Double) {
        segments.removeAll { $0.end < time - retention }
        while segments.count > 1 && segments.reduce(0, { $0 + $1.text.count }) > characterLimit { segments.removeFirst() }
        if segments.count == 1 { segments[0].text = String(segments[0].text.suffix(characterLimit)) }
    }
    public var text: String { segments.map(\.text).joined(separator: " ") }
    public mutating func clear() { segments.removeAll(keepingCapacity: false) }
}

public enum RiskCategory: String, Codable, CaseIterable, Sendable {
    case credentialRequest = "credential_request"
    case paymentPressure = "payment_pressure"
    case remoteAccess = "remote_access"
    case secrecy, impersonation, none
}

public struct RiskAssessment: Codable, Equatable, Sendable {
    public var warning: Bool
    public var category: RiskCategory
    public var reason: String
    public var quotes: [String]
    public init(warning: Bool, category: RiskCategory, reason: String, quotes: [String]) {
        self.warning = warning; self.category = category; self.reason = reason; self.quotes = quotes
    }
}

public struct WarningEvidence: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let assessment: RiskAssessment
    public let audioStart: Double
    public let audioEnd: Double
    public let emittedAt: Date
    public let source: String
    public let modelVersion: String
    public let policyVersion = "emilia-warning-v1"
    public init(assessment: RiskAssessment, audioStart: Double, audioEnd: Double, source: String, modelVersion: String) {
        id = UUID(); self.assessment = assessment; self.audioStart = audioStart; self.audioEnd = audioEnd
        self.source = source; self.modelVersion = modelVersion; emittedAt = Date()
    }
}

/// Only conversational evidence can trigger a red warning. Voice scores have no input here.
public struct WarningPolicy: Sendable {
    private var seen: Set<RiskCategory> = []
    private var lastAlert: Double = -.infinity
    public let cooldown: Double
    public init(cooldown: Double = 15) { self.cooldown = cooldown }
    public static func grounded(_ assessment: RiskAssessment, in transcript: String) -> Bool {
        guard assessment.warning, assessment.category != .none, !assessment.reason.isEmpty,
              !assessment.quotes.isEmpty, assessment.quotes.count <= 3 else { return false }
        let text = normalized(transcript)
        return assessment.quotes.allSatisfy { quote in
            let value = normalized(quote)
            return value.count >= 8 && text.contains(value)
        }
    }
    public mutating func consider(_ assessment: RiskAssessment, transcript: String, now: Double) -> Bool {
        guard Self.grounded(assessment, in: transcript), !seen.contains(assessment.category),
              now - lastAlert >= cooldown else { return false }
        seen.insert(assessment.category); lastAlert = now
        return true
    }
    public static func normalized(_ text: String) -> String {
        text.lowercased().components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }
}

public struct AudioRing: Sendable {
    private var storage: [Float]
    private var cursor = 0
    public private(set) var count = 0
    public init(capacity: Int) { storage = Array(repeating: 0, count: max(1, capacity)) }
    public mutating func append(_ samples: [Float]) {
        for sample in samples { storage[cursor] = sample; cursor = (cursor + 1) % storage.count; count = min(count + 1, storage.count) }
    }
    public func suffix(_ limit: Int) -> [Float] {
        let n = min(count, max(0, limit))
        return (0..<n).map { storage[(cursor - n + $0 + storage.count) % storage.count] }
    }
    public mutating func clear() { storage = Array(repeating: 0, count: storage.count); cursor = 0; count = 0 }
}
