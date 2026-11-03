import Foundation

// Requests, notifications, credentials and Atlas's items are in Shared/AtlasCore.swift,
// so the widgets and share extension decode exactly what the app does.

extension TrackedRequest {
    var activityState: AtlasActivityAttributes.ContentState {
        .init(title: title, status: status, summary: String(summary.prefix(500)), executeAt: executeAt, phase: phase)
    }
}

struct TranscriptLine: Identifiable {
    let id: String
    var role: String
    var text: String
}

enum AppConfiguration {
    static var backendURL: URL { AtlasEnvironment.backendURL }
    static var pushEnvironment: String {
        Bundle.main.object(forInfoDictionaryKey: "AtlasPushEnvironment") as? String ?? "sandbox"
    }
    static let installationID: String = {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: "installationID") { return existing }
        let value = UUID().uuidString
        defaults.set(value, forKey: "installationID")
        return value
    }()
}
