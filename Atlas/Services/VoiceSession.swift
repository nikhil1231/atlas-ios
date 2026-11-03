import AVFoundation
import Combine
import Foundation

@MainActor
final class VoiceSession: ObservableObject {
    enum State: String { case disconnected = "Ready", connecting = "Connecting…", listening = "Listening", thinking = "Thinking…", speaking = "Atlas is speaking" }
    @Published private(set) var state: State = .disconnected
    @Published private(set) var transcript: [TranscriptLine] = []
    @Published var error: String?
    private var socket: URLSessionWebSocketTask?
    private let suppliedAudio: (any VoiceAudioPlaying)?
    private let eventSender: (([String: Any]) async throws -> Void)?
    init(audio: (any VoiceAudioPlaying)? = nil, sendEvent: (([String: Any]) async throws -> Void)? = nil) {
        suppliedAudio = audio
        eventSender = sendEvent
    }
    private lazy var audio: any VoiceAudioPlaying = {
        let audio = suppliedAudio ?? VoiceAudio()
        audio.onPlaybackStarted = { [weak self] timing in
            guard let self else { return }
            self.telemetry.playback(timing)
            let now = Date()
            for id in self.pendingPresentedRequests { self.presentedRequests[id] = now }
            self.pendingPresentedRequests.removeAll()
            self.presentedRequests = self.presentedRequests.filter { now.timeIntervalSince($0.value) < 120 }
        }
        audio.onPlaybackFinished = { [weak self] in
            guard let self, self.isConnected else { return }
            self.state = self.responseActive ? .thinking : .listening
            let generation = self.sessionGeneration
            Task {
                guard generation == self.sessionGeneration else { return }
                try? await self.send(["type": "noodle.playback", "playing": false])
            }
        }
        return audio
    }()
    let telemetry = VoiceTelemetry()
    private let speechClock = LocalSpeechClock()
    private var pendingPresentedRequests: Set<String> = []
    private var presentedRequests: [String: Date] = [:]
    private var responseActive = false
    private var connectionTimeout: Task<Void, Never>?
    private var activeResponseID: String?
    private var interruptedResponses: Set<String> = []
    private var receiver: Task<Void, Never>?
    private var sender: Task<Void, Never>?
    private var continuation: AsyncStream<Data>.Continuation?
    private var sessionGeneration = UUID()
    var onRequest: ((TrackedRequest) -> Void)?
    var isConnected: Bool { state != .disconnected }

    func connect(api: AtlasAPI, question: TrackedRequest? = nil) async {
        guard !isConnected else { return }
        error = nil
        telemetry.reset(); speechClock.reset()
        state = .connecting
        let generation = UUID()
        sessionGeneration = generation
        let allowed = await AVAudioApplication.requestRecordPermission()
        guard generation == sessionGeneration, !Task.isCancelled else { return }
        guard allowed else { fail("Microphone access is required. Enable it in iOS Settings."); return }
        do {
            var request = try api.request("voice")
            var components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            components.scheme = "wss"
            components.queryItems = [.init(name: "tz", value: TimeZone.current.identifier),
                                     .init(name: "client_playback", value: "1")]
            if let question { components.queryItems?.append(.init(name: "question_id", value: question.id)) }
            request.url = components.url
            let socket = api.session.webSocketTask(with: request)
            self.socket = socket
            socket.resume()
            // Each connection has one ordered, bounded sender. A stalled network cannot grow RAM indefinitely.
            let (stream, continuation) = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingNewest(30))
            self.continuation = continuation
            sender = Task { [weak self] in
                do {
                    for await chunk in stream {
                        guard !Task.isCancelled, self?.sessionGeneration == generation else { break }
                        try await self?.send(["type": "input_audio_buffer.append", "audio": chunk.base64EncodedString()])
                    }
                } catch {
                    guard !Task.isCancelled, self?.sessionGeneration == generation else { return }
                    self?.fail("Voice upload stopped: \(error.localizedDescription)")
                }
            }
            connectionTimeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(20)) } catch { return }
                guard let self, generation == self.sessionGeneration, self.state == .connecting else { return }
                self.fail("Voice took too long to connect. Please try again.")
            }
            receiver = Task { [weak self] in
                guard let self else { return }
                do {
                    while !Task.isCancelled {
                        let message = try await socket.receive()
                        guard generation == self.sessionGeneration else { return }
                        let data: Data
                        switch message {
                        case .string(let text): data = Data(text.utf8)
                        case .data(let bytes): data = bytes
                        @unknown default: continue
                        }
                        guard let event = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                        try await self.handle(event, question: question)
                    }
                } catch {
                    if !Task.isCancelled, generation == self.sessionGeneration {
                        self.fail("Voice disconnected. Your submitted requests are still tracked. \(error.localizedDescription)")
                    }
                }
            }
        } catch { fail(error.localizedDescription) }
    }
    func handle(_ event: [String: Any], question: TrackedRequest?) async throws {
        switch event["type"] as? String {
        case "session.updated":
            guard state == .connecting else { return }
            connectionTimeout?.cancel(); connectionTimeout = nil
            let audioContinuation = continuation
            let generation = sessionGeneration
            let speechClock = self.speechClock
            try audio.start { [weak self] chunk in
                speechClock.observe(chunk)
                if let result = audioContinuation?.yield(chunk), case .dropped = result {
                    Task { @MainActor in
                        guard let self, self.sessionGeneration == generation else { return }
                        self.fail("The connection is too slow for live audio. Please reconnect.")
                    }
                }
            }
            state = .listening
            try await send(["type": "noodle.audio_ready"])
            // The server owns the greeting and persisted question context.
            if let question { append(id: "question-\(question.id)", role: "Atlas", text: question.title) }
        case "response.created":
            responseActive = true
            activeResponseID = (event["response"] as? [String: Any])?["id"] as? String
            if !audio.hasPendingAudio { state = .thinking }
        case "response.output_audio.delta", "response.audio.delta":
            if let id = event["response_id"] as? String, interruptedResponses.contains(id) { return }
            if let value = event["delta"] as? String, let data = Data(base64Encoded: value),
               let item = event["item_id"] as? String {
                let wasPlaying = audio.hasPendingAudio
                audio.enqueue(data, item: item)
                if !wasPlaying { try await send(["type": "noodle.playback", "playing": true]) }
                state = .speaking
            }
        case "input_audio_buffer.speech_started":
            if let id = activeResponseID { interruptedResponses.insert(id) }
            if interruptedResponses.count > 100 { interruptedResponses = Set(activeResponseID.map { [$0] } ?? []) }
            if let (item, milliseconds) = audio.interrupt() {
                try await send(["type": "conversation.item.truncate", "item_id": item,
                                "content_index": 0, "audio_end_ms": milliseconds])
            }
            try await send(["type": "noodle.playback", "playing": false])
            state = .listening
        case "input_audio_buffer.speech_stopped":
            telemetry.speechStopped(localEnd: speechClock.latest())
            state = .thinking
        case "response.done":
            responseActive = false
            activeResponseID = nil
            if !audio.hasPendingAudio { state = .listening }
            if let response = event["response"] as? [String: Any], response["status"] as? String == "failed" {
                error = "Atlas couldn’t respond. Please try again or send a message."
            }
        case "conversation.item.input_audio_transcription.completed":
            append(id: event["item_id"] as? String ?? UUID().uuidString, role: "You", text: event["transcript"] as? String ?? "")
        case "response.output_audio_transcript.delta", "response.audio_transcript.delta":
            append(id: event["item_id"] as? String ?? "assistant", role: "Atlas", text: event["delta"] as? String ?? "", delta: true)
        case "noodle.request":
            if let raw = event["request"] as? [String: Any] {
                let request = try mobileDecoder().decode(TrackedRequest.self, from: JSONSerialization.data(withJSONObject: raw))
                // This frame is sent only for operations tracked in this voice conversation.
                presentedRequests.removeValue(forKey: request.id)
                if !request.isActive || request.isQuestion || request.phase == "scheduled" {
                    pendingPresentedRequests.insert(request.id)
                }
                if pendingPresentedRequests.count > 100 { pendingPresentedRequests = [request.id] }
                onRequest?(request)
            }
        case "error":
            let detail = event["error"] as? [String: Any]
            error = detail?["message"] as? String ?? "Voice service reported an error."
        default: break
        }
    }
    func isPresenting(requestID: String?, notificationID: String?, now: Date = Date()) -> Bool {
        guard isConnected, let requestID, let presented = presentedRequests[requestID] else { return false }
        return now.timeIntervalSince(presented) < 120
    }
    private func append(id: String, role: String, text: String, delta: Bool = false) {
        if let index = transcript.firstIndex(where: { $0.id == id }) {
            transcript[index].text = delta ? transcript[index].text + text : text
        } else { transcript.append(.init(id: id, role: role, text: text)) }
        if transcript.count > 100 { transcript.removeFirst(transcript.count - 100) }
    }
    private func send(_ event: [String: Any]) async throws {
        if let eventSender { try await eventSender(event); return }
        guard let socket else { throw APIError(message: "Voice is disconnected") }
        let data = try JSONSerialization.data(withJSONObject: event)
        try await socket.send(.string(String(decoding: data, as: UTF8.self)))
    }
    private func fail(_ message: String) { disconnect(); error = message }
    func clearConversation() {
        disconnect()
        transcript.removeAll()
        error = nil
        telemetry.reset()
    }
    func disconnect() {
        sessionGeneration = UUID()
        connectionTimeout?.cancel(); connectionTimeout = nil
        responseActive = false
        pendingPresentedRequests.removeAll(); presentedRequests.removeAll()
        speechClock.reset()
        activeResponseID = nil
        interruptedResponses.removeAll()
        receiver?.cancel(); receiver = nil
        continuation?.finish(); continuation = nil
        sender?.cancel(); sender = nil
        socket?.cancel(with: .normalClosure, reason: nil); socket = nil
        audio.stop()
        state = .disconnected
    }
}
