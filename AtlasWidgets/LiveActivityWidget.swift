import ActivityKit
import SwiftUI
import WidgetKit

@main
struct AtlasWidgetsBundle: WidgetBundle {
    var body: some Widget {
        AtlasLiveActivity()
        TodayWidget()
        FocusWidget()
        if #available(iOS 18.0, *) { TalkControl() }
    }
}

struct AtlasLiveActivity: Widget {
    private let accent = Color(red: 0.788, green: 0.639, blue: 0.435)
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AtlasActivityAttributes.self) { context in
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: context.state.status == "awaiting_answer" ? "questionmark.bubble.fill" : "waveform")
                    .font(.title2).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 5) {
                    Text("atlas · \(label(context.state.phase ?? context.state.status))").font(.caption.bold()).foregroundStyle(.secondary)
                    Text(context.state.title).font(.system(.headline, design: .serif)).lineLimit(2)
                    Text(context.state.summary).font(.caption).lineLimit(2)
                    if context.state.status == "queued", let date = scheduledDate(context.state.executeAt), date > Date() {
                        HStack { Text("Starts in"); Text(timerInterval: Date()...date, countsDown: true).monospacedDigit() }
                            .font(.caption).foregroundStyle(accent)
                    }
                    if context.state.status == "awaiting_answer" {
                        Label("Tap to answer by voice", systemImage: "mic.fill").font(.caption.bold()).foregroundStyle(accent)
                    }
                }
                Spacer(minLength: 0)
            }.padding(16).activityBackgroundTint(Color(red: 0.102, green: 0.098, blue: 0.086))
                .activitySystemActionForegroundColor(accent)
                .widgetURL(link(context.attributes.requestID))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Label("atlas", systemImage: "waveform").font(.headline).foregroundStyle(accent) }
                DynamicIslandExpandedRegion(.trailing) { Text(label(context.state.phase ?? context.state.status)).font(.caption).foregroundStyle(.secondary) }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(context.state.title).font(.system(.headline, design: .serif)).lineLimit(2)
                        Text(context.state.status == "awaiting_answer" ? "Tap to answer by voice" : context.state.summary)
                            .font(.caption).lineLimit(2).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: context.state.status == "awaiting_answer" ? "questionmark.bubble.fill" : "waveform").foregroundStyle(accent)
            } compactTrailing: {
                Image(systemName: context.state.status == "awaiting_answer" ? "mic.fill" : "ellipsis").foregroundStyle(accent)
            } minimal: {
                Image(systemName: "waveform").foregroundStyle(accent)
            }
            .widgetURL(link(context.attributes.requestID)).keylineTint(accent)
        }
    }
    private func scheduledDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
    private func link(_ id: String) -> URL? { URL(string: "atlas://request/\(id)") }
    private func label(_ status: String) -> String {
        switch status {
        case "awaiting_answer": "Needs you"
        case "accepted": "Accepted"
        case "resolving": "Planning"
        case "scheduled": "Scheduled"
        case "executing": "Working"
        case "partial": "Partly completed"
        case "queued": "Pending"
        case "running": "Working"
        case "completed", "answered": "Done"
        case "cancelled": "Cancelled"
        default: "Needs attention"
        }
    }
}
