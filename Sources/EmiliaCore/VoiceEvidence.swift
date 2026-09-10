import Foundation

/// Descriptive detector evidence, never a calibrated probability of fraud or identity.
public struct VoiceEvidenceSummary: Codable, Equatable, Sendable {
    public var detectorKind = "emilia_v8"
    public var meanBaselineScore: Double? = nil
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
    public var supportsSynthetic: Bool { (detectorKind == "aasist_l_baseline" || bandwidth != .unknown) && latestFlagged == true && ageSeconds <= 10 && (flaggedCount ?? 0) * 2 > observationCount }
    public var revision: String { "\(latestAudioEnd):\(observationCount):\(flaggedCount):\(supportsSynthetic)" }
}

public struct VoiceEvidenceWindow: Sendable {
    private struct Observation: Sendable { let end: Double; let result: VoiceModelResult }
    private var observations: [Observation] = []
    private var baseline: [(end: Double, score: Double)] = []
    public init() {}
    public mutating func append(_ result: VoiceModelResult, audioEnd: Double) {
        guard result.isValid, audioEnd.isFinite, audioEnd >= 0,
              audioEnd > (observations.last?.end ?? -.infinity) else { return }
        baseline.removeAll()
        if observations.last?.result.modelId != result.modelId || observations.last?.result.bandwidth != result.bandwidth { observations.removeAll() }
        observations.append(Observation(end: audioEnd, result: result))
        observations.removeAll { $0.end < audioEnd - 30 }
        observations = Array(observations.suffix(6))
    }
    public func summary(at now: Double) -> VoiceEvidenceSummary? {
        if let last = baseline.last {
            guard now.isFinite, now >= last.end, now - last.end <= 10 else { return nil }
            let recent = baseline.filter { now - $0.end <= 30 }
            return VoiceEvidenceSummary(detectorKind: "aasist_l_baseline", meanBaselineScore: recent.map(\.score).reduce(0,+) / Double(recent.count),
                modelVersion: "aasist-l-a04c986-coreml-v1", observationCount: recent.count, bandwidth: .unknown,
                flaggedCount: recent.filter { $0.score >= 0.5 }.count, meanHumanMargin: nil,
                latestFlagged: last.score >= 0.5, widebandFlaggedCount: 0, narrowbandFlaggedCount: 0,
                latestAudioEnd: last.end, ageSeconds: now-last.end, windowSeconds: 30)
        }
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
    public mutating func appendBaseline(score: Double, audioEnd: Double) {
        guard score.isFinite, (0...1).contains(score), audioEnd.isFinite, audioEnd >= 0,
              audioEnd > (baseline.last?.end ?? -.infinity) else { return }
        observations.removeAll()
        baseline.append((audioEnd,score)); baseline.removeAll { $0.end < audioEnd-30 }
        baseline = Array(baseline.suffix(6))
    }
    public mutating func clear() { observations.removeAll(); baseline.removeAll() }
}
