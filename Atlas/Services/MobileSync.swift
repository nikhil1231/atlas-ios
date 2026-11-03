import Foundation

@MainActor
protocol MobileTransport: AnyObject {
    func state() async throws -> MobileState
    func events(after cursor: Int, connected: @escaping () -> Void,
                receive: @escaping (EventFrame) async throws -> Void) async throws
}

@MainActor
final class MobileSync {
    enum Connection: Equatable { case stopped, connecting, live, polling }
    private(set) var projection: MobileProjection
    private(set) var connection: Connection = .stopped
    var onChange: ((MobileProjection, Connection) -> Void)?
    var onError: ((String?) -> Void)?
    var onRead: ((ReadSnapshot) -> Void)?
    /// Atlas says something the screens read (items, today, calendar...) has changed.
    var onInvalidated: (() -> Void)?
    private let transport: any MobileTransport
    private let cache: StateCache
    private let scope: String
    private let sleep: (Double) async throws -> Void
    private var worker: Task<Void, Never>?
    private var snapshot: Task<MobileState, Error>?
    private var reconciliation: Task<Void, Never>?
    private var generation = UUID()
    private var needsSnapshot = false
    private var active = false
    private var retired = false
    private var mutationSerial = 0
    private var snapshotSerial = 0
    private var recentRequests: [String: (request: TrackedRequest, serial: Int)] = [:]

    init(transport: any MobileTransport, cache: StateCache, scope: String,
         projection: MobileProjection = MobileProjection(),
         sleep: @escaping (Double) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) {
        self.transport = transport; self.cache = cache; self.scope = scope
        self.projection = projection; self.sleep = sleep
    }
    func start() {
        guard !active, !retired else { return }
        active = true
        let token = generation
        worker = Task { [weak self] in await self?.run(token: token) }
    }
    func stop() {
        active = false; generation = UUID()
        worker?.cancel(); worker = nil
        snapshot?.cancel(); snapshot = nil
        reconciliation?.cancel(); reconciliation = nil
        connection = .stopped; publish()
    }
    func retire() { retired = true; stop() }
    func refresh() async {
        guard !retired else { return }
        let token = generation
        let task: Task<MobileState, Error>
        if let snapshot { task = snapshot }
        else {
            snapshotSerial = mutationSerial
            task = Task { try await transport.state() }
            snapshot = task
        }
        let beganAt = snapshotSerial
        do {
            let state = try await task.value
            guard token == generation, !Task.isCancelled else { return }
            snapshot = nil
            // A snapshot may finish after a newer event has already been applied.
            guard state.cursor == nil || (state.cursor ?? 0) >= (projection.state.cursor ?? 0) else {
                needsSnapshot = true; return
            }
            var next = MobileProjection(state: state)
            // Preserve a newer WebSocket acceptance/update that arrived during this HTTP request.
            for update in recentRequests.values {
                if update.serial > beganAt { next.merge(update.request) }
                else if let fresh = state.requests.first(where: { $0.id == update.request.id }),
                        let a = update.request.revision, let b = fresh.revision, a > b { next.merge(update.request) }
            }
            recentRequests = recentRequests.filter { $0.value.serial > beganAt }
            projection = next
            needsSnapshot = false
            onError?(nil)
            await commit()
        } catch {
            guard token == generation else { return }
            snapshot = nil
            if !Task.isCancelled { onError?(error.localizedDescription) }
        }
    }
    func merge(_ request: TrackedRequest) async {
        guard !retired else { return }
        mutationSerial += 1
        recentRequests[request.id] = (request, mutationSerial)
        projection.merge(request)
        await commit()
        if !request.isActive || request.isQuestion { reconcileSoon() }
    }
    func accept(_ frame: EventFrame) async throws {
        guard !retired else { throw CancellationError() }
        if frame.type == "reset" { throw StreamError.reset }
        let event = try mobileDecoder().decode(MobileEvent.self, from: Data(frame.data.utf8))
        guard let id = frame.id.flatMap(Int.init), id == event.sequence, event.type == frame.type else {
            throw StreamError.invalidFrame
        }
        guard event.sequence > (projection.state.cursor ?? 0) else { return }
        let reconcile = try projection.apply(event)
        // Notification-created events carry only an ID. Keep the old cursor durable until
        // a complete snapshot supplies that notification, so a crash cannot lose its inbox entry.
        needsSnapshot = needsSnapshot || reconcile
        if event.type == "read.updated", let read = try? event.payload.decode(ReadSnapshot.self) { onRead?(read) }
        if event.type == "source.invalidated" { onInvalidated?() }
        if needsSnapshot { publish(); reconcileSoon() }
        else { await commit() }
    }
    private func reconcileSoon() {
        guard reconciliation == nil, active else { return }
        let token = generation
        reconciliation = Task { [weak self] in
            guard let self else { return }
            defer { if token == self.generation { self.reconciliation = nil } }
            do { try await self.sleep(0.15) } catch { return }
            while token == self.generation, self.active {
                await self.refresh()
                if !self.needsSnapshot { return }
                do { try await self.sleep(5) } catch { return }
            }
        }
    }
    private func run(token: UUID) async {
        // A persisted snapshot and cursor form a replay checkpoint. Fetch a new snapshot only
        // when there's no checkpoint, a known gap, or the server rejects the cursor.
        if projection.state.cursor == nil || needsSnapshot { await refresh() }
        var failures = 0
        while active, token == generation, !Task.isCancelled {
            // Old servers omit cursor; don't repeatedly request an unsupported event API.
            if let cursor = projection.state.cursor {
                connection = .connecting; publish()
                do {
                    try await transport.events(after: cursor, connected: { [weak self] in
                        guard let self, self.generation == token else { return }
                        self.connection = .live; self.publish()
                    }, receive: { [weak self] frame in
                        guard let self, self.generation == token, self.active else { throw CancellationError() }
                        failures = 0
                        try await self.accept(frame)
                    })
                } catch is CancellationError { break }
                catch StreamError.reset {
                    guard token == generation, !Task.isCancelled else { break }
                    // Expired/ahead cursors require an authoritative replacement, not a merge.
                    projection.state.cursor = nil
                    await refresh()
                    failures = 0
                    continue
                } catch {
                    guard token == generation, !Task.isCancelled else { break }
                    // Polling is the compatibility path, including servers with streaming disabled.
                }
            }
            guard token == generation, active, !Task.isCancelled else { break }
            connection = .polling; publish()
            failures = min(failures + 1, 4)
            let retryDelay = min(30.0, 5.0 * pow(2.0, Double(failures - 1)))
            var elapsed = 0.0
            await refresh()
            while elapsed < retryDelay, active, token == generation {
                let interval = min(5, retryDelay - elapsed)
                do { try await sleep(interval) } catch { return }
                elapsed += interval
                await refresh()
            }
        }
    }
    private func publish() { onChange?(projection, connection) }
    private func commit() async {
        publish()
        // Don't advance the durable cursor past a notification we haven't loaded yet.
        guard !needsSnapshot, !retired else { return }
        do { try await cache.save(projection, scope: scope) }
        catch { onError?("Couldn’t save offline state. \(error.localizedDescription)") }
    }
}
