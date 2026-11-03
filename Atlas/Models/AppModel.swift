import ActivityKit
import Combine
import Foundation
import UIKit
import UserNotifications

@MainActor
final class AppModel: ObservableObject {
    /// The one the app runs; background tasks and intents reach it here even before a scene exists.
    static let shared = AppModel()
    @Published private(set) var loadingCredentials = true
    @Published private(set) var sendingMessage = false
    @Published var messageError: String?
    private var preparation: Task<Credentials, Never>?
    private var pendingMessage: (id: UUID, text: String, questionID: String?)?
    @Published var requests: [TrackedRequest] = []
    @Published var notifications: [AtlasNotification] = []
    @Published var credentials = Credentials()
    @Published var showSettings = false
    @Published var selectedTab = 3
    @Published var selectedRequestID: String?
    @Published var selectedNotification: AtlasNotification?
    @Published var voiceQuestion: TrackedRequest?
    @Published var error: String?
    @Published var pushStatus = "Notifications are off"
    @Published var activityError: String?
    @Published var lastSynced: Date?
    let voice = VoiceSession()
    let platform = PlatformStore()
    let reminders = ReminderSync()
    @Published var openProjectID: String?
    @Published var openItemID: String?
    private var finishedCaptures: Set<String> = []
    private var platformTask: Task<Void, Never>?
    let api: AtlasAPI
    private let activities = LiveActivityManager()
    @Published private(set) var connection: MobileSync.Connection = .stopped
    @Published private(set) var sourceHealth: SourceHealth?
    @Published private(set) var showingSavedState = false
    private let cache = StateCache()
    private var sync: MobileSync?
    private var foregroundActive = false
    private var activityTask: Task<Void, Never>?
    private var accountGeneration = UUID()
    private var registeredPush: String?

    init() {
        api = AtlasAPI(credentials: Credentials())
        voice.onRequest = { [weak self] request in
            guard let self else { return }
            let engine = self.sync
            Task { await engine?.merge(request) }
        }
        reminders.api = { [weak self] in self?.credentials.isConfigured == true ? self?.api : nil }
        platform.onRefreshed = { [weak self] in
            guard let self else { return }
            WidgetBridge.publish(self.platform)
        }
        ForegroundNotificationPolicy.shared.shouldSuppress = { [weak self] info in
            guard let self else { return false }
            return self.voice.isPresenting(requestID: info["request_id"] as? String,
                notificationID: info["notification_id"] as? String)
        }
    }
    func prepare() async {
        guard loadingCredentials else { return }
        // Keychain can block during device unlock; keep it off the first-frame path.
        if preparation == nil {
            preparation = Task.detached(priority: .userInitiated) {
                (try? KeychainStore().load()) ?? Credentials()
            }
        }
        guard let loaded = await preparation?.value, loadingCredentials else { return }
        credentials = loaded
        api.credentials = loaded
        await configureSync()
        loadingCredentials = false
    }

    func sendMessage(_ text: String) async -> Bool {
        guard !sendingMessage, !loadingCredentials else { return false }
        guard credentials.isConfigured else { showSettings = true; return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 5000 else { return false }
        let questionID = voiceQuestion.flatMap { question in
            requests.first(where: { $0.id == question.id && $0.isQuestion })?.id
        }
        if pendingMessage?.text != trimmed {
            pendingMessage = (UUID(), trimmed, questionID)
        }
        guard let submission = pendingMessage else { return false }
        let generation = accountGeneration
        let engine = sync
        sendingMessage = true
        messageError = nil
        defer { sendingMessage = false }
        do {
            let request = try await api.submit(text: submission.text, id: submission.id, questionID: submission.questionID)
            guard generation == accountGeneration else { return false }
            await engine?.merge(request)
            pendingMessage = nil
            await refresh()
            return true
        } catch {
            guard generation == accountGeneration else { return false }
            messageError = "Couldn’t confirm submission. Retry the same message to check safely. \(error.localizedDescription)"
            return false
        }
    }

    var openQuestions: [TrackedRequest] { requests.filter(\.isQuestion) }
    var activeRequests: [TrackedRequest] { requests.filter(\.isActive) }
    /// Activity shows captures and questions; a direct edit only while it runs or if it went wrong.
    var visibleRequests: [TrackedRequest] { requests.filter { !$0.isAction || $0.isActive || $0.status != "completed" } }
    var unreadCount: Int { notifications.filter { !$0.read }.count }

    private func configureSync() async {
        let generation = accountGeneration
        let scope = StateCache.scope(credentials: credentials)
        let saved = credentials.isConfigured ? await cache.load(scope: scope) : nil
        guard generation == accountGeneration else { return }
        let projection = saved ?? MobileProjection()
        requests = projection.state.requests
        notifications = projection.state.notifications
        lastSynced = saved?.savedAt
        showingSavedState = saved != nil
        sourceHealth = projection.state.sources
        let engine = MobileSync(transport: api, cache: cache, scope: scope, projection: projection)
        engine.onChange = { [weak self] projection, connection in
            guard let self, generation == self.accountGeneration else { return }
            self.requests = projection.state.requests
            self.notifications = projection.state.notifications
            self.connection = connection
            self.sourceHealth = projection.state.sources
            if projection.savedAt != saved?.savedAt {
                self.lastSynced = projection.savedAt
                self.showingSavedState = false
            }
            if self.platform.reconcile(self.requests) {
                Task { await self.platform.refresh(api: self.api) }
            }
            self.syncRemindersAfterCaptures()
            self.updateActivities()
        }
        engine.onInvalidated = { [weak self] in
            guard let self, generation == self.accountGeneration else { return }
            Task { await self.platform.refresh(api: self.api) }
        }
        engine.onError = { [weak self] message in
            guard let self, generation == self.accountGeneration else { return }
            self.error = message
        }
        sync = engine
    }
    func startForeground() {
        foregroundActive = true
        guard credentials.isConfigured else { return }
        sync?.start()
        updateActivities()
        Task { await reminders.sync(api: api) }
        if platformTask == nil {
            platformTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    await self.platform.refresh(api: self.api)
                    do { try await Task.sleep(for: .seconds(15)) } catch { return }
                }
            }
        }
    }
    func stopForeground() {
        foregroundActive = false
        BackgroundRefresh.schedule()
        sync?.stop()
        platformTask?.cancel(); platformTask = nil
        activityTask?.cancel(); activityTask = nil
        activities.pause()
        voice.disconnect()
    }
    private func updateActivities() {
        guard foregroundActive else { return }
        guard activityTask == nil else { return }
        let generation = accountGeneration
        activityTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            guard let self, generation == self.accountGeneration, self.foregroundActive else { return }
            // Serialize ActivityKit updates and coalesce bursts from journal replay.
            var last: [TrackedRequest] = []
            repeat {
                last = self.requests
                await self.activities.synchronize(last, api: self.api)
            } while last != self.requests && self.foregroundActive && !Task.isCancelled
            self.activityError = self.activities.error
            if generation == self.accountGeneration { self.activityTask = nil }
        }
    }
    func save(_ value: Credentials) async {
        do {
            voice.clearConversation()
            sync?.retire()
            platformTask?.cancel(); platformTask = nil
            platform.reset()
            WidgetBridge.clear()
            activityTask?.cancel(); activityTask = nil
            accountGeneration = UUID()
            ForegroundNotificationPolicy.shared.reset()
            await activities.reset()
            if credentials.isConfigured {
                _ = try? await api.data("devices/\(AppConfiguration.installationID)", method: "DELETE")
            }
            try await cache.clear()
            try KeychainStore().save(value)
            credentials = value
            api.credentials = value
            requests = []; notifications = []; lastSynced = nil; registeredPush = nil
            pendingMessage = nil; messageError = nil; voiceQuestion = nil
            selectedRequestID = nil; selectedNotification = nil
            UserDefaults.standard.removeObject(forKey: "pendingNotification")
            error = nil
            await configureSync()
            showSettings = false
            if foregroundActive { startForeground() }
            await refresh()
        } catch {
            self.error = error.localizedDescription
            await configureSync()
            if foregroundActive { startForeground() }
        }
    }
    func refresh() async {
        guard credentials.isConfigured else { return }
        await sync?.refresh()
        await platform.refresh(api: api)
        let generation = accountGeneration
        if let token = UserDefaults.standard.string(forKey: "pushToken"), registeredPush != token {
            do {
                try await api.registerPush(token)
                if generation == accountGeneration { registeredPush = token }
            } catch { pushStatus = "Push registration failed: \(error.localizedDescription)" }
        }
    }
    func updateItem(_ item: PlatformItem, fields: [String: Any]) async {
        guard credentials.isConfigured else { showSettings = true; return }
        let generation = accountGeneration
        if let request = await platform.update(item, fields: fields, api: api), generation == accountGeneration {
            await sync?.merge(request)
            if platform.reconcile(requests) { await platform.refresh(api: api) }
        }
    }
    /// Any typed change from the app (see Atlas's mobile_platform.py for the handlers).
    func perform(_ handler: String, input: [String: Any], key: String) async {
        guard credentials.isConfigured else { showSettings = true; return }
        let generation = accountGeneration
        if let request = await platform.perform(handler, input: input, key: key, api: api), generation == accountGeneration {
            await sync?.merge(request)
            if platform.reconcile(requests) { await platform.refresh(api: api) }
            // Ticks, snoozes and new times move the phone's reminder too.
            if handler == "items.update" || handler == "captures.undo" || handler == "items.delete" {
                Task { await reminders.sync(api: api, force: true) }
            }
        }
    }

    /// A finished capture may have made a reminder: put it on the phone now rather than at the next sync.
    private func syncRemindersAfterCaptures() {
        let finished = requests.filter { !$0.isAction && !$0.isActive && $0.status == "completed" }.map(\.id)
        let fresh = Set(finished).subtracting(finishedCaptures)
        let first = finishedCaptures.isEmpty
        finishedCaptures.formUnion(fresh)
        guard !first, !fresh.isEmpty, reminders.enabled else { return }
        Task { await reminders.sync(api: api, force: true) }
    }

    /// The BGAppRefreshTask: fresh widgets and a Reminders sync while the app isn't open.
    func backgroundRefresh() async {
        await prepare()
        guard credentials.isConfigured else { return }
        await platform.refresh(api: api)
        await reminders.sync(api: api, force: true)
    }

    func route(_ route: AppRouter.Route) {
        switch route {
        case .today: selectedTab = 3
        case .everything: selectedTab = 4
        case .talk: selectedTab = 0; startVoice()
        case .activity: selectedTab = 1
        case .inbox: selectedTab = 2
        case .request(let id): selectedTab = 1; selectedRequestID = id
        case .item(let id): openItemID = id
        case .project(let id): selectedTab = 4; openProjectID = id
        }
        Task { await refresh() }
    }

    func startVoice(question: TrackedRequest? = nil) {
        guard !loadingCredentials else { return }
        guard credentials.isConfigured else { showSettings = true; return }
        voiceQuestion = question
        selectedTab = 0
        Task {
            guard foregroundActive, !Task.isCancelled else { return }
            await voice.connect(api: api, question: question)
        }
    }
    func answer(_ request: TrackedRequest) {
        voice.disconnect()
        selectedRequestID = nil
        startVoice(question: request)
    }
    func cancel(_ request: TrackedRequest) async {
        do {
            _ = try await api.data("requests/\(request.id)/cancel", method: "POST")
            await refresh()
        } catch { self.error = error.localizedDescription }
    }
    func openNotification(_ note: AtlasNotification) async {
        do {
            _ = try await api.data("notifications/\(note.id)/read", method: "POST")
            await refresh()
        } catch { self.error = error.localizedDescription }
        if let id = note.requestID { selectedRequestID = id } else { selectedNotification = note }
    }
    func enableNotifications() async {
        do {
            let center = UNUserNotificationCenter.current()
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            pushStatus = granted ? "Notifications enabled" : "Notifications are disabled in iOS Settings"
            if granted { UIApplication.shared.registerForRemoteNotifications() }
        } catch { pushStatus = error.localizedDescription }
    }
    func updatePushStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let enabled = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional || settings.authorizationStatus == .ephemeral
        pushStatus = enabled ? "Notifications enabled" : "Notifications are disabled in iOS Settings"
        if enabled { UIApplication.shared.registerForRemoteNotifications() }
    }
    func openPush(_ info: [AnyHashable: Any]) async {
        UserDefaults.standard.removeObject(forKey: "pendingNotification")
        selectedTab = 2
        await refresh()
        if let id = info["notification_id"] as? String, let note = notifications.first(where: { $0.id == id }) {
            await openNotification(note)
        } else if let id = info["request_id"] as? String { selectedRequestID = id }
    }
    func handleURL(_ url: URL) {
        if let route = AppRouter.route(url) { self.route(route) }
    }
}
