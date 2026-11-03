import Foundation
import Security

// Compiled into the app, the widgets and the share extension: configuration, credentials, the data
// Atlas returns, and a small client the extensions use to reach it without the app running.

enum AtlasEnvironment {
    private static func value(_ key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !raw.isEmpty, !raw.contains("$(") else { return nil }
        return raw
    }
    static var backendURL: URL {
        let value = value("AtlasBackendURL") ?? "https://atlas.nikhil.ing"
        guard let url = URL(string: value), url.scheme == "https", let host = url.host,
              !host.isEmpty, host != "localhost", !host.hasSuffix(".local"),
              !host.contains(":"), host.range(of: #"^[0-9.]+$"#, options: .regularExpression) == nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            preconditionFailure("AtlasBackendURL must be a hosted HTTPS URL")
        }
        return url
    }
    /// The App Group the widgets read their snapshot from. Nil in unsigned builds.
    static var appGroup: String? { value("AtlasAppGroup") }
    /// The keychain group shared with the extensions (team prefix included at build time).
    static var keychainGroup: String? {
        guard let group = value("AtlasKeychainGroup"), group.contains(".") else { return nil }
        return group
    }
    static var sharedDefaults: UserDefaults {
        appGroup.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }
    static var sharedContainer: URL {
        if let group = appGroup, let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) {
            return url
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }
}

struct Credentials: Codable, Equatable {
    var token = ""
    var accessID = ""
    var accessSecret = ""
    var isConfigured: Bool { !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// Credentials live in a keychain group the extensions share. Older installs saved them in the app's
/// own group: they're found there and moved across on first load.
struct KeychainStore {
    private let service = "ing.nikhil.noodle.credentials"
    private let account = "hosted"
    var group: String? = AtlasEnvironment.keychainGroup

    private func query(group: String?) -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service, kSecAttrAccount as String: account]
        if let group { query[kSecAttrAccessGroup as String] = group }
        return query
    }
    private func read(group: String?) throws -> Credentials? {
        var query = query(group: group)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound || status == errSecMissingEntitlement { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError(status: status) }
        return try JSONDecoder().decode(Credentials.self, from: data)
    }
    func load() throws -> Credentials {
        if let group, let shared = try read(group: group) { return shared }
        guard let legacy = try read(group: nil) else { return Credentials() }
        if group != nil { try? save(legacy) }  // move it where the widgets and share sheet can see it
        return legacy
    }
    func save(_ credentials: Credentials) throws {
        SecItemDelete(query(group: nil) as CFDictionary)
        let values: [String: Any] = [kSecValueData as String: try JSONEncoder().encode(credentials),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemAdd(query(group: group).merging(values) { _, new in new } as CFDictionary, nil)
        if status == errSecMissingEntitlement {  // an unsigned build has no shared group
            status = SecItemAdd(query(group: nil).merging(values) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }
}

struct KeychainError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? { "Could not access credentials in Keychain (\(status))." }
}

struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// Reject redirects so bearer and Cloudflare credentials cannot follow a login or foreign URL.
final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

enum AtlasRequest {
    static func make(_ path: String, method: String = "GET", body: [String: Any]? = nil,
                     credentials: Credentials, base: URL = AtlasEnvironment.backendURL) throws -> URLRequest {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")
        if !credentials.accessID.isEmpty {
            request.setValue(credentials.accessID, forHTTPHeaderField: "CF-Access-Client-Id")
            request.setValue(credentials.accessSecret, forHTTPHeaderField: "CF-Access-Client-Secret")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }
    static func check(_ data: Data, _ response: URLResponse) throws -> Data {
        guard let response = response as? HTTPURLResponse else { throw APIError(message: "Invalid server response") }
        guard (200..<300).contains(response.statusCode) else {
            if [301, 302, 303, 307, 308, 401, 403].contains(response.statusCode) {
                throw APIError(message: "Sign-in failed. Check your Atlas and Cloudflare Access tokens in Settings.")
            }
            let detail = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw APIError(message: detail?["detail"] as? String ?? "Atlas returned HTTP \(response.statusCode).")
        }
        return data
    }
}

/// For the widgets, the share sheet and Siri: one request at a time, no streaming.
struct AtlasClient: Sendable {
    let credentials: Credentials
    static func load() throws -> AtlasClient {
        let credentials = try KeychainStore().load()
        guard credentials.isConfigured else { throw APIError(message: "Open Atlas and connect it in Settings first.") }
        return AtlasClient(credentials: credentials)
    }
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25
        config.httpShouldSetCookies = false
        config.urlCache = nil
        return URLSession(configuration: config, delegate: RedirectGuard(), delegateQueue: nil)
    }()
    func data(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> Data {
        let request = try AtlasRequest.make("api/mobile/" + path, method: method, body: body, credentials: credentials)
        let (data, response) = try await Self.session.data(for: request)
        return try AtlasRequest.check(data, response)
    }
    func submit(_ text: String, id: UUID = UUID()) async throws -> TrackedRequest {
        try mobileDecoder().decode(TrackedRequest.self, from: await data("requests", method: "POST", body: [
            "request_id": id.uuidString, "text": text, "tz": TimeZone.current.identifier]))
    }
    func operation(_ handler: String, input: [String: Any], id: UUID = UUID()) async throws -> TrackedRequest {
        try mobileDecoder().decode(TrackedRequest.self, from: await data("operations", method: "POST", body: [
            "request_id": id.uuidString, "handler": handler, "input": input, "tz": TimeZone.current.identifier]))
    }
    func read(_ source: String, query: [String: Any] = [:]) async throws -> ReadSnapshot {
        var query = query
        query["tz"] = query["tz"] ?? TimeZone.current.identifier
        return try mobileDecoder().decode(ReadSnapshot.self, from: await data("reads", method: "POST",
            body: ["source": source, "query": query, "refresh": false]))
    }
    func request(_ id: String) async throws -> TrackedRequest? {
        let state = try mobileDecoder().decode(MobileState.self, from: await data("state"))
        return state.requests.first { $0.id == id }
    }
    /// Submit, then wait (briefly) for Atlas's actual result rather than reporting acceptance as success.
    func submitAndWait(_ text: String, timeout: TimeInterval = 25) async throws -> TrackedRequest {
        var request = try await submit(text)
        let deadline = Date().addingTimeInterval(timeout)
        while request.isActive, !request.isQuestion, Date() < deadline {
            try await Task.sleep(for: .seconds(1.5))
            request = try await self.request(request.id) ?? request
        }
        return request
    }
}

// ---- requests and notifications --------------------------------------------------------------
struct TrackedRequest: Codable, Identifiable, Hashable {
    let id: String
    let kind: String
    let status: String
    let title: String
    let text: String
    let summary: String
    let executeAt: String?
    let createdAt: String
    let updatedAt: String

    let phase: String?
    let revision: Int?
    let outcome: String?
    let handler: String?

    init(id: String, kind: String, status: String, title: String, text: String, summary: String,
         executeAt: String?, createdAt: String, updatedAt: String, phase: String? = nil,
         revision: Int? = nil, outcome: String? = nil, handler: String? = nil) {
        self.id = id; self.kind = kind; self.status = status; self.title = title; self.text = text
        self.summary = summary; self.executeAt = executeAt; self.createdAt = createdAt; self.updatedAt = updatedAt
        self.phase = phase; self.revision = revision; self.outcome = outcome; self.handler = handler
    }

    var isActive: Bool { ["queued", "running", "awaiting_answer"].contains(status) }
    var canCancel: Bool { ["queued", "awaiting_answer"].contains(status) }
    var isQuestion: Bool { kind == "question" && status == "awaiting_answer" }
    /// A direct edit from the app (tick, snooze, note). Shown in Activity only while running or if it failed.
    var isAction: Bool { kind == "action" }
    var statusLabel: String {
        switch phase ?? status {
        case "accepted": "Accepted"
        case "resolving": "Planning"
        case "scheduled": "Scheduled — awaiting execution"
        case "executing": "Working on it"
        case "partial": "Partly completed — needs attention"
        case "awaiting_answer": "Needs your answer"
        case "queued": "Waiting to run"
        case "running": "Working on it"
        case "completed": "Completed"
        case "answered": "Answered"
        case "failed": "Needs attention"
        case "interrupted": "Interrupted — check Atlas"
        case "cancelled": "Cancelled"
        default: status.capitalized
        }
    }
}

struct AtlasNotification: Codable, Identifiable {
    let id: String
    let kind: String
    let title: String
    let body: String
    let requestID: String?
    let createdAt: String
    let read: Bool
    enum CodingKeys: String, CodingKey {
        case id, kind, title, body, read
        case requestID = "requestId"
        case createdAt
    }
}

struct MobileState: Codable {
    var requests: [TrackedRequest]
    var notifications: [AtlasNotification]
    var cursor: Int?
    var sources: SourceHealth?
}

struct SourceHealth: Codable, Equatable {
    var ready: Bool
    var connected: Bool
}

// ---- reads --------------------------------------------------------------------------------
// Keep source-specific data extensible without silently treating missing data as an empty list.
indirect enum JSONValue: Codable, Equatable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try mobileDecoder().decode(type, from: JSONEncoder().encode(self))
    }
}

func mobileDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
}

func parseISODate(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    if let date = formatter.date(from: value) { return date }
    formatter.formatOptions.insert(.withFractionalSeconds)
    return formatter.date(from: value)
}

/// "yyyy-MM-dd" in the device's calendar.
func dayString(_ date: Date = Date(), offset: Int = 0) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: Calendar.current.date(byAdding: .day, value: offset, to: date) ?? date)
}

func parseDay(_ value: String) -> Date? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: String(value.prefix(10)))
}

struct ReadSnapshot: Codable, Equatable {
    let readId: String
    let source: String
    let data: JSONValue?
    let revision: String?
    let verifiedAt: String?
    let ageSeconds: Double?
    let freshness: String
    let refreshing: Bool
    let error: String?
    var hasData: Bool { data != nil && data != .null }
    func needsAgeDisclosure(at now: Date = Date(), connected: Bool) -> Bool {
        guard hasData else { return false }
        guard connected, let verifiedAt, let date = parseISODate(verifiedAt) else { return true }
        return now.timeIntervalSince(date) > 300
    }
}

// ---- Atlas's items ------------------------------------------------------------------------------
struct ItemNote: Codable, Equatable, Hashable {
    let text: String
    let at: String?
}

struct ProjectCounts: Codable, Equatable, Hashable {
    let todos: Int?
    let ideas: Int?
    let done: Int?
    let doing: Int?
    let blocked: Int?
}

struct PlatformItem: Codable, Identifiable, Equatable, Hashable {
    let id: String
    var title: String
    let type: String
    let status: String?
    let area: String?
    let planDay: String?
    let dueDate: String?
    let remindAt: String?
    let projectId: String?
    let boardColumn: String?
    let description: String?
    let pinned: Bool?
    let must: Bool?
    let mustWhy: String?
    let overdue: Bool?
    let done: Bool?
    var snoozedUntil: String? = nil
    var stage: String? = nil
    var dueDay: String? = nil
    var lastTouchedAt: String? = nil
    var createdAt: String? = nil
    var cadenceDays: Int? = nil
    var lastContactAt: String? = nil
    var daysSinceContact: Double? = nil
    var overdueDays: Double? = nil
    var phase: String? = nil
    var repo: String? = nil
    var link: String? = nil
    var counts: ProjectCounts? = nil
    var next: String? = nil
    var notes: [ItemNote]? = nil
    var noteCount: Int? = nil
    var suggestedType: String? = nil
    var suggestedTitle: String? = nil
    var suggestedReason: String? = nil
    var suggestedArea: String? = nil
    var suggestedProject: String? = nil
    var blockedReason: String? = nil
    var mentions: Int? = nil
    var returned: Bool? = nil

    init(id: String, title: String, type: String, status: String? = "active", area: String? = nil,
         planDay: String? = nil, dueDate: String? = nil, remindAt: String? = nil, projectId: String? = nil,
         boardColumn: String? = nil, description: String? = nil, pinned: Bool? = nil, must: Bool? = nil,
         mustWhy: String? = nil, overdue: Bool? = nil, done: Bool? = nil) {
        self.id = id; self.title = title; self.type = type; self.status = status; self.area = area
        self.planDay = planDay; self.dueDate = dueDate; self.remindAt = remindAt; self.projectId = projectId
        self.boardColumn = boardColumn; self.description = description; self.pinned = pinned; self.must = must
        self.mustWhy = mustWhy; self.overdue = overdue; self.done = done
    }

    var isDone: Bool { status == "done" || done == true }
    var isActive: Bool { status == "active" && done != true }
    var isSnoozed: Bool {
        guard let snoozedUntil else { return false }
        let end = snoozedUntil.count == 10 ? parseDay(snoozedUntil) : parseISODate(snoozedUntil)
        return (end ?? .distantPast) > Date()
    }
    var category: String { Self.areas.first { $0.0 == area }?.1 ?? "Other" }
    var typeLabel: String { Self.kinds.first { $0.0 == type }?.1 ?? type.capitalized }
    static let areas = [("home", "Home"), ("admin", "Admin"), ("finances", "Finances"),
                        ("health", "Health & Training"), ("social", "Friends & Social"),
                        ("career", "Career"), ("projects", "Side Projects"), ("direction", "Life Direction")]
    static let kinds = [("todo", "To-do"), ("project", "Project"), ("idea", "Idea"), ("goal", "Goal"),
                        ("habit", "Habit"), ("person", "Person"), ("inbox", "Inbox"), ("event", "Event")]
}

struct PlatformDay: Codable, Equatable {
    let date: String
    let today: String
    let dayEnds: String?
    let tasks: [PlatformItem]
    let overdue: [PlatformItem]
    let leftovers: [PlatformItem]
    let timed: [DayAppointment]
    var tomorrow: DayPlan? = nil
}

struct DayPlan: Codable, Equatable {
    let date: String
    let tasks: [PlatformItem]
    let timed: [DayAppointment]
}

struct DayAppointment: Codable, Equatable, Identifiable {
    let kind: String
    let title: String
    let at: String
    let allDay: Bool
    let itemId: String?
    let item: PlatformItem?
    var link: String? = nil
    var source: String? = nil
    var id: String { "\(kind):\(itemId ?? title):\(at)" }
}

struct CalendarEntry: Codable, Identifiable, Equatable {
    let id: String
    let summary: String?
    let start: Start
    var link: String? = nil
    struct Start: Codable, Equatable {
        let date: String?
        let dateTime: String?
    }
}

struct Upcoming: Codable, Equatable, Identifiable {
    let kind: String
    let title: String
    let at: String
    let allDay: Bool
    let itemId: String?
    var link: String? = nil
    var source: String? = nil
    var overdue: Bool? = nil
    var id: String { "\(kind):\(itemId ?? title):\(at)" }
    var date: Date? { allDay ? parseDay(at) : parseISODate(at) }
}

struct CaptureRecord: Codable, Equatable, Identifiable {
    let id: String
    let rawText: String
    let summary: String?
    let receivedAt: String
    let status: String?
}

struct Waiting: Codable, Equatable, Identifiable {
    let id: String
    let kind: String
    let handler: String?
    let question: String?
    let options: [String]
    let summary: String?
    let expiresAt: String?
    let runAt: String?
    var isQuestion: Bool { kind == "question" }
}

/// The dashboard as Atlas's web page sees it. Missing sections decode as empty, never as an error.
struct Dashboard: Codable, Equatable {
    var today: String
    var dayEnds: String?
    var focus: [PlatformItem] = []
    var upcoming: [Upcoming] = []
    var todos: [PlatformItem] = []
    var projectWork: [PlatformItem] = []
    var people: [PlatformItem] = []
    var goals: [PlatformItem] = []
    var habits: [PlatformItem] = []
    var projects: [PlatformItem] = []
    var inbox: [PlatformItem] = []
    var refile: [PlatformItem] = []
    var captures: [CaptureRecord] = []
    var waiting: [Waiting] = []
    var warnings: [String] = []

    enum CodingKeys: String, CodingKey {
        case today, dayEnds, focus, upcoming, todos, projectWork, people, goals, habits, projects, inbox, refile,
             captures, waiting, warnings
    }
    init(today: String) { self.today = today }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func list<T: Decodable>(_ key: CodingKeys) -> [T] { (try? c.decodeIfPresent([T].self, forKey: key)) ?? [] }
        today = try c.decode(String.self, forKey: .today)
        dayEnds = try c.decodeIfPresent(String.self, forKey: .dayEnds)
        focus = list(.focus); upcoming = list(.upcoming); todos = list(.todos); projectWork = list(.projectWork)
        people = list(.people); goals = list(.goals); habits = list(.habits); projects = list(.projects)
        inbox = list(.inbox); refile = list(.refile); captures = list(.captures); waiting = list(.waiting)
        warnings = list(.warnings)
    }
}

struct ProjectView: Codable, Equatable {
    let id: String
    let title: String
    let phase: String?
    let repo: String?
    let link: String?
    var notes: [ItemNote] = []
    var cards: [PlatformItem] = []
    var ideas: [PlatformItem] = []
    var done: [PlatformItem] = []
    var counts: ProjectCounts? = nil
    var description: String? = nil
    static let columns = [("ideas", "Ideas"), ("todo", "To do"), ("doing", "Doing"), ("blocked", "Blocked"), ("done", "Done")]
}

// ---- the widget snapshot ----------------------------------------------------------------------
/// What the widgets show. The app writes it after each refresh; the widgets refresh it themselves too.
struct WidgetSnapshot: Codable, Equatable {
    struct Entry: Codable, Equatable, Hashable {
        let title: String
        let at: Date?
        let allDay: Bool
        let kind: String
    }
    struct Task: Codable, Equatable, Hashable, Identifiable {
        let id: String
        let title: String
        var done: Bool
        let must: Bool
        let overdue: Bool
    }
    var updatedAt: Date
    var day: String
    var agenda: [Entry] = []
    var tasks: [Task] = []
    var focus: [Task] = []
    var overdueCount = 0
    var waitingCount = 0
    var connected = true

    static let placeholder = WidgetSnapshot(updatedAt: Date(), day: dayString(), agenda: [
        Entry(title: "Dinner with Sam", at: Calendar.current.date(bySettingHour: 19, minute: 0, second: 0, of: Date()), allDay: false, kind: "event")],
        tasks: [Task(id: "1", title: "Book the dentist", done: false, must: true, overdue: false),
                Task(id: "2", title: "Fix the cabinet door", done: false, must: false, overdue: false)],
        focus: [Task(id: "1", title: "Book the dentist", done: false, must: true, overdue: false),
                Task(id: "3", title: "Renew the passport", done: false, must: true, overdue: true)],
        overdueCount: 1)

    static func build(day: PlatformDay?, dashboard: Dashboard?, calendar: [CalendarEntry] = [], now: Date = Date()) -> WidgetSnapshot {
        func task(_ item: PlatformItem) -> Task {
            Task(id: item.id, title: item.title, done: item.isDone, must: item.must == true, overdue: item.overdue == true)
        }
        var agenda: [Entry] = (day?.timed ?? []).map {
            Entry(title: $0.title, at: $0.allDay ? nil : parseISODate($0.at), allDay: $0.allDay, kind: $0.kind)
        }
        let today = day?.date ?? dashboard?.today ?? dayString(now)
        for event in calendar where (event.start.date ?? event.start.dateTime.flatMap(parseISODate).map { dayString($0) }) == today {
            let at = event.start.dateTime.flatMap(parseISODate)
            if !agenda.contains(where: { $0.title == (event.summary ?? "") && $0.at == at }) {
                agenda.append(Entry(title: event.summary ?? "Untitled event", at: at, allDay: at == nil, kind: "event"))
            }
        }
        for u in dashboard?.upcoming ?? [] where u.source != nil && String(u.at.prefix(10)) == today {
            agenda.append(Entry(title: u.title, at: u.allDay ? nil : parseISODate(u.at), allDay: u.allDay, kind: u.kind))
        }
        agenda.sort { ($0.allDay ? .distantPast : $0.at ?? .distantFuture) < ($1.allDay ? .distantPast : $1.at ?? .distantFuture) }
        let tasks = ((day?.overdue ?? []) + (day?.tasks ?? [])).filter { $0.type == "todo" || $0.type == "goal" || $0.type == "person" }
        var seen = Set<String>()
        return WidgetSnapshot(updatedAt: now, day: today, agenda: agenda,
                              tasks: tasks.filter { seen.insert($0.id).inserted }.map(task),
                              focus: (dashboard?.focus ?? []).filter(\.isActive).map(task),
                              overdueCount: day?.overdue.filter { !$0.isDone }.count ?? 0,
                              waitingCount: dashboard?.waiting.count ?? 0)
    }
    var nextEntry: Entry? {
        agenda.first { !$0.allDay && ($0.at ?? .distantPast) > Date().addingTimeInterval(-15 * 60) }
    }
    var openTasks: [Task] { tasks.filter { !$0.done } }
}

enum SnapshotStore {
    static var url: URL { AtlasEnvironment.sharedContainer.appendingPathComponent("widget-snapshot.json") }
    static func load() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }
    static func save(_ snapshot: WidgetSnapshot) {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    static func clear() { try? FileManager.default.removeItem(at: url) }
    /// Tick a task off locally so a widget shows it straight away, before the next refresh.
    static func markDone(_ id: String) {
        guard var snapshot = load() else { return }
        for i in snapshot.tasks.indices where snapshot.tasks[i].id == id { snapshot.tasks[i].done = true }
        snapshot.focus.removeAll { $0.id == id }
        save(snapshot)
    }
}
