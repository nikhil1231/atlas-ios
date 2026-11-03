import Foundation

@MainActor
final class AtlasAPI: MobileTransport {
    var credentials: Credentials
    private let guardDelegate = RedirectGuard()
    var eventConfiguration: (() -> URLSessionConfiguration)?
    lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.httpShouldSetCookies = false
        config.urlCache = nil
        return URLSession(configuration: config, delegate: guardDelegate, delegateQueue: nil)
    }()
    init(credentials: Credentials) { self.credentials = credentials }

    func request(_ path: String, method: String = "GET", body: [String: Any]? = nil) throws -> URLRequest {
        try AtlasRequest.make("api/mobile/" + path, method: method, body: body, credentials: credentials,
                              base: AppConfiguration.backendURL)
    }
    func data(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> Data {
        let (data, response) = try await session.data(for: request(path, method: method, body: body))
        return try AtlasRequest.check(data, response)
    }
    func state() async throws -> MobileState {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(MobileState.self, from: await data("state"))
    }
    func submit(text: String, id: UUID, questionID: String? = nil) async throws -> TrackedRequest {
        var body: [String: Any] = ["request_id": id.uuidString, "text": text, "tz": TimeZone.current.identifier]
        if let questionID { body["question_id"] = questionID }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(TrackedRequest.self, from: await data("requests", method: "POST", body: body))
    }
    func operation(handler: String, input: [String: Any], id: UUID, delaySeconds: Double = 0) async throws -> TrackedRequest {
        try mobileDecoder().decode(TrackedRequest.self, from: await data("operations", method: "POST",
            body: ["request_id": id.uuidString, "handler": handler, "input": input,
                   "tz": TimeZone.current.identifier, "delay_seconds": delaySeconds]))
    }
    func read(source: String, query: [String: Any] = [:], refresh: Bool = false) async throws -> ReadSnapshot {
        try mobileDecoder().decode(ReadSnapshot.self, from: await data("reads", method: "POST",
            body: ["source": source, "query": query, "refresh": refresh]))
    }
    func events(after cursor: Int, connected: @escaping () -> Void,
                receive: @escaping (EventFrame) async throws -> Void) async throws {
        var request = try request("events")
        var url = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        url.queryItems = [.init(name: "after", value: String(cursor))]
        request.url = url.url
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        // A dedicated session avoids a total-resource timeout on a healthy, long-lived stream.
        let config = eventConfiguration?() ?? URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 45 // Heartbeats arrive every 15 seconds.
        config.timeoutIntervalForResource = 24 * 60 * 60
        config.httpShouldSetCookies = false
        config.urlCache = nil
        let stream = URLSession(configuration: config, delegate: guardDelegate, delegateQueue: nil)
        defer { stream.invalidateAndCancel() }
        let (bytes, response) = try await stream.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw StreamError.invalidFrame }
        if http.statusCode == 409 { throw StreamError.reset }
        guard http.statusCode == 200,
              http.value(forHTTPHeaderField: "Content-Type")?.lowercased().hasPrefix("text/event-stream") == true else {
            throw StreamError.unavailable(http.statusCode)
        }
        connected()
        try await withTaskCancellationHandler {
            var parser = EventParser()
            for try await byte in bytes {
                try Task.checkCancellation()
                if let frame = try parser.feed(byte) { try await receive(frame) }
            }
            throw StreamError.ended
        } onCancel: {
            bytes.task.cancel()
        }
    }
    /// The same exchange the Atlas Sync Shortcut makes (see Atlas's phone.py), driven by EventKit.
    func syncReminders(_ lines: [String]) async throws -> ReminderSyncResponse {
        let request = try AtlasRequest.make("api/reminders/sync", method: "POST",
            body: ["reminders": lines.joined(separator: "\n"), "tz": TimeZone.current.identifier],
            credentials: credentials, base: AppConfiguration.backendURL)
        let (data, response) = try await session.data(for: request)
        return try JSONDecoder().decode(ReminderSyncResponse.self, from: AtlasRequest.check(data, response))
    }
    func registerPush(_ token: String) async throws {
        _ = try await data("devices/\(AppConfiguration.installationID)", method: "PUT",
                           body: ["token": token, "environment": AppConfiguration.pushEnvironment])
    }
}
