import BackgroundTasks
import Foundation
import WidgetKit

/// Hands the widgets a fresh snapshot after the app reads Atlas, and only reloads them when it changed
/// (WidgetKit budgets reloads).
@MainActor
enum WidgetBridge {
    private static var last: WidgetSnapshot?

    static func publish(_ store: PlatformStore) {
        guard store.day != nil || store.dashboard != nil else { return }
        var snapshot = WidgetSnapshot.build(day: store.day, dashboard: store.dashboard, calendar: store.calendar)
        let previous = last ?? SnapshotStore.load()
        snapshot.updatedAt = Date()
        SnapshotStore.save(snapshot)
        var comparable = snapshot; comparable.updatedAt = previous?.updatedAt ?? comparable.updatedAt
        if comparable != previous { WidgetCenter.shared.reloadAllTimelines() }
        last = snapshot
    }

    static func clear() {
        last = nil
        SnapshotStore.clear()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// A periodic background refresh: today's snapshot for the widgets, and the Reminders sync.
enum BackgroundRefresh {
    static let identifier = "ing.nikhil.noodle.refresh"

    static func register(model: @escaping @MainActor () -> AppModel?) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            schedule()
            let work = Task { @MainActor in
                await model()?.backgroundRefresh()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date().addingTimeInterval(30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
