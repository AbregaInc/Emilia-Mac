import Foundation

/// Descriptive detector evidence, never a calibrated probability of fraud or identity.
public struct VoiceEvidenceSummary: Codable, Equatable, Sendable {
    public let modelVersion: String
    public let observationCount: Int
    public let bandwidth: VoiceBandwidth
    public let flaggedCount: Int?
    public let meanHumanMargin: Double?
    public let latestFlagged: Bool?
    public let widebandFlaggedCount: Int
    public let narrowbandFlaggedCount: Int
    public let latestAudioEnd: Double
    public let ageSeconds: Double
    public let windowSeconds: Double
    public var interpretation: String { "Signed margins, not probabilities. Bandwidth is an explicit assumption; unknown has no single classification. Mixed captured audio has no speaker attribution. Observations may be correlated. Artifact scores only route the model and are excluded." }
    public var supportsSynthetic: Bool { bandwidth != .unknown && latestFlagged == true && ageSeconds <= 10 && (flaggedCount ?? 0) * 2 > observationCount }
    public var revision: String { "\(latestAudioEnd):\(observationCount):\(flaggedCount):\(supportsSynthetic)" }
}

public struct VoiceEvidenceWindow: Sendable {
    private struct Observation: Sendable { let end: Double; let result: VoiceModelResult }
    private var observations: [Observation] = []
    public init() {}
    public mutating func append(_ result: VoiceModelResult, audioEnd: Double) {
        guard result.isValid, audioEnd.isFinite, audioEnd >= 0,
              audioEnd > (observations.last?.end ?? -.infinity) else { return }
        if observations.last?.result.modelId != result.modelId || observations.last?.result.bandwidth != result.bandwidth { observations.removeAll() }
        observations.append(Observation(end: audioEnd, result: result))
        observations.removeAll { $0.end < audioEnd - 30 }
        observations = Array(observations.suffix(6))
    }
    public func summary(at now: Double) -> VoiceEvidenceSummary? {
        guard now.isFinite, let last = observations.last, now >= last.end, now - last.end <= 10 else { return nil }
        let recent = observations.filter { now - $0.end <= 30 }
        return VoiceEvidenceSummary(modelVersion: last.result.modelId, observationCount: recent.count, bandwidth: last.result.bandwidth,
            flaggedCount: last.result.bandwidth == .unknown ? nil : recent.filter { $0.result.syntheticFlag == true }.count,
            meanHumanMargin: last.result.bandwidth == .unknown ? nil : recent.compactMap { $0.result.humanMargin }.reduce(0, +) / Double(recent.count),
            latestFlagged: last.result.syntheticFlag,
            widebandFlaggedCount: recent.filter { $0.result.bandwidthDecisions["wideband"]?.syntheticFlag == true }.count,
            narrowbandFlaggedCount: recent.filter { $0.result.bandwidthDecisions["narrowband"]?.syntheticFlag == true }.count,
            latestAudioEnd: last.end, ageSeconds: now - last.end, windowSeconds: 30)
    }
    public mutating func clear() { observations.removeAll() }
}
