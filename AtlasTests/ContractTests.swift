import XCTest
@testable import Atlas

final class ContractTests: XCTestCase {
    func testStateDecodesBackendKeysAndOpenQuestions() throws {
        let json = #"{"requests":[{"id":"q1","kind":"question","status":"awaiting_answer","title":"Which morning?","text":"Move my appointment","summary":"Which morning?","execute_at":null,"created_at":"2026-10-15T09:00:00+00:00","updated_at":"2026-10-15T09:00:00+00:00"}],"notifications":[{"id":"n1","kind":"question","title":"Answer needed","body":"Which morning?","request_id":"q1","created_at":"2026-10-15T09:00:00+00:00","read":false}]}"#
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let state = try decoder.decode(MobileState.self, from: Data(json.utf8))
        XCTAssertTrue(state.requests[0].isQuestion)
        XCTAssertTrue(state.requests[0].canCancel)
        XCTAssertEqual(state.notifications[0].requestID, "q1")
        XCTAssertNotNil(parseISODate(state.requests[0].createdAt))
    }
    func testActivityContentMatchesAPNsPayload() throws {
        let data = Data(#"{"title":"Move delivery","status":"running","summary":"Working"}"#.utf8)
        let state = try JSONDecoder().decode(AtlasActivityAttributes.ContentState.self, from: data)
        let encoded = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: encoded) as? [String: String],
                       ["title": "Move delivery", "status": "running", "summary": "Working"])
    }
    func testRunningRequestsCannotBeCancelled() throws {
        let data = Data(#"{"id":"r1","kind":"operation","status":"running","title":"Do it","text":"Do it","summary":"Working","created_at":"now","updated_at":"now"}"#.utf8)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let request = try decoder.decode(TrackedRequest.self, from: data)
        XCTAssertTrue(request.isActive)
        XCTAssertFalse(request.canCancel)
    }
}

@MainActor
private final class TestVoiceAudio: VoiceAudioPlaying {
    var onPlaybackFinished: (() -> Void)?
    var onPlaybackStarted: ((PlaybackTiming) -> Void)?
    var hasPendingAudio = false
    var interrupted = false
    func start(onAudio: @escaping (Data) -> Void) throws {}
    func enqueue(_ data: Data, item: String) { hasPendingAudio = true }
    func interrupt() -> (String, Int)? {
        interrupted = true
        hasPendingAudio = false
        return ("spoken-item", 120)
    }
    func stop() { hasPendingAudio = false }
    func finish() {
        hasPendingAudio = false
        onPlaybackFinished?()
    }
}

extension ContractTests {
    @MainActor
    func testListeningWaitsForActualPlaybackAndReportsPlaybackToServer() async throws {
        let audio = TestVoiceAudio()
        var events: [[String: Any]] = []
        let voice = VoiceSession(audio: audio) { events.append($0) }
        try await voice.handle(["type": "response.created", "response": ["id": "r1"]], question: nil)
        try await voice.handle(["type": "response.output_audio.delta", "response_id": "r1",
                                "item_id": "spoken-item", "delta": "AAAA"], question: nil)
        try await voice.handle(["type": "response.done", "response": ["status": "completed"]], question: nil)
        XCTAssertEqual(voice.state, .speaking)
        XCTAssertTrue(events.contains { $0["type"] as? String == "noodle.playback" && $0["playing"] as? Bool == true })
        audio.finish()
        XCTAssertEqual(voice.state, .listening)
        await Task.yield()
        XCTAssertTrue(events.contains { $0["type"] as? String == "noodle.playback" && $0["playing"] as? Bool == false })
    }

    @MainActor
    func testBargeInTruncatesPlaybackAndIgnoresLateAudio() async throws {
        let audio = TestVoiceAudio()
        var events: [[String: Any]] = []
        let voice = VoiceSession(audio: audio) { events.append($0) }
        try await voice.handle(["type": "response.created", "response": ["id": "r1"]], question: nil)
        let delta: [String: Any] = ["type": "response.output_audio.delta", "response_id": "r1",
                                    "item_id": "spoken-item", "delta": "AAAA"]
        try await voice.handle(delta, question: nil)
        try await voice.handle(["type": "input_audio_buffer.speech_started"], question: nil)
        try await voice.handle(delta, question: nil)
        XCTAssertTrue(audio.interrupted)
        XCTAssertFalse(audio.hasPendingAudio)
        XCTAssertEqual(voice.state, .listening)
        let truncate = try XCTUnwrap(events.first { $0["type"] as? String == "conversation.item.truncate" })
        XCTAssertEqual(truncate["audio_end_ms"] as? Int, 120)
    }

    @MainActor
    func testTextSubmissionUsesExistingBackendContract() async throws {
        let api = AtlasAPI(credentials: Credentials(token: "test"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SubmissionProtocol.self]
        api.session = URLSession(configuration: configuration)
        let id = UUID()
        SubmissionProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/mobile/requests")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test")
            let stream = try XCTUnwrap(request.httpBodyStream)
            stream.open()
            defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 4096)
            let count = stream.read(&bytes, maxLength: bytes.count)
            XCTAssertGreaterThan(count, 0)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(bytes.prefix(max(0, count)))) as? [String: String])
            XCTAssertEqual(body["request_id"], id.uuidString)
            XCTAssertEqual(body["text"], "Remember milk")
            XCTAssertEqual(body["question_id"], "q1")
            return Data(#"{"id":"r1","kind":"operation","status":"queued","title":"Remember milk","text":"Remember milk","summary":"Waiting to run","created_at":"now","updated_at":"now"}"#.utf8)
        }
        defer { SubmissionProtocol.handler = nil; api.session.invalidateAndCancel() }
        let result = try await api.submit(text: "Remember milk", id: id, questionID: "q1")
        XCTAssertEqual(result.id, "r1")
        XCTAssertEqual(result.status, "queued")
    }
}

private final class SubmissionProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> Data)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let data = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 202,
                                httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
