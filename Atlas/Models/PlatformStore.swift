import Combine
import Foundation

/// Read through the same authenticated adapter used by voice. Never infer success from acceptance.
@MainActor
final class PlatformStore: ObservableObject {
    @Published private(set) var items: [PlatformItem] = []
    @Published private(set) var day: PlatformDay?
    @Published private(set) var calendar: [CalendarEntry] = []
    @Published private(set) var dashboard: Dashboard?
    @Published private(set) var loading = false
    @Published private(set) var errors: [String: String] = [:]
    @Published private(set) var updatedAt: Date?
    /// Item, pending-question or capture ID → the tracked request changing it (or "Sending…").
    @Published private(set) var pending: [String: String] = [:]
    @Published private(set) var projects: [String: ProjectView] = [:]
    @Published private(set) var details: [String: PlatformItem] = [:]
    var onRefreshed: (() -> Void)?
    private var operationIDs: [String: UUID] = [:]
    private var generation = UUID()
    private var readSerial = 0
    private var verifiedAt: [String: Date] = [:]
    private var refreshing = false
    private var refreshAgain = false

    func reset() {
        generation = UUID(); readSerial += 1
        items = []; day = nil; calendar = []; dashboard = nil; errors = [:]; updatedAt = nil
        pending = [:]; operationIDs = [:]; loading = false; verifiedAt = [:]; projects = [:]; details = [:]
    }

    /// Coalesces: a refresh asked for while one is running runs once more afterwards.
    func refresh(api: AtlasAPI) async {
        guard api.credentials.isConfigured else { return }
        if refreshing { refreshAgain = true; return }
        refreshing = true
        defer { refreshing = false }
        repeat {
            refreshAgain = false
            await load(api: api)
        } while refreshAgain && !Task.isCancelled
        onRefreshed?()
    }

    private func load(api: AtlasAPI) async {
        let token = generation
        readSerial += 1
        let serial = readSerial
        loading = true
        defer { if token == generation && serial == readSerial { loading = false } }
        let tz = TimeZone.current.identifier
        // Each source keeps its last good value independently if another is unavailable.
        for (key, source, query) in [
            ("Today", "items", ["scope": "today", "tz": tz]),
            ("Dashboard", "dashboard", ["tz": tz]),
            ("Everything", "items", ["scope": "all", "tz": tz]),
            ("Calendar", "calendar", ["tz": tz])
        ] {
            do {
                let snapshot = try await api.read(source: source, query: query)
                guard token == generation, serial == readSerial, !Task.isCancelled else { return }
                guard let data = snapshot.data, snapshot.hasData else {
                    errors[key] = snapshot.refreshing ? "Loading \(key.lowercased()) from Atlas…" : "\(key) is unavailable. Pull to refresh."
                    continue
                }
                if key == "Everything" { items = try data.decode([PlatformItem].self) }
                if key == "Today" { day = try data.decode(PlatformDay.self) }
                if key == "Calendar" { calendar = try data.decode([CalendarEntry].self) }
                if key == "Dashboard" { dashboard = try data.decode(Dashboard.self) }
                verifiedAt[key] = snapshot.verifiedAt.flatMap(parseISODate)
                updatedAt = verifiedAt.values.min()
                errors[key] = snapshot.freshness == "fresh" && snapshot.error == nil ? nil
                    : key == "Calendar" && snapshot.error != nil ? snapshot.error
                    : "\(key) may be out of date. Pull to refresh."
            } catch {
                guard token == generation, serial == readSerial, !Task.isCancelled else { return }
                errors[key] = "\(key): \(error.localizedDescription)"
            }
        }
    }

    func loadProject(_ id: String, api: AtlasAPI) async {
        let token = generation
        do {
            let snapshot = try await api.read(source: "project", query: ["project_id": id, "tz": TimeZone.current.identifier])
            guard token == generation, let data = snapshot.data else { return }
            projects[id] = try data.decode(ProjectView.self)
            errors["Project"] = nil
        } catch {
            guard token == generation else { return }
            errors["Project"] = "Couldn’t load the project. \(error.localizedDescription)"
        }
    }

    func loadDetail(_ id: String, api: AtlasAPI) async {
        let token = generation
        guard let data = try? await api.read(source: "item", query: ["item_id": id]).data,
              token == generation, let item = try? data.decode(PlatformItem.self) else { return }
        details[id] = item
    }

    /// The freshest copy of an item from any source.
    func item(_ id: String) -> PlatformItem? {
        details[id] ?? items.first { $0.id == id } ?? dashboard?.people.first { $0.id == id }
            ?? dashboard?.projects.first { $0.id == id } ?? dashboard?.focus.first { $0.id == id }
            ?? day?.tasks.first { $0.id == id }
    }

    func update(_ item: PlatformItem, fields: [String: Any], api: AtlasAPI) async -> TrackedRequest? {
        await perform("items.update", input: fields.merging(["item_id": item.id]) { a, _ in a }, key: item.id, api: api)
    }

    /// A typed change. `key` is what it's about (shown as pending there until it finishes).
    /// An uncertain failure keeps its submission ID, so retrying the same change can't apply it twice.
    func perform(_ handler: String, input: [String: Any], key: String, api: AtlasAPI) async -> TrackedRequest? {
        guard pending[key] == nil else { return nil }
        let token = generation
        let body = (try? JSONSerialization.data(withJSONObject: input, options: .sortedKeys)) ?? Data()
        let signature = handler + key + String(decoding: body, as: UTF8.self)
        let id = operationIDs[signature] ?? UUID()
        operationIDs[signature] = id
        pending[key] = "Sending…"
        do {
            let request = try await api.operation(handler: handler, input: input, id: id)
            guard token == generation else { return nil }
            pending[key] = request.id
            errors["Action"] = nil
            return request
        } catch {
            guard token == generation else { return nil }
            pending[key] = nil
            errors["Action"] = "Couldn’t confirm the change. Retry the same action safely. \(error.localizedDescription)"
            return nil
        }
    }

    func reconcile(_ requests: [TrackedRequest]) -> Bool {
        var changed = false
        for (key, requestID) in pending {
            if let request = requests.first(where: { $0.id == requestID }), !request.isActive {
                pending[key] = nil
                operationIDs = operationIDs.filter { $0.value.uuidString.caseInsensitiveCompare(requestID) != .orderedSame }
                if request.status != "completed" || request.phase == "partial" {
                    errors["Action"] = request.summary.isEmpty ? request.statusLabel : request.summary
                }
                changed = true
            }
        }
        return changed
    }

    func clearActionError() { errors["Action"] = nil }
}
