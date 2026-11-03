import AVFoundation
import SwiftUI

@main
@MainActor
struct AtlasApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .tint(Theme.accent)
                .onOpenURL { model.handleURL($0) }
                .onAppear { AppRouter.shared.attach { [weak model] in model?.route($0) } }
                .onReceive(NotificationCenter.default.publisher(for: .atlasPushToken)) { _ in
                    Task { await model.refresh() }
                }
                .onReceive(NotificationCenter.default.publisher(for: .atlasPushError)) { event in
                    model.pushStatus = "Push registration failed: \(event.object as? String ?? "Unknown error")"
                }
                .onReceive(NotificationCenter.default.publisher(for: .atlasNotificationOpened)) { event in
                    Task { await model.openPush(event.userInfo ?? [:]) }
                }
                .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { event in
                    if let raw = event.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                       AVAudioSession.InterruptionType(rawValue: raw) == .began { model.voice.disconnect() }
                }
                .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { event in
                    if let raw = event.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                       AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable { model.voice.disconnect() }
                }
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    await model.prepare()
                    Task { await model.updatePushStatus() }
                    if let pending = UserDefaults.standard.dictionary(forKey: "pendingNotification") {
                        await model.openPush(pending)
                    }
                    guard !Task.isCancelled else { return }
                    model.startForeground()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { model.stopForeground() }
                }
        }
    }
}
