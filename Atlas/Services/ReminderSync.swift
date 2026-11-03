import EventKit
import Foundation
import UserNotifications

struct ReminderSyncResponse: Decodable {
    struct Create: Decodable {
        let title: String
        let notes: String?
        let link: String?
        let dueInMinutes: Int?
        enum CodingKeys: String, CodingKey { case title, notes, link, dueInMinutes = "due_in_minutes" }
    }
    struct Edit: Decodable {
        let op: String?
        let dueInMinutes: Int?
        let link: String?
        enum CodingKeys: String, CodingKey { case op, link, dueInMinutes = "due_in_minutes" }
    }
    let deviceActions: [Create]
    let edits: [String: Edit]
    let changes: [String]
    let nudge: String?
    let error: String?

    // Decoded with a plain JSONDecoder: edits are keyed by URLs and titles, which mustn't be case-converted.
    enum CodingKeys: String, CodingKey { case deviceActions = "device_actions", edits, changes, nudge, error }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        deviceActions = (try? c.decodeIfPresent([Create].self, forKey: .deviceActions)) ?? []
        edits = (try? c.decodeIfPresent([String: Edit].self, forKey: .edits)) ?? [:]
        changes = (try? c.decodeIfPresent([String].self, forKey: .changes)) ?? []
        nudge = try? c.decodeIfPresent(String.self, forKey: .nudge)
        error = try? c.decodeIfPresent(String.self, forKey: .error)
    }
}

/// What a reminder looks like to the sync, independent of EventKit (so it can be tested).
struct ReminderLine: Equatable {
    let done: Bool
    let due: Date?
    let url: String?
    let title: String

    /// `open | <due, ISO 8601> | <URL> | <title>` or `done |  | <URL> | <title>`, as Atlas's phone.py reads it.
    var line: String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        let when = done ? "" : due.map { formatter.string(from: $0) } ?? ""
        let title = title.replacingOccurrences(of: "\n", with: " ")
        return "\(done ? "done" : "open") | \(when) | \(url ?? "") | \(title)"
    }
    /// Atlas keys its edits by the reminder's URL (its title if it has none) without dots.
    var editKey: String { ((url?.isEmpty == false ? url : nil) ?? title).replacingOccurrences(of: ".", with: "") }
}

/// Keeps one Reminders list in step with Atlas's to-dos, both ways, instead of the Atlas Sync Shortcut:
/// ticks and snoozes on the phone reach Atlas, and Atlas's new reminders, ticks, drops and new times
/// reach the phone. Runs when the app opens, when Reminders changes, after a capture and in the background.
@MainActor
final class ReminderSync: ObservableObject {
    @Published private(set) var status = "Off"
    @Published private(set) var lastSync: Date?
    @Published private(set) var authorized = false
    @Published private(set) var lists: [EKCalendar] = []
    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Self.enabledKey); status = enabled ? "Waiting to sync" : "Off" }
    }
    @Published var listID: String? {
        didSet { UserDefaults.standard.set(listID, forKey: Self.listKey) }
    }
    private let store = EKEventStore()
    private var running = false
    private var changeObserver: NSObjectProtocol?
    private var debounce: Task<Void, Never>?
    private var lastAttempt = Date.distantPast
    private var writing = false
    var api: (() -> AtlasAPI?)?
    static let enabledKey = "remindersSyncEnabled"
    static let listKey = "remindersListID"

    init() {
        enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        listID = UserDefaults.standard.string(forKey: Self.listKey)
        refreshAuthorization()
        if enabled { status = "Waiting to sync" }
        changeObserver = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.storeChanged() }
        }
    }

    var selectedList: EKCalendar? {
        guard let listID else { return nil }
        return store.calendar(withIdentifier: listID)
    }

    func refreshAuthorization() {
        let state = EKEventStore.authorizationStatus(for: .reminder)
        authorized = state == .fullAccess
        if authorized { lists = store.calendars(for: .reminder).sorted { $0.title < $1.title } }
    }

    func requestAccess() async {
        do {
            authorized = try await store.requestFullAccessToReminders()
        } catch { status = error.localizedDescription }
        refreshAuthorization()
        if !authorized { status = "Allow Reminders access in iOS Settings" }
        // Default to a list called Atlas (or the old Noodle one), as the Shortcut setup suggests.
        if authorized, listID == nil {
            listID = (lists.first { $0.title == "Atlas" } ?? lists.first { $0.title == "Noodle" })?.calendarIdentifier
        }
    }

    func createList() {
        let list = EKCalendar(for: .reminder, eventStore: store)
        list.title = "Atlas"
        list.source = store.defaultCalendarForNewReminders()?.source ?? store.sources.first { $0.sourceType == .local }
        do {
            try store.saveCalendar(list, commit: true)
            refreshAuthorization()
            listID = list.calendarIdentifier
        } catch { status = "Couldn’t create the list: \(error.localizedDescription)" }
    }

    private func storeChanged() {
        guard enabled, !writing else { return }
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self, let api = self.api?() else { return }
            await self.sync(api: api)
        }
    }

    /// `force` skips the short rate limit (Sync now, or after a capture that may have made a reminder).
    func sync(api: AtlasAPI, force: Bool = false) async {
        guard enabled, api.credentials.isConfigured, !running else { return }
        guard force || Date().timeIntervalSince(lastAttempt) > 20 else { return }
        refreshAuthorization()
        guard authorized else { status = "Allow Reminders access in Settings"; return }
        guard let list = selectedList else { status = "Choose a Reminders list"; return }
        running = true; lastAttempt = Date()
        defer { running = false }
        status = "Syncing…"
        do {
            let open = await fetch(store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: [list]))
            let since = Calendar.current.date(byAdding: .day, value: -14, to: Date())
            let done = await fetch(store.predicateForCompletedReminders(withCompletionDateStarting: since, ending: Date(), calendars: [list]))
            let lines = (open + done).map { Self.line(for: $0) }
            let response = try await api.syncReminders(lines.map(\.line))
            if let error = response.error { throw APIError(message: error) }
            try apply(response, open: open, list: list)
            lastSync = Date()
            status = response.changes.isEmpty ? "Up to date" : response.changes.joined(separator: "\n")
            if let nudge = response.nudge { await notify(nudge) }
        } catch {
            status = "Couldn’t sync: \(error.localizedDescription)"
        }
    }

    static func line(for reminder: EKReminder) -> ReminderLine {
        ReminderLine(done: reminder.isCompleted,
                     due: reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) },
                     url: reminder.url?.absoluteString, title: reminder.title ?? "")
    }

    private func fetch(_ predicate: NSPredicate) async -> [EKReminder] {
        await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { continuation.resume(returning: $0 ?? []) }
        }
    }

    private func apply(_ response: ReminderSyncResponse, open: [EKReminder], list: EKCalendar) throws {
        writing = true
        defer { writing = false }
        var dirty = false
        for reminder in open {
            guard let edit = response.edits[Self.line(for: reminder).editKey] else { continue }
            switch edit.op {
            case "done": reminder.isCompleted = true
            case "delete": try store.remove(reminder, commit: false); dirty = true; continue
            case "move": if let minutes = edit.dueInMinutes { setDue(reminder, minutes: minutes) }
            default: break
            }
            if let link = edit.link, let url = URL(string: link) { reminder.url = url }
            try store.save(reminder, commit: false)
            dirty = true
        }
        for create in response.deviceActions {
            let reminder = EKReminder(eventStore: store)
            reminder.calendar = list
            reminder.title = create.title
            if let notes = create.notes, !notes.isEmpty { reminder.notes = notes }
            if let link = create.link { reminder.url = URL(string: link) }
            setDue(reminder, minutes: create.dueInMinutes ?? 0)
            try store.save(reminder, commit: false)
            dirty = true
        }
        if dirty { try store.commit() }
    }

    private func setDue(_ reminder: EKReminder, minutes: Int) {
        let due = Date().addingTimeInterval(TimeInterval(max(0, minutes) * 60))
        reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
        reminder.alarms?.forEach { reminder.removeAlarm($0) }
        reminder.addAlarm(EKAlarm(absoluteDate: due))
    }

    private func notify(_ text: String) async {
        let content = UNMutableNotificationContent()
        content.title = "Atlas"
        content.body = text
        content.threadIdentifier = "atlas-morning"
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "atlas-nudge-\(UUID().uuidString)", content: content, trigger: nil))
    }
}
