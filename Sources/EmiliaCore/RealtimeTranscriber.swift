import Foundation

public enum TranscriptionMode: String, CaseIterable, Identifiable, Sendable {
    case local = "Local Whisper"
    case realtime = "OpenAI Realtime"
    public var id: String { rawValue }
}

public enum RealtimeError: LocalizedError {
    case server(String), disconnected, backlog
    public var errorDescription: String? {
        switch self {
        case .server(let code): return "Realtime transcription unavailable (\(code))."
        case .disconnected: return "Realtime transcription disconnected. Pause and start to reconnect."
        case .backlog: return "Realtime upload fell behind. Pause and start to reconnect."
        }
    }
}

/// Correlates partial/final events by item ID, including completions arriving out of order.
public struct RealtimeTranscriptState {
    private struct Item { var start: Double; var end: Double?; var text = ""; var complete = false }
    private var items: [String: Item] = [:]
    private var order: [String] = []
    public init() {}
    public mutating func receive(_ event: [String: Any], audioEnd: Double, turnStart: Double = 0) -> TranscriptSegment? {
        guard let id = event["item_id"] as? String, let type = event["type"] as? String else { return nil }
        if items[id] == nil {
            let start = (event["audio_start_ms"] as? Double).map { $0 / 1000 } ?? turnStart
            items[id] = Item(start: start, end: nil); order.append(id)
            while order.count > 64 { items.removeValue(forKey: order.removeFirst()) }
        }
        guard var item = items[id] else { return nil }
        if type == "input_audio_buffer.speech_started" {
            item.start = (event["audio_start_ms"] as? Double).map { $0 / 1000 } ?? item.start
        } else if type == "input_audio_buffer.speech_stopped" {
            item.end = (event["audio_end_ms"] as? Double).map { $0 / 1000 } ?? audioEnd
        } else if type == "conversation.item.input_audio_transcription.delta", !item.complete {
            item.text = String((item.text + (event["delta"] as? String ?? "")).suffix(6000))
        } else if type == "conversation.item.input_audio_transcription.completed" {
            item.text = String((event["transcript"] as? String ?? "").suffix(6000)); item.complete = true
        }
        items[id] = item
        guard type.hasPrefix("conversation.item.input_audio_transcription."), !item.text.isEmpty else { return nil }
        return TranscriptSegment(start: item.start, end: max(item.start, min(item.end ?? audioEnd, audioEnd)), text: item.text, id: id)
    }
}

public struct RealtimeAudioPacket: Sendable {
    public let pcm16: Data
    public let end: Double
    public let speech: Bool
    public init(pcm16: Data, end: Double, speech: Bool = true) { self.pcm16 = pcm16; self.end = end; self.speech = speech }
    public static func encode(_ samples: [Float]) -> Data {
        var data = Data(capacity: samples.count * 2)
        for sample in samples {
            let finite = sample.isFinite ? sample : 0
            let clamped = max(-1, min(1, finite))
            var value = Int16(max(-32768, min(32767, Int((clamped * 32768).rounded())))).littleEndian
            withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        }
        return data
    }
}

public actor RealtimeTranscriber {
    public static let model = "gpt-live-transcribe"
    private var socket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var receiver: Task<Void, Never>?
    private var sender: Task<Void, Never>?
    private var audioEnd = 0.0
    private var turnStart = 0.0
    private var hadSpeech = false
    private var lastSpeech = 0.0
    private var committedTurns: [(Double, Double)] = []
    private var transcriptState = RealtimeTranscriptState()
    public init() {}
    public static func configuration() -> [String: Any] {
        ["type": "session.update", "session": [
            "type": "transcription", "audio": ["input": [
                "format": ["type": "audio/pcm", "rate": 24000],
                "transcription": ["model": model, "languages": ["en"], "delay": "low"],
                "turn_detection": NSNull()
            ]]
        ]]
    }
    public func connect(key: String, packets: AsyncStream<RealtimeAudioPacket>,
                        onTranscript: @escaping @Sendable (TranscriptSegment) -> Void,
                        onError: @escaping @Sendable (String) -> Void) async throws {
        guard !key.isEmpty else { throw AstraError.missingKey }
        var request = URLRequest(url: URL(string: "wss://api.openai.com/v1/realtime?intent=transcription")!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20
        let session = URLSession(configuration: .ephemeral)
        self.session = session
        let socket = session.webSocketTask(with: request); self.socket = socket
        socket.maximumMessageSize = 1_000_000
        socket.resume()
        let handshakeTimeout = Task {
            try? await Task.sleep(for: .seconds(15))
            if !Task.isCancelled { socket.cancel(with: .goingAway, reason: nil) }
        }
        defer { handshakeTimeout.cancel() }
        try await send(Self.configuration(), socket: socket)
        // Do not report coverage until the server accepts the transcription configuration.
        while true {
            let event = try await receive(socket)
            if event["type"] as? String == "error" { throw serverError(event) }
            if event["type"] as? String == "session.updated" || event["type"] as? String == "transcription_session.updated" { break }
        }
        receiver = Task {
            do {
                while !Task.isCancelled {
                    let event = try await receive(socket)
                    if event["type"] as? String == "error" || event["type"] as? String == "conversation.item.input_audio_transcription.failed" { throw serverError(event) }
                    if event["type"] as? String == "input_audio_buffer.committed", let id = event["item_id"] as? String, !committedTurns.isEmpty {
                        let turn = committedTurns.removeFirst()
                        _ = transcriptState.receive(["type": "input_audio_buffer.speech_started", "item_id": id, "audio_start_ms": turn.0 * 1000], audioEnd: audioEnd)
                        _ = transcriptState.receive(["type": "input_audio_buffer.speech_stopped", "item_id": id, "audio_end_ms": turn.1 * 1000], audioEnd: audioEnd)
                    }
                    if let segment = transcriptState.receive(event, audioEnd: audioEnd, turnStart: turnStart), lastSpeech > 0 { onTranscript(segment) }
                }
            } catch { if !Task.isCancelled { onError(error.localizedDescription) } }
        }
        sender = Task {
            do {
                for await packet in packets {
                    try Task.checkCancellation()
                    // Max 30 minutes per session; the UI also stops at its analysis request ceiling.
                    guard packet.end <= 1800 else { throw RealtimeError.server("session limit reached") }
                    try await send(["type": "input_audio_buffer.append", "audio": packet.pcm16.base64EncodedString()], socket: socket)
                    audioEnd = packet.end
                    if packet.speech { hadSpeech = true; lastSpeech = audioEnd }
                    // Live-transcribe does not support server VAD. Deltas arrive before these
                    // app-managed commits; a pause or six-second boundary finalizes the turn.
                    if audioEnd - turnStart >= 6 || (hadSpeech && audioEnd - lastSpeech >= 0.7 && audioEnd - turnStart >= 1) {
                        if hadSpeech {
                            guard committedTurns.count < 64 else { throw RealtimeError.backlog }
                            committedTurns.append((turnStart, audioEnd))
                            try await send(["type": "input_audio_buffer.commit"], socket: socket)
                        } else { try await send(["type": "input_audio_buffer.clear"], socket: socket) }
                        turnStart = audioEnd; hadSpeech = false
                    }
                }
            } catch { if !Task.isCancelled { onError(error.localizedDescription) } }
        }
    }
    private func send(_ event: [String: Any], socket: URLSessionWebSocketTask) async throws {
        let data = try JSONSerialization.data(withJSONObject: event)
        try await socket.send(.string(String(decoding: data, as: UTF8.self)))
    }
    private func receive(_ socket: URLSessionWebSocketTask) async throws -> [String: Any] {
        let message = try await socket.receive()
        let data: Data
        switch message { case .data(let value): data = value; case .string(let value): data = Data(value.utf8); @unknown default: throw RealtimeError.disconnected }
        guard let event = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw RealtimeError.disconnected }
        return event
    }
    private func serverError(_ event: [String: Any]) -> RealtimeError {
        let error = event["error"] as? [String: Any]
        let code = error?["code"] as? String ?? "server error"
        let detail = String((error?["message"] as? String ?? "").prefix(300))
        return .server(detail.isEmpty ? code : "\(code): \(detail)")
    }
    public func stop() {
        receiver?.cancel(); receiver = nil; sender?.cancel(); sender = nil
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
        session?.invalidateAndCancel(); session = nil
        transcriptState = RealtimeTranscriptState(); audioEnd = 0; turnStart = 0; hadSpeech = false; committedTurns.removeAll()
    }
}
