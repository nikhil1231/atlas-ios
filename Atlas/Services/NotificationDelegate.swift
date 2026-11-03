import UIKit
import UserNotifications

extension Notification.Name {
    static let atlasPushToken = Notification.Name("atlasPushToken")
    static let atlasPushError = Notification.Name("atlasPushError")
    static let atlasNotificationOpened = Notification.Name("atlasNotificationOpened")
    static let atlasAudioInterrupted = Notification.Name("atlasAudioInterrupted")
}

@MainActor
final class ForegroundNotificationPolicy {
    static let shared = ForegroundNotificationPolicy()
    var shouldSuppress: (([AnyHashable: Any]) -> Bool)?
    private var seen: [String] = []
    func suppress(_ info: [AnyHashable: Any]) -> Bool {
        if let id = info["notification_id"] as? String, seen.contains(id) { return true }
        let suppress = shouldSuppress?(info) ?? false
        if let id = info["notification_id"] as? String {
            seen.append(id)
            if seen.count > 200 { seen.removeFirst(seen.count - 200) }
        }
        return suppress
    }
    func reset() { seen.removeAll() }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        BackgroundRefresh.register { AppModel.shared }
        return true
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: "pushToken")
        NotificationCenter.default.post(name: .atlasPushToken, object: token)
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NotificationCenter.default.post(name: .atlasPushError, object: error.localizedDescription)
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let info = notification.request.content.userInfo
        Task { @MainActor in
            let suppressed = ForegroundNotificationPolicy.shared.suppress(info)
            completionHandler(suppressed ? [.list] : [.banner, .sound, .list])
        }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        DispatchQueue.main.async {
            var routing: [String: String] = [:]
            for key in ["notification_id", "request_id"] {
                if let value = info[key] as? String { routing[key] = value }
            }
            UserDefaults.standard.set(routing, forKey: "pendingNotification")
            NotificationCenter.default.post(name: .atlasNotificationOpened, object: nil, userInfo: info)
        }
        completionHandler()
    }
}
