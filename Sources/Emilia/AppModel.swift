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
    @Published var voiceStatus = "Model not installed"
    @Published var synthetic = false
    @Published var keyConfigured = false
    @Published var settingsVisible = false
    @Published var errorMessage: String?
    @Published var degraded = false
    private let capture = AudioCapture()
    private var speech: SpeechPipeline?
    private let voice = VoiceDetector()
    private var window = TranscriptWindow()
    private var policy = WarningPolicy()
    private var sessionID = UUID()
    private var captureTask: Task<Void, Never>?
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
        transcriptionMode = TranscriptionMode(rawValue: UserDefaults.standard.string(forKey: "transcriptionMode") ?? "") ?? .local
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
        if transcription == .realtime && !keyConfigured { settingsVisible = true; errorMessage = "Add an API key to use OpenAI Realtime."; return }
        sessionID = UUID(); let token = sessionID
        preparing = true; errorMessage = nil; degraded = false
        status = transcription == .local ? "Loading local Whisper…" : "Connecting to OpenAI Realtime…"
        window.clear(); transcript = ""; policy = WarningPolicy(); warning = nil
        lastSubmitted = ""; lastSubmission = -.infinity; assessments = 0; apiLatency = nil; elapsed = 0
        startTask = Task {
            let pipeline = SpeechPipeline(mode: transcription, key: key)
            do {
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
                captureTask = Task.detached(priority: .userInitiated) { [weak self, voice] in
                    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
                    let converter = PCMConverter(outputFormat: format)
                    var ring = AudioRing(capacity: 16000 * 30)
                    var lastScore = 0.0; var lastMeter = 0.0
                    var voiceReady = false
                    do {
                        let version = try await voice.load(); voiceReady = version != nil
                        await self?.setVoiceStatus(version.map { "Ready · \($0)" } ?? "Model not installed", token: token)
                    } catch { await self?.setVoiceStatus(error.localizedDescription, token: token) }
                    do {
                        for await item in stream {
                            try Task.checkCancellation()
                            try pipeline.append(item)
                            let buffer = try converter.convert(item.pcm)
                            if let channel = buffer.floatChannelData?[0] {
                                let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
                                ring.append(samples)
                                let rms = sqrt(samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(max(1, samples.count)))
                                if item.time - lastMeter >= 0.1 {
                                    lastMeter = item.time
                                    await self?.meter(rms, token: token, dropped: pipeline.dropped)
                                }
                                if voiceReady, item.time - lastScore >= 5, ring.count >= 80000, rms > 0.003 {
                                    lastScore = item.time
                                    if let result = try await voice.score(ring.suffix(80000)) {
                                        await self?.voiceResult(result, token: token)
                                    }
                                }
                            }
                        }
                    } catch {
                        if !Task.isCancelled { await self?.captureFailed(error.localizedDescription, token: token) }
                    }
                    ring.clear()
                }
                heartbeat = Task {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(1))
                        guard sessionID == token, listening, !Task.isCancelled else { return }
                        let now = ProcessInfo.processInfo.systemUptime
                        elapsed = now - epoch; window.prune(at: elapsed); transcript = window.text
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
    private func voiceResult(_ result: (Double, Bool), token: UUID) {
        guard sessionID == token, listening else { return }
        synthetic = result.1
        voiceStatus = result.1 ? "Synthetic voice evidence" : "No synthetic flag in latest window"
    }
    private func captureFailed(_ message: String, token: UUID) {
        guard sessionID == token else { return }; stop(); errorMessage = message; status = "Audio processing unavailable"
    }
    private func submitIfNeeded(token: UUID, source: String) {
        guard keyConfigured else { errorMessage = "Whisper is listening locally. Add an API key for scam analysis."; return }
        guard riskTask == nil, transcript.count >= 20, transcript != lastSubmitted,
              elapsed - lastSubmission >= 3 else { return }
        // Absolute request ceiling for a single listening session; no unbounded paid background loop.
        guard assessments < 120 else { stop(); status = "Session analysis limit reached — restart to continue"; return }
        let snapshot = transcript
        let start = window.segments.first?.start ?? 0, end = window.segments.last?.end ?? elapsed
        lastSubmitted = snapshot; lastSubmission = elapsed; assessments += 1
        riskTask = Task {
            let began = ProcessInfo.processInfo.systemUptime
            defer { if sessionID == token { riskTask = nil } }
            do {
                let result = try await AstraClient().assess(transcript: snapshot, key: key)
                guard sessionID == token, listening, !Task.isCancelled else { return }
                apiLatency = ProcessInfo.processInfo.systemUptime - began
                errorMessage = nil
                // Reject invented evidence, ASR-retracted quotes and answers that have become stale.
                guard elapsed - end <= 30, WarningPolicy.grounded(result, in: snapshot),
                      WarningPolicy.grounded(result, in: transcript) else { return }
                if policy.consider(result, transcript: transcript, now: elapsed) {
                    let evidence = WarningEvidence(assessment: result, audioStart: start, audioEnd: end, source: source, modelVersion: AstraClient.model)
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
        speech?.stop(); speech = nil
        listening = false; preparing = false; level = 0; status = "Paused"
        window.clear(); transcript = ""; lastSubmitted = ""; warning = nil; synthetic = false
        onDismiss?()
    }
}
