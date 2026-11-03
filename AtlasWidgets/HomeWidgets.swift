import AppIntents
import SwiftUI
import WidgetKit

private enum Palette {
    static let paper = Color(light: 0xf8f7f3, dark: 0x1a1916)
    static let ink = Color(light: 0x2a2925, dark: 0xe8e4db)
    static let accent = Color(light: 0x9d7a4a, dark: 0xc9a36f)
    static let secondary = Color(light: 0x8a857b, dark: 0x8f8a80)
    static let warning = Color(light: 0xa8432c, dark: 0xe0745a)
}

private extension Color {
    init(light: UInt32, dark: UInt32) {
        self = Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
}

struct AtlasEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    var stale: Bool { date.timeIntervalSince(snapshot.updatedAt) > 3 * 3600 }
}

/// Reads Atlas directly (the widget has the shared credentials), falling back to what the app last saved.
struct AtlasProvider: TimelineProvider {
    func placeholder(in context: Context) -> AtlasEntry { AtlasEntry(date: Date(), snapshot: .placeholder) }

    func getSnapshot(in context: Context, completion: @escaping (AtlasEntry) -> Void) {
        completion(AtlasEntry(date: Date(), snapshot: context.isPreview ? .placeholder : SnapshotStore.load() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AtlasEntry>) -> Void) {
        Task {
            let snapshot = await Self.fresh() ?? SnapshotStore.load() ?? WidgetSnapshot(updatedAt: .distantPast, day: dayString(), connected: false)
            let now = Date()
            // A new entry as each timed thing starts, so "next" moves on without a network refresh.
            let starts = snapshot.agenda.compactMap(\.at).filter { $0 > now }.prefix(6)
            let entries = [AtlasEntry(date: now, snapshot: snapshot)] + starts.map { AtlasEntry(date: $0.addingTimeInterval(60), snapshot: snapshot) }
            let midnight = Calendar.current.startOfDay(for: now.addingTimeInterval(86400))
            completion(Timeline(entries: entries, policy: .after(min(now.addingTimeInterval(30 * 60), midnight))))
        }
    }

    static func fresh() async -> WidgetSnapshot? {
        guard let client = try? AtlasClient.load() else { return nil }
        async let todayRead = client.read("items", query: ["scope": "today"])
        async let dashboardRead = client.read("dashboard")
        guard let data = try? await todayRead.data, let day = try? data.decode(PlatformDay.self) else { return nil }
        let dashboard = (try? await dashboardRead)?.data.flatMap { try? $0.decode(Dashboard.self) }
        let snapshot = WidgetSnapshot.build(day: day, dashboard: dashboard)
        SnapshotStore.save(snapshot)
        return snapshot
    }
}

private struct TaskLine: View {
    let task: WidgetSnapshot.Task
    var interactive = true
    var body: some View {
        HStack(spacing: 8) {
            if interactive && !task.done {
                Button(intent: CompleteTaskIntent(itemID: task.id, title: task.title)) {
                    Image(systemName: "circle").foregroundStyle(task.must ? Palette.warning : Palette.accent)
                }.buttonStyle(.plain)
            } else {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle").foregroundStyle(Palette.accent)
            }
            Text(task.title).font(.caption).lineLimit(1).strikethrough(task.done)
                .foregroundStyle(task.done ? Palette.secondary : task.overdue ? Palette.warning : Palette.ink)
            Spacer(minLength: 0)
        }
    }
}

private struct AgendaLine: View {
    let entry: WidgetSnapshot.Entry
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Group {
                if entry.allDay { Text("All day") } else if let at = entry.at { Text(at, style: .time) }
            }.font(.caption2.monospacedDigit()).foregroundStyle(Palette.accent).frame(width: 44, alignment: .leading)
            Text(entry.title).font(.caption).lineLimit(1).foregroundStyle(Palette.ink)
        }
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AtlasEntry
    private var s: WidgetSnapshot { entry.snapshot }

    var body: some View {
        content.widgetURL(URL(string: "atlas://today"))
            .containerBackground(for: .widget) { Palette.paper }
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryInline:
            if let next = s.nextEntry, let at = next.at { Text("\(at, style: .time) \(next.title)") }
            else { Text("\(s.openTasks.count) to do today") }
        case .accessoryCircular:
            Gauge(value: Double(s.tasks.count - s.openTasks.count), in: 0...Double(max(s.tasks.count, 1))) {
                Image(systemName: "checklist")
            } currentValueLabel: { Text("\(s.openTasks.count)") }
                .gaugeStyle(.accessoryCircularCapacity)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                if let next = s.nextEntry, let at = next.at {
                    Text(at, style: .time).font(.caption.bold())
                    Text(next.title).font(.caption).lineLimit(1)
                } else { Text("Today").font(.caption.bold()) }
                Text(s.openTasks.first?.title ?? "Nothing left to do").font(.caption2).lineLimit(1)
                if s.openTasks.count > 1 { Text("+\(s.openTasks.count - 1) more").font(.caption2).foregroundStyle(.secondary) }
            }
        case .systemSmall:
            VStack(alignment: .leading, spacing: 6) {
                header
                if let next = s.nextEntry { AgendaLine(entry: next) }
                Spacer(minLength: 0)
                Text("\(s.openTasks.count)").font(.system(.largeTitle, design: .serif)).foregroundStyle(Palette.ink)
                Text(s.openTasks.count == 1 ? "thing to do" : "things to do").font(.caption2).foregroundStyle(Palette.secondary)
                if s.overdueCount > 0 { Text("\(s.overdueCount) overdue").font(.caption2.bold()).foregroundStyle(Palette.warning) }
            }
        case .systemMedium:
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    header
                    ForEach(s.agenda.prefix(3), id: \.self) { AgendaLine(entry: $0) }
                    if s.agenda.isEmpty { Text("Nothing timed").font(.caption).foregroundStyle(Palette.secondary) }
                    Spacer(minLength: 0)
                    footer
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(s.openTasks.prefix(4)) { TaskLine(task: $0) }
                    if s.openTasks.isEmpty { Text("All done").font(.caption).foregroundStyle(Palette.secondary) }
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                header
                ForEach(s.agenda.prefix(4), id: \.self) { AgendaLine(entry: $0) }
                Divider()
                ForEach(s.tasks.prefix(7)) { TaskLine(task: $0) }
                if s.tasks.isEmpty { Text("Nothing planned").font(.caption).foregroundStyle(Palette.secondary) }
                Spacer(minLength: 0)
                footer
            }
        }
    }

    private var header: some View {
        HStack {
            Text(parseDay(s.day).map { $0.formatted(.dateTime.weekday(.abbreviated).day()) } ?? "Today")
                .font(.system(.subheadline, design: .serif).weight(.semibold)).foregroundStyle(Palette.ink)
            Spacer(minLength: 0)
            if s.waitingCount > 0 { Image(systemName: "questionmark.bubble.fill").font(.caption).foregroundStyle(Palette.accent) }
        }
    }
    @ViewBuilder private var footer: some View {
        if entry.stale || !s.connected {
            Text(s.updatedAt == .distantPast ? "Open Atlas to connect" : "Updated \(s.updatedAt, style: .relative) ago")
                .font(.caption2).foregroundStyle(Palette.secondary)
        } else if s.overdueCount > 0 {
            Text("\(s.overdueCount) overdue").font(.caption2.bold()).foregroundStyle(Palette.warning)
        }
    }
}

struct FocusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AtlasEntry
    var body: some View {
        let focus = entry.snapshot.focus
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Focus").font(.system(.subheadline, design: .serif).weight(.semibold)).foregroundStyle(Palette.ink)
                Spacer()
                Image(systemName: "pin.fill").font(.caption2).foregroundStyle(Palette.accent)
            }
            ForEach(focus.prefix(family == .systemLarge ? 10 : 4)) { TaskLine(task: $0) }
            if focus.isEmpty { Text("Pin things or mark must-dos and they land here.").font(.caption).foregroundStyle(Palette.secondary) }
            Spacer(minLength: 0)
        }
        .widgetURL(URL(string: "atlas://today"))
        .containerBackground(for: .widget) { Palette.paper }
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.today, provider: AtlasProvider()) { TodayWidgetView(entry: $0) }
            .configurationDisplayName("Today")
            .description("What’s timed, what’s on your list, and what’s overdue. Tick to-dos off right here.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct FocusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.focus, provider: AtlasProvider()) { FocusWidgetView(entry: $0) }
            .configurationDisplayName("Focus")
            .description("Your pinned items and must-dos.")
            .supportedFamilies([.systemMedium, .systemLarge])
    }
}

@available(iOS 18.0, *)
struct TalkControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "AtlasTalk") {
            ControlWidgetButton(action: OpenURLIntent(URL(string: "atlas://talk")!)) {
                Label("Talk to Atlas", systemImage: "waveform")
            }
        }
        .displayName("Talk to Atlas")
        .description("Start a voice conversation with Atlas.")
    }
}
