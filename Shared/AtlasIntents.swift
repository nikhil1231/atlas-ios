import AppIntents
import Foundation
import WidgetKit

/// The tick button on the Today and Focus widgets. Runs in the widget's own process, so it works
/// without opening the app. It reports Atlas's actual result: a failed tick throws and shows as failed.
struct CompleteTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Tick off a to-do"
    static let description = IntentDescription("Marks a to-do done in Atlas.")
    static let isDiscoverable = false

    @Parameter(title: "To-do ID") var itemID: String
    @Parameter(title: "Title") var itemTitle: String

    init() {}
    init(itemID: String, title: String) { self.itemID = itemID; self.itemTitle = title }

    func perform() async throws -> some IntentResult {
        let result = try await AtlasClient.load().operation("items.update", input: ["item_id": itemID, "status": "done"])
        guard result.status == "completed" else { throw APIError(message: result.summary) }
        SnapshotStore.markDone(itemID)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

enum WidgetKinds {
    static let today = "AtlasToday"
    static let focus = "AtlasFocus"
}
