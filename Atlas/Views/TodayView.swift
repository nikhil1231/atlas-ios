import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var store: PlatformStore
    @State private var search = ""
    @State private var newTask = ""
    @State private var showTomorrow = false
    @FocusState private var adding: Bool

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(dayTitle).font(.system(.largeTitle, design: .serif).weight(.medium))
                    Text(subtitle).font(.subheadline).foregroundStyle(Theme.secondary)
                }
                if !model.credentials.isConfigured && !model.loadingCredentials {
                    ConnectPrompt()
                } else {
                    StatusBlock(store: store)
                    content
                }
            }.padding(24).frame(maxWidth: 700).frame(maxWidth: .infinity)
        }
        .background(Color.atlasBackground)
        .navigationTitle("Atlas").navigationBarTitleDisplayMode(.inline)
        .toolbar { SettingsButton() }
        .refreshable { await model.refresh() }
        .searchable(text: $search, prompt: "Search your day")
    }

    private var dayTitle: String {
        guard let day = store.day, let date = parseDay(day.date) else { return "Today" }
        return "Today · " + date.formatted(.dateTime.day().month(.abbreviated))
    }
    private var subtitle: String {
        guard let day = store.day else { return "A little room for what matters." }
        let open = day.tasks.filter { !$0.isDone }.count
        let done = day.tasks.filter(\.isDone).count
        if open == 0 && done > 0 { return "All \(done) done. Nicely handled." }
        if open == 0 { return "Nothing planned yet. A little room for what matters." }
        return "\(open) to go" + (done > 0 ? ", \(done) done" : "") + (day.overdue.isEmpty ? "." : " · \(day.overdue.count) overdue.")
    }
    private func matches(_ title: String) -> Bool { search.isEmpty || title.localizedCaseInsensitiveContains(search) }

    @ViewBuilder private var content: some View {
        if let ends = store.day?.dayEnds.flatMap(parseISODate), ends > Date() {
            Text("Still on yesterday’s day. Atlas rolls over at \(ends, style: .time).")
                .font(.caption).foregroundStyle(Theme.accent)
        }
        if let waiting = store.dashboard?.waiting, !waiting.isEmpty {
            ForEach(waiting) { WaitingCard(waiting: $0, store: store) }
        }
        addField
        if let focus = store.dashboard?.focus.filter({ $0.isActive && matches($0.title) }), !focus.isEmpty {
            section("Focus", items: focus)
        }
        if let day = store.day {
            if !day.overdue.isEmpty { section("Overdue", items: day.overdue) }
            agenda(day)
            section("On your list", items: day.tasks, empty: "Nothing planned. Add something above, or plan from Everything.")
            if !day.leftovers.isEmpty { leftovers(day.leftovers) }
            if let tomorrow = day.tomorrow, !(tomorrow.tasks.isEmpty && tomorrow.timed.isEmpty) { tomorrowSection(tomorrow) }
        } else if !store.loading && store.errors["Today"] == nil {
            EmptyLine(text: "Pull to refresh your day.")
        }
    }

    private var addField: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus").foregroundStyle(Theme.accent)
            TextField("Add to today", text: $newTask).focused($adding).submitLabel(.done)
                .onSubmit(add)
            if store.pending["new-today"] != nil { ProgressView() }
            else if !newTask.isEmpty { Button("Add", action: add).font(.subheadline.bold()) }
        }
        .padding(.vertical, 12).padding(.horizontal, 14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
    }
    private func add() {
        let title = newTask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 120 else { return }
        let day = store.day?.date ?? dayString()
        Task {
            await model.perform("items.create", input: ["type": "todo", "title": title, "plan_day": day], key: "new-today")
            if store.errors["Action"] == nil { newTask = "" }
        }
    }

    private func section(_ title: String, items: [PlatformItem], empty: String = "") -> some View {
        let visible = items.filter { matches($0.title) }
        return VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title: title, count: visible.count)
            ForEach(visible) { ItemRow(item: $0, store: store) }
            if visible.isEmpty && !empty.isEmpty { EmptyLine(text: empty) }
        }
    }

    private func agenda(_ day: PlatformDay) -> some View {
        let feeds = (store.dashboard?.upcoming ?? []).filter {
            $0.source != nil && String($0.at.prefix(10)) == day.date && matches($0.title)
        }
        let calendar = calendarToday(day).filter { matches($0.summary ?? "") }
        let timed = day.timed.filter { matches($0.title) }
        return VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title: "Your day", count: timed.count + calendar.count + feeds.count)
            ForEach(timed) { entry in
                if let item = entry.item { ItemRow(item: item, subtitle: entry.allDay ? "All day" : parseISODate(entry.at).map { $0.formatted(date: .omitted, time: .shortened) }, store: store) }
                else { AppointmentRow(title: entry.title, at: entry.at, allDay: entry.allDay, kind: entry.kind, source: entry.source) }
            }
            ForEach(calendar) { event in
                AppointmentRow(title: event.summary ?? "Untitled event", at: event.start.dateTime ?? event.start.date ?? "", allDay: event.start.dateTime == nil)
            }
            ForEach(feeds) { AppointmentRow(title: $0.title, at: $0.at, allDay: $0.allDay, kind: $0.kind, source: $0.source) }
            if timed.isEmpty && calendar.isEmpty && feeds.isEmpty { EmptyLine(text: "No events, reminders or deliveries.") }
        }
    }

    private func calendarToday(_ day: PlatformDay) -> [CalendarEntry] {
        let localDay: (String) -> String = { value in
            guard let date = parseISODate(value) else { return value }
            if let ends = day.dayEnds.flatMap(parseISODate), date < ends, String(value.prefix(10)) > day.date { return day.date }
            return dayString(date)
        }
        return store.calendar.filter { event in
            let date = event.start.date ?? localDay(event.start.dateTime ?? "")
            return date == day.date && !day.timed.contains { $0.kind == "event" && $0.title == event.summary && $0.at == (event.start.dateTime ?? event.start.date) }
        }.sorted { ($0.start.dateTime ?? $0.start.date ?? "") < ($1.start.dateTime ?? $1.start.date ?? "") }
    }

    private func leftovers(_ items: [PlatformItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title: "From yesterday", count: items.count)
            Text("Carry them over, or let them go.").font(.caption).foregroundStyle(Theme.secondary).padding(.bottom, 4)
            ForEach(items.filter { matches($0.title) }) { item in
                HStack {
                    ItemRow(item: item, store: store)
                    Button("Today") { plan(item, store.day?.date) }.font(.caption.bold()).buttonStyle(.bordered)
                    Button { plan(item, nil) } label: { Image(systemName: "xmark") }.font(.caption).buttonStyle(.bordered)
                        .accessibilityLabel("Let \(item.title) go")
                }
            }
            if items.count > 1 {
                Button("Carry all over") { items.forEach { plan($0, store.day?.date) } }.font(.caption).padding(.top, 8)
            }
        }
    }
    private func plan(_ item: PlatformItem, _ day: String?) {
        Task { await model.perform("items.update", input: ["item_id": item.id, "plan_day": day ?? NSNull()], key: item.id) }
    }

    private func tomorrowSection(_ tomorrow: DayPlan) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation { showTomorrow.toggle() } } label: {
                HStack {
                    SectionHeading(title: "Tomorrow", count: tomorrow.tasks.count + tomorrow.timed.count)
                    Image(systemName: showTomorrow ? "chevron.up" : "chevron.down").font(.caption).foregroundStyle(Theme.secondary)
                }
            }.buttonStyle(.plain)
            if showTomorrow {
                ForEach(tomorrow.timed) { entry in
                    AppointmentRow(title: entry.title, at: entry.at, allDay: entry.allDay, kind: entry.kind, source: entry.source)
                }
                ForEach(tomorrow.tasks) { ItemRow(item: $0, store: store) }
            }
        }
    }
}

struct ConnectPrompt: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        ContentUnavailableView {
            Label("Your Atlas, together", systemImage: "square.stack.3d.up")
        } description: {
            Text("Connect to see your tasks, plans, projects and people.")
        } actions: {
            Button("Connect Atlas") { model.showSettings = true }.buttonStyle(.borderedProminent)
        }
    }
}

struct SettingsButton: ToolbarContent {
    @EnvironmentObject private var model: AppModel
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { model.showSettings = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Settings")
        }
    }
}
