import XCTest
@testable import Atlas

private func request(_ id: String = "op", phase: String = "scheduled", revision: Int = 1) throws -> TrackedRequest {
    try mobileDecoder().decode(TrackedRequest.self, from: Data("""
    {"id":"\(id)","kind":"operation","status":"\(phase == "completed" ? "completed" : phase == "partial" ? "failed" : "queued")","phase":"\(phase)","revision":\(revision),"title":"Apples","text":"Add apples","summary":"Planned","created_at":"2026-10-16T10:00:00Z","updated_at":"2026-10-16T10:00:00Z"}
    """.utf8))
}
private func frame(sequence: Int, type: String = "operation.updated", payload: String) -> EventFrame {
    EventFrame(id: String(sequence), type: type, data: """
    {"id":"\(String(format: "%020d", sequence))","sequence":\(sequence),"type":"\(type)","payload":\(payload)}
    """)
}
private func event(_ frame: EventFrame) throws -> MobileEvent {
    try mobileDecoder().decode(MobileEvent.self, from: Data(frame.data.utf8))
}
private let operationJSON = #"{"id":"op","kind":"operation","status":"queued","phase":"scheduled","revision":2,"title":"Apples","text":"Add apples","summary":"Planned","created_at":"2026-10-16T10:00:00Z","updated_at":"2026-10-16T10:00:01Z"}"#

final class ResponsivenessTests: XCTestCase {
    func testParserHandlesChunkedUnicodeMultilineCRLFCommentsAndReset() throws {
        let text = ": heartbeat\r\n\r\nid: 123\r\nevent: operation.updated\r\ndata: {\"text\":\"🍎\",\r\ndata: \"value\":1}\r\n\r\nevent: reset\ndata: {\"reason\":\"slow_consumer\"}\n\n"
        var parser = EventParser()
        let frames = try text.utf8.compactMap { try parser.feed($0) }
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames[0].id, "123")
        XCTAssertEqual(frames[0].type, "operation.updated")
        XCTAssertEqual(frames[0].data, "{\"text\":\"🍎\",\n\"value\":1}")
        XCTAssertEqual(frames[1].type, "reset")
        XCTAssertNil(frames[1].id)
    }
    func testUnterminatedOversizedFrameIsBounded() throws {
        var parser = EventParser()
        for _ in 0..<EventParser.limit { _ = try parser.feed(97) }
        XCTAssertThrowsError(try parser.feed(97))
    }
    func testReplayIsIdempotentAndOldRevisionsCannotRewindOperations() throws {
        var projection = MobileProjection(state: MobileState(requests: [], notifications: [], cursor: 4))
        let update = try event(frame(sequence: 5, payload: operationJSON))
        XCTAssertFalse(try projection.apply(update))
        XCTAssertFalse(try projection.apply(update))
        XCTAssertEqual(projection.state.requests.count, 1)
        projection.merge(try request(phase: "completed", revision: 3))
        projection.merge(try request(revision: 1))
        XCTAssertEqual(projection.state.requests[0].phase, "completed")
        XCTAssertEqual(projection.state.cursor, 5)
    }
    func testScheduledPartialAndLegacyStatesRemainAccurate() throws {
        let scheduled = try request()
        XCTAssertTrue(scheduled.isActive)
        XCTAssertTrue(scheduled.canCancel)
        XCTAssertEqual(scheduled.statusLabel, "Scheduled — awaiting execution")
        XCTAssertEqual(scheduled.activityState.status, "queued")
        let partial = try request(phase: "partial")
        XCTAssertFalse(partial.isActive)
        XCTAssertEqual(partial.statusLabel, "Partly completed — needs attention")
        let old = try mobileDecoder().decode(MobileState.self, from: Data(#"{"requests":[],"notifications":[]}"#.utf8))
        XCTAssertNil(old.cursor)
        XCTAssertNil(old.sources)
    }
    func testMissingReadNeverLooksLikeAnEmptySuccessfulResultAndAgeUsesVerificationTime() throws {
        let missing = try mobileDecoder().decode(ReadSnapshot.self, from: Data(#"{"read_id":"r","source":"shopping","data":null,"revision":null,"verified_at":null,"age_seconds":null,"freshness":"missing","refreshing":true,"error":"offline"}"#.utf8))
        XCTAssertFalse(missing.hasData)
        let stale = try mobileDecoder().decode(ReadSnapshot.self, from: Data(#"{"read_id":"r","source":"shopping","data":{"accounts":[]},"revision":"1","verified_at":"2026-10-16T10:00:00Z","age_seconds":0,"freshness":"fresh","refreshing":false}"#.utf8))
        XCTAssertTrue(stale.hasData)
        XCTAssertTrue(stale.needsAgeDisclosure(at: parseISODate("2026-10-16T10:06:00Z")!, connected: true))
        XCTAssertTrue(stale.needsAgeDisclosure(at: parseISODate("2026-10-16T10:00:01Z")!, connected: false))
        XCTAssertFalse(stale.needsAgeDisclosure(at: parseISODate("2026-10-16T10:00:01Z")!, connected: true))
    }
    func testCacheRoundTripIsAccountScopedAndClearsContentsAndCursor() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = StateCache(directory: directory)
        let a = StateCache.scope(credentials: Credentials(token: "a", accessSecret: "one"))
        let b = StateCache.scope(credentials: Credentials(token: "a", accessSecret: "two"))
        XCTAssertNotEqual(a, b)
        let projection = MobileProjection(state: MobileState(requests: [try request()], notifications: [], cursor: 27))
        try await cache.save(projection, scope: a)
        let restored = await cache.load(scope: a)
        let otherAccount = await cache.load(scope: b)
        XCTAssertEqual(restored?.state.cursor, 27)
        XCTAssertEqual(restored?.state.requests.first?.phase, "scheduled")
        XCTAssertNil(otherAccount)
        try await cache.clear()
        let cleared = await cache.load(scope: a)
        XCTAssertNil(cleared)
    }
    @MainActor
    func testNoPollingWhileStreamHealthyAndStopCancelsStream() async throws {
        let api = FakeTransport()
        let cache = StateCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let live = expectation(description: "live")
        let cancelled = expectation(description: "stream cancelled")
        api.onCancel = { cancelled.fulfill() }
        let sync = MobileSync(transport: api, cache: cache, scope: "test")
        sync.onChange = { _, connection in if connection == .live { live.fulfill() } }
        sync.start()
        await fulfillment(of: [live], timeout: 3)
        XCTAssertEqual(api.stateCalls, 1)
        XCTAssertEqual(api.cursors, [10])
        sync.stop()
        await fulfillment(of: [cancelled], timeout: 3)
        XCTAssertEqual(sync.connection, .stopped)
        try await cache.clear()
    }
    @MainActor
    func testRestartUsesPersistedCursorWithoutFirstReplacingItWithASnapshot() async throws {
        let api = FakeTransport()
        let cache = StateCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let saved = MobileProjection(state: MobileState(requests: [try request()], notifications: [], cursor: 27))
        try await cache.save(saved, scope: "test")
        let restored = await cache.load(scope: "test")
        let sync = MobileSync(transport: api, cache: cache, scope: "test", projection: try XCTUnwrap(restored))
        let live = expectation(description: "checkpoint replay")
        sync.onChange = { _, connection in if connection == .live { live.fulfill() } }
        sync.start()
        await fulfillment(of: [live], timeout: 3)
        XCTAssertEqual(api.stateCalls, 0)
        XCTAssertEqual(api.cursors, [27])
        XCTAssertEqual(sync.projection.state.requests.first?.id, "op")
        sync.stop()
        try await cache.clear()
    }
    @MainActor
    func testExpiredCursorFetchesSnapshotAndResubscribes() async throws {
        let api = FakeTransport()
        api.resetOnce = true
        let cache = StateCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let live = expectation(description: "recovered")
        let sync = MobileSync(transport: api, cache: cache, scope: "test")
        sync.onChange = { _, connection in if connection == .live { live.fulfill() } }
        sync.start()
        await fulfillment(of: [live], timeout: 3)
        XCTAssertEqual(api.cursors, [10, 20])
        XCTAssertEqual(sync.projection.state.cursor, 20)
        sync.stop()
        try await cache.clear()
    }
    @MainActor
    func testLegacyServerPollsOnlyAtFallbackInterval() async throws {
        let api = FakeTransport()
        api.legacy = true
        let asleep = expectation(description: "waiting for polling interval")
        let cache = StateCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let sync = MobileSync(transport: api, cache: cache, scope: "test", sleep: { interval in
            XCTAssertEqual(interval, 5)
            asleep.fulfill()
            try await Task.sleep(for: .seconds(60))
        })
        sync.start()
        await fulfillment(of: [asleep], timeout: 3)
        XCTAssertEqual(sync.connection, .polling)
        XCTAssertTrue(api.cursors.isEmpty)
        sync.stop()
        try await cache.clear()
    }
    @MainActor
    func testNotificationGapDoesNotAdvanceDurableCursorUntilSnapshot() async throws {
        let api = FakeTransport()
        let cache = StateCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let sync = MobileSync(transport: api, cache: cache, scope: "test")
        await sync.refresh()
        try await sync.accept(frame(sequence: 11, type: "notification.created", payload: #"{"notification_id":"n"}"#))
        XCTAssertEqual(sync.projection.state.cursor, 11)
        let saved = await cache.load(scope: "test")
        XCTAssertEqual(saved?.state.cursor, 10)
        sync.stop()
        try await cache.clear()
    }
    @MainActor
    func testResetAndMismatchedEventIDsCannotAdvanceCursor() async throws {
        let cache = StateCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let sync = MobileSync(transport: FakeTransport(), cache: cache, scope: "test")
        await sync.refresh()
        do { try await sync.accept(EventFrame(id: nil, type: "reset", data: "{}")); XCTFail("Expected reset") }
        catch StreamError.reset {} catch { XCTFail("Unexpected error: \(error)") }
        let good = frame(sequence: 11, payload: operationJSON)
        do { try await sync.accept(EventFrame(id: "12", type: good.type, data: good.data)); XCTFail("Expected invalid frame") }
        catch StreamError.invalidFrame {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(sync.projection.state.cursor, 10)
        sync.stop()
        try await cache.clear()
    }
    @MainActor
    func testForegroundSuppressionIsSelectiveAndDeduplicated() {
        let policy = ForegroundNotificationPolicy()
        policy.shouldSuppress = { $0["request_id"] as? String == "spoken" }
        XCTAssertFalse(policy.suppress(["request_id": "other", "notification_id": "1"]))
        XCTAssertTrue(policy.suppress(["request_id": "spoken", "notification_id": "2"]))
        XCTAssertTrue(policy.suppress(["request_id": "other", "notification_id": "1"]))
        policy.reset()
        XCTAssertFalse(policy.suppress(["request_id": "other", "notification_id": "1"]))
    }
    @MainActor
    func testVoiceTimingsRecordFirstRenderOncePerTurnWithoutContent() {
        let telemetry = VoiceTelemetry()
        telemetry.speechStopped(at: 100, localEnd: 99.5)
        telemetry.playback(.init(item: "audio", renderedAt: 100.2, estimatedAudibleAt: 100.3))
        telemetry.playback(.init(item: "audio", renderedAt: 100.4, estimatedAudibleAt: 100.5))
        XCTAssertEqual(telemetry.samples.count, 3)
        XCTAssertEqual(telemetry.samples[2].milliseconds, 800, accuracy: 0.001)
        for i in 0..<100 {
            telemetry.speechStopped(at: Double(i))
            telemetry.playback(.init(item: "audio", renderedAt: Double(i) + 0.1, estimatedAudibleAt: Double(i) + 0.2))
        }
        XCTAssertEqual(telemetry.samples.count, 200)
    }
}

extension ResponsivenessTests {
    @MainActor
    func testReconnectBackoffIsBoundedAndPollingStopsWhenStreamRecovers() async throws {
        let api = FakeTransport()
        api.streamFailures = 4
        var waits: [Double] = []
        let live = expectation(description: "reconnected")
        let cache = StateCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let sync = MobileSync(transport: api, cache: cache, scope: "test", sleep: { waits.append($0); await Task.yield() })
        sync.onChange = { _, connection in if connection == .live { live.fulfill() } }
        sync.start()
        await fulfillment(of: [live], timeout: 3)
        XCTAssertEqual(waits.reduce(0, +), 65) // 5, 10, 20, 30 seconds, with five-second fallback polls.
        XCTAssertTrue(waits.allSatisfy { $0 == 5 })
        XCTAssertEqual(api.cursors.count, 5)
        let calls = api.stateCalls
        await Task.yield()
        XCTAssertEqual(api.stateCalls, calls)
        sync.stop()
        try await cache.clear()
    }
    @MainActor
    func testAcceptanceDuringSnapshotSurvivesItsOlderResponse() async throws {
        let api = FakeTransport()
        let entered = expectation(description: "snapshot started")
        var response: CheckedContinuation<MobileState, Error>?
        api.stateOverride = {
            try await withCheckedThrowingContinuation { continuation in
                response = continuation
                entered.fulfill()
            }
        }
        let cache = StateCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let sync = MobileSync(transport: api, cache: cache, scope: "test")
        let refresh = Task { await sync.refresh() }
        await fulfillment(of: [entered], timeout: 3)
        await sync.merge(try request("accepted-during-http"))
        response?.resume(returning: MobileState(requests: [], notifications: [], cursor: 0))
        await refresh.value
        XCTAssertEqual(sync.projection.state.requests.first?.id, "accepted-during-http")
        sync.retire()
        try await cache.clear()
    }
    @MainActor
    func testSnapshotCannotOverwriteNewerEvent() async throws {
        let api = FakeTransport()
        let cache = StateCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let sync = MobileSync(transport: api, cache: cache, scope: "test")
        await sync.refresh()
        try await sync.accept(frame(sequence: 100, payload: operationJSON))
        await sync.refresh() // Snapshot cursor 20 predates the already-applied event 100.
        XCTAssertEqual(sync.projection.state.cursor, 100)
        XCTAssertEqual(sync.projection.state.requests.first?.id, "op")
        sync.retire()
        await sync.merge(try request("other"))
        XCTAssertEqual(sync.projection.state.requests.count, 1)
        try await cache.clear()
    }
    @MainActor
    func testVoiceOnlySuppressesOperationAfterItsPlaybackAndKeepsTrackingAfterDisconnect() async throws {
        let audio = PresentationAudio()
        let voice = VoiceSession(audio: audio, sendEvent: { _ in })
        var received: [TrackedRequest] = []
        voice.onRequest = { received.append($0) }
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(operationJSON.utf8)) as? [String: Any])
        try await voice.handle(["type": "noodle.request", "request": json], question: nil)
        XCTAssertFalse(voice.isPresenting(requestID: "op", notificationID: nil))
        try await voice.handle(["type": "response.output_audio.delta", "item_id": "spoken", "delta": "AAAA"], question: nil)
        audio.onPlaybackStarted?(.init(item: "spoken", renderedAt: 1, estimatedAudibleAt: 1))
        XCTAssertTrue(voice.isPresenting(requestID: "op", notificationID: nil))
        XCTAssertFalse(voice.isPresenting(requestID: "unrelated", notificationID: nil))
        voice.disconnect()
        XCTAssertFalse(voice.isPresenting(requestID: "op", notificationID: nil))
        XCTAssertEqual(received.first?.id, "op")
        try await voice.handle(["type": "conversation.item.input_audio_transcription.completed", "item_id": "text", "transcript": "Private conversation"], question: nil)
        XCTAssertFalse(voice.transcript.isEmpty)
        voice.clearConversation()
        XCTAssertTrue(voice.transcript.isEmpty)
    }
    @MainActor
    func testCancellingForegroundTransportClosesAnIdleAsyncByteStream() async throws {
        let api = AtlasAPI(credentials: Credentials(token: "test"))
        api.eventConfiguration = {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [EventProtocol.self]
            return config
        }
        EventProtocol.status = 200
        EventProtocol.holdOpen = true
        defer { EventProtocol.holdOpen = false }
        let live = expectation(description: "stream opened")
        let stopped = expectation(description: "idle stream cancelled")
        let worker = Task {
            do { try await api.events(after: 1, connected: { live.fulfill() }, receive: { _ in }) }
            catch { stopped.fulfill() }
        }
        await fulfillment(of: [live], timeout: 3)
        worker.cancel()
        await fulfillment(of: [stopped], timeout: 3)
        await worker.value
    }
    @MainActor
    func testAuthenticatedEventTransportUsesCursorAndParsesRealAsyncBytes() async throws {
        let api = AtlasAPI(credentials: Credentials(token: "test", accessID: "cf-id", accessSecret: "cf-secret"))
        api.eventConfiguration = {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [EventProtocol.self]
            return config
        }
        EventProtocol.status = 200
        EventProtocol.inspect = { request in
            XCTAssertEqual(request.url?.path, "/api/mobile/events")
            XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "41")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test")
            XCTAssertEqual(request.value(forHTTPHeaderField: "CF-Access-Client-Id"), "cf-id")
            XCTAssertEqual(request.value(forHTTPHeaderField: "CF-Access-Client-Secret"), "cf-secret")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
        }
        defer { EventProtocol.inspect = nil }
        var connected = false
        var received: [EventFrame] = []
        do { try await api.events(after: 41, connected: { connected = true }, receive: { received.append($0) }) }
        catch StreamError.ended {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(connected)
        XCTAssertEqual(received.first?.id, "42")
        EventProtocol.status = 409
        do { try await api.events(after: 41, connected: { XCTFail("Should reset") }, receive: { _ in }); XCTFail("Expected reset") }
        catch StreamError.reset {} catch { XCTFail("Unexpected error: \(error)") }
    }
}

@MainActor
private final class PresentationAudio: VoiceAudioPlaying {
    var onPlaybackFinished: (() -> Void)?
    var onPlaybackStarted: ((PlaybackTiming) -> Void)?
    var hasPendingAudio = false
    func start(onAudio: @escaping (Data) -> Void) throws {}
    func enqueue(_ data: Data, item: String) { hasPendingAudio = true }
    func interrupt() -> (String, Int)? { nil }
    func stop() { hasPendingAudio = false }
}

private final class EventProtocol: URLProtocol {
    static var inspect: ((URLRequest) -> Void)?
    static var status = 200
    static var holdOpen = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.inspect?(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.status,
            httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!, cacheStoragePolicy: .notAllowed)
        let text = ": heartbeat\n\nid: 42\nevent: source.invalidated\ndata: {}\n\n"
        // Split the response across arbitrary byte boundaries, as a real network does.
        for byte in text.utf8 { client?.urlProtocol(self, didLoad: Data([byte])) }
        if !Self.holdOpen { client?.urlProtocolDidFinishLoading(self) }
    }
    override func stopLoading() {}
}

@MainActor
private final class FakeTransport: MobileTransport {
    var stateCalls = 0
    var cursors: [Int] = []
    var resetOnce = false
    var streamFailures = 0
    var legacy = false
    var onCancel: (() -> Void)?
    var stateOverride: (() async throws -> MobileState)?
    func state() async throws -> MobileState {
        stateCalls += 1
        if let stateOverride { return try await stateOverride() }
        return MobileState(requests: [], notifications: [], cursor: legacy ? nil : stateCalls * 10)
    }
    func events(after cursor: Int, connected: @escaping () -> Void,
                receive: @escaping (EventFrame) async throws -> Void) async throws {
        cursors.append(cursor)
        if resetOnce { resetOnce = false; throw StreamError.reset }
        if streamFailures > 0 { streamFailures -= 1; throw StreamError.unavailable(503) }
        connected()
        do { try await Task.sleep(for: .seconds(60)) }
        catch { onCancel?(); throw error }
    }
}
