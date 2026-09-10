import AppKit
import AVFoundation
import Combine
import EmiliaCore

@MainActor
final class AppModel: ObservableObject {
    @Published var captureMode: CaptureMode = .microphone
    @Published var transcriptionMode: TranscriptionMode = .local {
        didSet { UserDefaults.standard.set(transcriptionMode.rawValue, forKey: "transcriptionMode") }
    }
    @Published var listening = false
    @Published var preparing = false
    @Published var status = "Ready when you are"
    @Published var transcript = ""
    @Published var warning: WarningEvidence?
    @Published var level: Float = 0
    @Published var elapsed: Double = 0
    @Published var apiLatency: Double?
    @Published var assessments = 0
    @Published var voiceStatus = "Voice detector · not started"
    @Published var synthetic = false
    @Published var voiceChoice = VoiceDetectorChoice.baseline {
        didSet { UserDefaults.standard.set(voiceChoice.rawValue, forKey: "voiceDetectorChoice") }
    }
    @Published var voiceBandwidth: VoiceBandwidth = .unknown {
        didSet { UserDefaults.standard.set(voiceBandwidth.rawValue, forKey: "voiceBandwidth") }
    }
    @Published var keyConfigured = false
    @Published var settingsVisible = false
    @Published var errorMessage: String?
    @Published var degraded = false
    private let capture = AudioCapture()
    private var speech: SpeechPipeline?
    private let voice = VoiceDetector()
    private var baseline = BaselineDetector()
    private var window = TranscriptWindow()
    private var policy = WarningPolicy()
    private var voiceEvidence = VoiceEvidenceWindow()
    private var lastVoiceRevision = ""
    private var sessionID = UUID()
    private var captureTask: Task<Void, Never>?
    private var voiceTask: Task<Void, Never>?
    private var startTask: Task<Void, Never>?
    private var riskTask: Task<Void, Never>?
    private var heartbeat: Task<Void, Never>?
    private var lastSubmitted = ""
    private var lastSubmission: Double = -.infinity
    private var epoch = 0.0
    private var lastAudio = 0.0
    private var key = ""
    private var observer: NSObjectProtocol?
    var onWarning: ((WarningEvidence) -> Void)?
    var onDismiss: (() -> Void)?

    init() {
        voiceChoice = VoiceDetectorChoice(rawValue: UserDefaults.standard.string(forKey: "voiceDetectorChoice") ?? "") ?? .baseline
        transcriptionMode = TranscriptionMode(rawValue: UserDefaults.standard.string(forKey: "transcriptionMode") ?? "") ?? .local
        voiceBandwidth = VoiceBandwidth(rawValue: UserDefaults.standard.string(forKey: "voiceBandwidth") ?? "") ?? .unknown
        key = Environment.readKey(); keyConfigured = !key.isEmpty
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.stop(); self?.status = "Paused for sleep — start again when ready" }
        }
    }
    func saveKey(_ value: String) {
        do { try KeyStore.save(value); key = Environment.readKey(); keyConfigured = !key.isEmpty; errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }
    func start() {
        guard !listening, !preparing else { return }
        key = Environment.readKey(); keyConfigured = !key.isEmpty
        let mode = captureMode
        let transcription = transcriptionMode
        let bandwidth = voiceBandwidth
        let detectorChoice = voiceChoice
        let baseline = BaselineDetector(); self.baseline = baseline
        if transcription == .realtime && !keyConfigured { settingsVisible = true; errorMessage = "Add an API key to use OpenAI Realtime."; return }
        sessionID = UUID(); let token = sessionID
        preparing = true; errorMessage = nil; degraded = false
        status = transcription == .local ? "Loading local Whisper…" : "Connecting to OpenAI Realtime…"
        window.clear(); transcript = ""; policy = WarningPolicy(); warning = nil
        voiceEvidence.clear(); synthetic = false; lastVoiceRevision = ""
        lastSubmitted = ""; lastSubmission = -.infinity; assessments = 0; apiLatency = nil; elapsed = 0
        startTask = Task {
            let pipeline = SpeechPipeline(mode: transcription, key: key)
            do {
                voiceStatus = "Loading \(detectorChoice.label)…"
                status = voiceStatus
                var voiceReady = false
                do {
                    let version: String?
                    if detectorChoice == .baseline { try await baseline.load(); version = "AASIST-L baseline · local Core ML" }
                    else { version = try await voice.load() }
                    voiceReady = version != nil
                    guard sessionID == token, !Task.isCancelled else { return }
                    voiceStatus = version.map { detectorChoice == .baseline ? $0 : "\($0) · \(bandwidth.label)" } ?? "Emilia v8 not installed"
                } catch {
                    guard sessionID == token, !Task.isCancelled else { return }
                    voiceStatus = "Voice detector unavailable: \(error.localizedDescription)"
                }
                status = transcription == .local ? "Loading local Whisper…" : "Connecting to OpenAI Realtime…"
                try await pipeline.prepare(onTranscript: { [weak self] segment in
                    Task { @MainActor in self?.receive(segment, token: token) }
                }, onError: { [weak self] message in
                    Task { @MainActor in
                        guard let self, self.sessionID == token else { return }
                        self.stop(); self.errorMessage = message; self.status = "Transcription unavailable"
                    }
                })
                guard sessionID == token, !Task.isCancelled else { pipeline.stop(); return }
                let stream = try await capture.start(mode: mode)
                guard sessionID == token, !Task.isCancelled else { capture.stop(); pipeline.stop(); return }
                speech = pipeline; epoch = ProcessInfo.processInfo.systemUptime; lastAudio = epoch
                listening = true; preparing = false; status = "Listening · \(mode.rawValue)"
                captureTask = Task.detached(priority: .userInitiated) { [weak self, voiceReady] in
                    var accumulator = VoicePCMAccumulator(windowSeconds: detectorChoice.windowSeconds)
                    var lastMeter = 0.0
                    do {
                        for await item in stream {
                            try Task.checkCancellation()
                            try pipeline.append(item)
                            let samples = try item.interleavedFloatPCM()
                                let rms = sqrt(samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(max(1, samples.count)))
                                if item.time - lastMeter >= 0.1 {
                                    lastMeter = item.time
                                    await self?.meter(rms, token: token, dropped: pipeline.dropped)
                                }
                                if voiceReady {
                                    let windows = accumulator.append(samples, sampleRate: Int(item.pcm.format.sampleRate), channels: Int(item.pcm.format.channelCount), start: item.time, source: mode.rawValue)
                                    for window in windows { await self?.scheduleVoice(window, bandwidth: bandwidth, choice: detectorChoice, baseline: baseline, token: token) }
                                }
                        }
                    } catch {
                        if !Task.isCancelled { await self?.captureFailed(error.localizedDescription, token: token) }
                    }
                }
                heartbeat = Task {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(1))
                        guard sessionID == token, listening, !Task.isCancelled else { return }
                        let now = ProcessInfo.processInfo.systemUptime
                        elapsed = now - epoch; window.prune(at: elapsed); transcript = window.text
                        refreshVoiceEvidence(at: elapsed)
                        if now - lastAudio > 8 { degraded = true; status = "No audio arriving — check playback and permission" }
                        submitIfNeeded(token: token, source: mode.rawValue)
                    }
                }
            } catch {
                pipeline.stop()
                guard sessionID == token else { return }
                stop(); errorMessage = error.localizedDescription; status = "Couldn’t start listening"
            }
        }
    }
    private func receive(_ segment: TranscriptSegment, token: UUID) {
        guard sessionID == token, listening else { return }
        window.update(segment); transcript = window.text
        if let warning, !WarningPolicy.grounded(warning.assessment, in: transcript) {
            self.warning = nil; onDismiss?()
        }
    }
    private func meter(_ rms: Float, token: UUID, dropped: Int) {
        guard sessionID == token, listening else { return }
        level = min(1, rms * 10); lastAudio = ProcessInfo.processInfo.systemUptime
        if dropped > 0 || capture.droppedBuffers > 0 { degraded = true; status = "Coverage degraded — audio buffers dropped" }
        else if degraded && errorMessage == nil { degraded = false; status = "Listening" }
    }
    private func setVoiceStatus(_ value: String, token: UUID) { guard sessionID == token else { return }; voiceStatus = value }
    private func scheduleVoice(_ window: VoicePCMWindow, bandwidth: VoiceBandwidth, choice: VoiceDetectorChoice, baseline: BaselineDetector, token: UUID) {
        guard sessionID == token, listening, voiceTask == nil else { return }
        voiceTask = Task {
            defer { if sessionID == token { voiceTask = nil } }
            do {
                if choice == .baseline {
                    let score = try await baseline.score(window)
                    guard sessionID == token, listening else { return }
                    if window.hasSignal { voiceEvidence.appendBaseline(score: score, audioEnd: window.end) }
                    refreshVoiceEvidence(at: max(window.end, ProcessInfo.processInfo.systemUptime-epoch))
                    voiceStatus = "AASIST-L baseline · " + (synthetic ? "Synthetic voice evidence" : "No fresh synthetic flag")
                    return
                }
                let result = try await voice.score(window, bandwidth: bandwidth)
                guard window.hasSignal else {
                    if sessionID == token { refreshVoiceEvidence(at: ProcessInfo.processInfo.systemUptime - epoch) }
                    return
                }
                voiceResult(result, audioEnd: window.end, token: token)
            } catch {
                guard sessionID == token, listening else { return }
                voiceEvidence.clear(); synthetic = false
                voiceStatus = "Voice detector unavailable: \(error.localizedDescription)"
                refreshVoiceEvidence(at: elapsed)
            }
        }
    }
    private func voiceResult(_ result: VoiceModelResult, audioEnd: Double, token: UUID) {
        guard sessionID == token, listening else { return }
        voiceEvidence.append(result, audioEnd: audioEnd)
        refreshVoiceEvidence(at: max(audioEnd, ProcessInfo.processInfo.systemUptime - epoch))
        if result.bandwidth == .unknown {
            let wide = result.bandwidthDecisions["wideband"]?.syntheticFlag == true ? "flag" : "no flag"
            let narrow = result.bandwidthDecisions["narrowband"]?.syntheticFlag == true ? "flag" : "no flag"
            voiceStatus = "Emilia v8 · bandwidth unknown · wide: \(wide), narrow: \(narrow)"
        } else {
            voiceStatus = "Emilia v8 · \(result.bandwidth.label) · " + (synthetic ? "Synthetic voice evidence" : "No synthetic flag in latest window")
        }
    }
    private func refreshVoiceEvidence(at now: Double) {
        let summary = voiceEvidence.summary(at: now)
        synthetic = summary?.supportsSynthetic == true
        if summary == nil && voiceStatus.contains("Synthetic voice evidence") { voiceStatus = "\(voiceChoice == .baseline ? "AASIST-L baseline" : "Emilia v8") · waiting for fresh voice evidence" }
        if warning?.assessment.usesVoiceEvidence == true && !synthetic { warning = nil; onDismiss?() }
    }
    private func captureFailed(_ message: String, token: UUID) {
        guard sessionID == token else { return }; stop(); errorMessage = message; status = "Audio processing unavailable"
    }
    private func submitIfNeeded(token: UUID, source: String) {
        guard keyConfigured else { errorMessage = "Whisper is listening locally. Add an API key for scam analysis."; return }
        let summary = voiceEvidence.summary(at: elapsed)
        let voiceRevision = summary?.revision ?? ""
        guard riskTask == nil, transcript.count >= 20, transcript != lastSubmitted || voiceRevision != lastVoiceRevision,
              elapsed - lastSubmission >= 3 else { return }
        // Absolute request ceiling for a single listening session; no unbounded paid background loop.
        guard assessments < 120 else { stop(); status = "Session analysis limit reached — restart to continue"; return }
        let snapshot = transcript
        let start = window.segments.first?.start ?? 0, end = window.segments.last?.end ?? elapsed
        lastSubmitted = snapshot; lastSubmission = elapsed; assessments += 1
        lastVoiceRevision = voiceRevision
        riskTask = Task {
            let began = ProcessInfo.processInfo.systemUptime
            defer { if sessionID == token { riskTask = nil } }
            do {
                let result = try await AstraClient().assess(transcript: snapshot, key: key, voiceEvidence: summary)
                guard sessionID == token, listening, !Task.isCancelled else { return }
                apiLatency = ProcessInfo.processInfo.systemUptime - began
                errorMessage = nil
                if result.usesVoiceEvidence == true {
                    guard let summary, summary.supportsSynthetic, summary.observationCount >= 2,
                          voiceEvidence.summary(at: ProcessInfo.processInfo.systemUptime - epoch)?.supportsSynthetic == true,
                          ProcessInfo.processInfo.systemUptime - epoch - summary.latestAudioEnd <= 10 else { return }
                    let recentText = window.segments.filter { $0.end >= summary.latestAudioEnd - 30 }.map(\.text).joined(separator: " ")
                    guard WarningPolicy.grounded(result, in: recentText) else { return }
                }
                // Reject invented evidence, ASR-retracted quotes and answers that have become stale.
                guard elapsed - end <= 30, WarningPolicy.grounded(result, in: snapshot),
                      WarningPolicy.grounded(result, in: transcript) else { return }
                if policy.consider(result, transcript: transcript, now: elapsed) {
                    let evidence = WarningEvidence(assessment: result, audioStart: start, audioEnd: end, source: source, modelVersion: AstraClient.model, voiceEvidence: summary)
                    warning = evidence; onWarning?(evidence)
                }
            } catch {
                guard sessionID == token, !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                // Allow a retry of the latest context after a bounded backoff.
                lastSubmitted = ""; lastSubmission = elapsed + 7
            }
        }
    }
    func dismissWarning() { warning = nil; onDismiss?() }
    func stop() {
        sessionID = UUID()
        startTask?.cancel(); startTask = nil; heartbeat?.cancel(); heartbeat = nil
        riskTask?.cancel(); riskTask = nil
        capture.stop(); captureTask?.cancel(); captureTask = nil
        voiceTask?.cancel(); voiceTask = nil; voice.stop()
        let oldBaseline = baseline; Task { await oldBaseline.stop() }
        speech?.stop(); speech = nil
        listening = false; preparing = false; level = 0; status = "Paused"
        window.clear(); transcript = ""; lastSubmitted = ""; warning = nil; synthetic = false
        voiceEvidence.clear(); lastVoiceRevision = ""; voiceStatus = "Voice detection paused"
        onDismiss?()
    }
}
