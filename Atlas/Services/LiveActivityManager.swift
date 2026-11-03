import ActivityKit
import Foundation

@MainActor
final class LiveActivityManager {
    private var watchers: [String: Task<Void, Never>] = [:]
    private var registeredTokens: [String: String] = [:]
    private(set) var error: String?

    func pause() {
        watchers.values.forEach { $0.cancel() }
        watchers.removeAll()
    }
    func reset() async {
        pause()
        registeredTokens.removeAll()
        for activity in Activity<AtlasActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
    func synchronize(_ requests: [TrackedRequest], api: AtlasAPI) async {
        error = nil
        let active = requests.filter(\.isActive)
        for activity in Activity<AtlasActivityAttributes>.activities {
            guard !Task.isCancelled else { return }
            if let request = requests.first(where: { $0.id == activity.attributes.requestID }) {
                if request.isActive {
                    await activity.update(ActivityContent(state: request.activityState, staleDate: Date().addingTimeInterval(120)))
                    guard !Task.isCancelled else { return }
                    observe(activity, api: api)
                    if let token = activity.pushToken { await register(token, activity: activity, api: api) }
                } else {
                    await activity.end(ActivityContent(state: request.activityState, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(60)))
                    watchers.removeValue(forKey: activity.id)?.cancel()
                    registeredTokens.removeValue(forKey: activity.id)
                }
            }
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        for request in active.prefix(3) {
            guard !Task.isCancelled else { return }
            guard !Activity<AtlasActivityAttributes>.activities.contains(where: { $0.attributes.requestID == request.id }) else { continue }
            do {
                let activity = try Activity.request(attributes: AtlasActivityAttributes(requestID: request.id, kind: request.kind),
                    content: ActivityContent(state: request.activityState, staleDate: Date().addingTimeInterval(120)), pushType: .token)
                observe(activity, api: api)
            } catch { self.error = "Live Activity could not start: \(error.localizedDescription)" }
        }
    }
    private func observe(_ activity: Activity<AtlasActivityAttributes>, api: AtlasAPI) {
        guard watchers[activity.id] == nil else { return }
        watchers[activity.id] = Task { [weak self] in
            for await token in activity.pushTokenUpdates {
                guard !Task.isCancelled else { return }
                await self?.register(token, activity: activity, api: api)
            }
        }
    }
    private func register(_ token: Data, activity: Activity<AtlasActivityAttributes>, api: AtlasAPI) async {
        let value = token.map { String(format: "%02x", $0) }.joined()
        guard registeredTokens[activity.id] != value else { return }
        do {
            _ = try await api.data("activities/\(AppConfiguration.installationID)/\(activity.id)", method: "PUT",
                body: ["token": value, "environment": AppConfiguration.pushEnvironment, "request_id": activity.attributes.requestID])
            guard !Task.isCancelled else { return }
            registeredTokens[activity.id] = value
        } catch {
            guard !Task.isCancelled else { return }
            self.error = "Live Activity push registration failed: \(error.localizedDescription)" }
    }
}
