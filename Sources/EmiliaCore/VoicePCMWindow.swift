import Foundation

public enum VoiceBandwidth: String, Codable, CaseIterable, Sendable {
    case unknown, wideband, narrowband
    public var label: String { self == .unknown ? "Unknown (no single flag)" : "Assume \(rawValue)" }
}
public struct VoiceBandDecision: Codable, Sendable {
    public let humanMargin: Double
    public let syntheticFlag: Bool
    public let threshold: Double
}
public struct VoiceModelResult: Codable, Sendable {
    public let modelId: String
    public let seed: Int
    public let windowSeconds: Int
    public let route: String
    public let bandwidth: VoiceBandwidth
    public let artifactScore: Double
    public let bandwidthDecisions: [String: VoiceBandDecision]
    public let humanMargin: Double?
    public let syntheticFlag: Bool?
    public var isValid: Bool {
        modelId == "promotion-v8-reconstruction-20260910-seed-1" && seed == 1 && windowSeconds == 3 && ["v6", "v7"].contains(route) && artifactScore.isFinite &&
        ["wideband", "narrowband"].allSatisfy { band in
            guard let value = bandwidthDecisions[band] else { return false }
            return value.humanMargin.isFinite && value.threshold.isFinite && value.syntheticFlag == (value.humanMargin < 0)
        } && (bandwidth == .unknown ? humanMargin == nil && syntheticFlag == nil : humanMargin?.isFinite == true && syntheticFlag == (humanMargin! < 0))
    }
}
public struct VoicePCMWindow: Sendable {
    public let samples: [Float]
    public let sampleRate: Int
    public let channels: Int
    public let end: Double
    /// Presentation/evidence quality only: still score the complete window unchanged.
    public var hasSignal: Bool { samples.contains { $0.isFinite && abs($0) > 0.00001 } }
    public init(samples: [Float], sampleRate: Int, channels: Int, end: Double) {
        self.samples = samples; self.sampleRate = sampleRate; self.channels = channels; self.end = end
    }
}
/// Nonoverlapping wall-clock windows. Gaps, source changes and format changes reset the buffer.
public struct VoicePCMAccumulator: Sendable {
    private var samples: [Float] = []
    private var rate = 0; private var channels = 0; private var source = ""
    private var start = 0.0; private var expected = 0.0
    public init() {}
    public mutating func append(_ pcm: [Float], sampleRate: Int, channels: Int, start: Double, source: String) -> [VoicePCMWindow] {
        guard (1...192000).contains(sampleRate), (1...8).contains(channels), pcm.count % channels == 0, start.isFinite else { return [] }
        if rate != sampleRate || self.channels != channels || self.source != source || abs(start - expected) > 0.1 {
            samples.removeAll(); self.start = start
        }
        rate = sampleRate; self.channels = channels; self.source = source
        expected = start + Double(pcm.count / channels) / Double(rate)
        samples.append(contentsOf: pcm)
        let size = rate * 3 * channels
        var result: [VoicePCMWindow] = []
        while samples.count >= size {
            result.append(VoicePCMWindow(samples: Array(samples.prefix(size)), sampleRate: rate, channels: channels, end: self.start + 3))
            samples.removeFirst(size); self.start += 3
        }
        return result
    }
}
