import AppIntents
import Foundation

/// "Hey Siri, tell Atlas…", the Action Button and Shortcuts. These run without bringing the app forward
/// (except Talk), through the same capture pipeline as voice and typing.
struct AddToAtlasIntent: AppIntent {
    static let title: LocalizedStringResource = "Tell Atlas"
    static let description = IntentDescription("Files a thought, to-do, reminder or question in Atlas, and says what it did.")
    static let openAppWhenRun = false

    @Parameter(title: "Thought", requestValueDialog: "What’s on your mind?")
    var text: String

    static var parameterSummary: some ParameterSummary { Summary("Tell Atlas \(\.$text)") }

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw APIError(message: "There was nothing to send.") }
        let request = try await AtlasClient.load().submitAndWait(String(trimmed.prefix(5000)))
        let reply: String
        switch request.status {
        case "completed": reply = request.summary
        case "awaiting_answer": reply = "Atlas has a question: \(request.summary). Open Atlas to answer."
        case "queued", "running": reply = "Sent. Atlas is still working on it; you'll get a notification."
        default: reply = "That didn’t go through: \(request.summary)"
        }
        return .result(value: reply, dialog: IntentDialog(stringLiteral: Self.spoken(reply)))
    }

    /// Summaries carry emoji markers for the dashboard; Siri reads them out, so drop them.
    static func spoken(_ text: String) -> String {
        String(text.unicodeScalars.filter { !$0.properties.isEmojiPresentation && $0.properties.generalCategory != .otherSymbol })
            .replacingOccurrences(of: "\n", with: ". ").trimmingCharacters(in: .whitespaces)
    }
}

struct WhatsOnTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "What’s on today"
    static let description = IntentDescription("Reads out today’s plan from Atlas: what’s timed, what’s on your list and what’s overdue.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let client = try AtlasClient.load()
        guard let data = try await client.read("items", query: ["scope": "today"]).data else {
            throw APIError(message: "Atlas couldn’t read today right now.")
        }
        let summary = Self.summary(try data.decode(PlatformDay.self))
        return .result(value: summary, dialog: IntentDialog(stringLiteral: summary))
    }

    static func summary(_ day: PlatformDay, now: Date = Date()) -> String {
        var parts: [String] = []
        let timed = day.timed.filter { $0.allDay || (parseISODate($0.at) ?? now) > now.addingTimeInterval(-1800) }
        if !timed.isEmpty {
            let formatter = DateFormatter(); formatter.timeStyle = .short
            let list = timed.prefix(4).map { a in
                a.allDay ? a.title : "\(a.title) at \(parseISODate(a.at).map(formatter.string) ?? "")"
            }
            parts.append("Coming up: " + list.joined(separator: ", ") + ".")
        }
        let open = day.tasks.filter { !$0.isDone }
        if !open.isEmpty {
            parts.append("On your list: " + open.prefix(5).map(\.title).joined(separator: ", ")
                         + (open.count > 5 ? ", and \(open.count - 5) more." : "."))
        }
        let late = day.overdue.filter { !$0.isDone }
        if !late.isEmpty { parts.append("\(late.count) overdue, starting with \(late[0].title).") }
        return parts.isEmpty ? "Nothing planned today. A clear day." : parts.joined(separator: " ")
    }
}

struct TalkToAtlasIntent: AppIntent {
    static let title: LocalizedStringResource = "Talk to Atlas"
    static let description = IntentDescription("Opens Atlas and starts a voice conversation.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.open(.talk)
        return .result()
    }
}

struct AtlasShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddToAtlasIntent(), phrases: ["Tell \(.applicationName)", "Add to \(.applicationName)",
                                                          "Note in \(.applicationName)"],
                    shortTitle: "Tell Atlas", systemImageName: "text.bubble")
        AppShortcut(intent: WhatsOnTodayIntent(), phrases: ["What’s on today in \(.applicationName)",
                                                            "What’s my day in \(.applicationName)"],
                    shortTitle: "What’s on today", systemImageName: "sun.max")
        AppShortcut(intent: TalkToAtlasIntent(), phrases: ["Talk to \(.applicationName)", "Start \(.applicationName)"],
                    shortTitle: "Talk to Atlas", systemImageName: "waveform")
    }
}

/// Where an intent, widget or link wants the app to go once it's in front.
@MainActor
final class AppRouter {
    enum Route: Equatable { case today, everything, talk, activity, inbox, item(String), request(String), project(String) }
    static let shared = AppRouter()
    var handler: ((Route) -> Void)?
    private var pending: Route?
    func open(_ route: Route) {
        if let handler { handler(route) } else { pending = route }
    }
    func attach(_ handler: @escaping (Route) -> Void) {
        self.handler = handler
        if let pending { self.pending = nil; handler(pending) }
    }
    static func route(_ url: URL) -> Route? {
        guard ["atlas", "noodle"].contains(url.scheme) else { return nil }
        let id = url.pathComponents.dropFirst().first
        switch url.host {
        case "today": return .today
        case "everything": return .everything
        case "talk": return .talk
        case "activity": return .activity
        case "inbox": return .inbox
        case "request": return id.map(Route.request)
        case "item": return id.map(Route.item)
        case "project": return id.map(Route.project)
        default: return nil
        }
    }
}
