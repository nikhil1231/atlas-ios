import SwiftUI

struct EverythingView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var store: PlatformStore
    @State private var search = ""
    @AppStorage("everythingTab") private var tab = "todo"
    @State private var area = "all"
    @State private var showDone = false
    @State private var showSomeday = false
    @State private var adding = false
    @State private var undoing: CaptureRecord?
    private let tabs = [("todo", "To-dos"), ("person", "People"), ("project", "Projects"), ("goal", "Goals"),
                        ("habit", "Habits"), ("inbox", "Inbox"), ("captures", "Captured")]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Everything").font(.system(.largeTitle, design: .serif).weight(.medium))
                    Text("All the threads of your life, in one place.").font(.subheadline).foregroundStyle(Theme.secondary)
                }
                if !model.credentials.isConfigured && !model.loadingCredentials {
                    ConnectPrompt()
                } else {
                    StatusBlock(store: store)
                    tabBar
                    if search.isEmpty { content } else { results }
                }
            }.padding(24).frame(maxWidth: 700).frame(maxWidth: .infinity)
        }
        .background(Color.atlasBackground)
        .navigationTitle("Atlas").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add")
            }
            SettingsButton()
        }
        .refreshable { await model.refresh() }
        .searchable(text: $search, prompt: "Search everything, including notes")
        .sheet(isPresented: $adding) { NewItemSheet(store: store, type: ["todo", "person", "project", "goal", "habit"].contains(tab) ? tab : "todo") }
        .navigationDestination(item: $model.openProjectID) { ProjectDetailView(projectID: $0, store: store) }
        .confirmationDialog("Undo this capture?", isPresented: Binding(get: { undoing != nil }, set: { if !$0 { undoing = nil } }), presenting: undoing) { capture in
            Button("Undo everything it did", role: .destructive) {
                Task { await model.perform("captures.undo", input: ["capture_id": capture.id], key: capture.id) }
            }
        } message: { capture in Text(capture.summary ?? capture.rawText) }
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                ForEach(tabs, id: \.0) { kind in
                    Button { tab = kind.0 } label: {
                        HStack(spacing: 4) {
                            Text(kind.1)
                            if let badge = badge(kind.0), badge > 0 {
                                Text("\(badge)").font(.caption2.bold()).padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(Theme.accent.opacity(0.2), in: Capsule())
                            }
                        }
                        .font(.subheadline).foregroundStyle(tab == kind.0 ? Theme.ink : Theme.secondary)
                        .padding(.vertical, 9)
                        .overlay(alignment: .bottom) { Rectangle().fill(tab == kind.0 ? Theme.ink : .clear).frame(height: 1) }
                    }.buttonStyle(.plain)
                }
            }
        }
    }
    private func badge(_ kind: String) -> Int? {
        switch kind {
        case "inbox": (store.dashboard?.inbox.count ?? 0) + (store.dashboard?.refile.count ?? 0)
        case "person": store.dashboard?.people.filter { ($0.overdueDays ?? 0) > 0 }.count
        default: nil
        }
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case "person": people
        case "project": projects
        case "inbox": inbox
        case "captures": captures
        default: list(tab)
        }
    }

    // ---- search ----
    private var results: some View {
        let words = search.lowercased().split(separator: " ")
        let hits = store.items.filter { item in
            let hay = ([item.title, item.description ?? ""] + (item.notes ?? []).map(\.text)).joined(separator: " ").lowercased()
            return words.allSatisfy { hay.contains($0) }
        }.sorted { ($0.isActive ? 0 : 1, $0.title) < ($1.isActive ? 0 : 1, $1.title) }
        return VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title: "Results", count: hits.count)
            ForEach(hits.prefix(100)) { ItemRow(item: $0, store: store) }
            if hits.isEmpty { EmptyLine(text: "Nothing matches.") }
        }
    }

    // ---- to-dos, goals, habits ----
    private func list(_ type: String) -> some View {
        // Project tasks live on their project's board, as on the dashboard.
        let all = store.items.filter { $0.type == type && $0.projectId == nil }
            .filter { showDone ? $0.isDone : $0.status == "active" }
            .filter { area == "all" || $0.area == area }
            .sorted(by: Self.order)
        let someday = all.filter { $0.stage == "someday" && !showDone }
        let live = all.filter { !someday.contains($0) }
        let grouped = type == "todo" && area == "all" && !showDone
        return VStack(alignment: .leading, spacing: 20) {
            HStack {
                if type != "habit" {
                    Menu {
                        Button("All areas") { area = "all" }
                        ForEach(PlatformItem.areas, id: \.0) { category in Button(category.1) { area = category.0 } }
                    } label: { Label(PlatformItem.areas.first { $0.0 == area }?.1 ?? "All areas", systemImage: "line.3.horizontal.decrease") }
                }
                Spacer()
                Toggle("Done", isOn: $showDone).toggleStyle(.button)
            }.font(.caption)
            if grouped {
                ForEach(PlatformItem.areas + [("", "Other")], id: \.0) { category in
                    let items = live.filter { ($0.area ?? "") == category.0 || (category.0 == "" && !PlatformItem.areas.map(\.0).contains($0.area ?? "")) }
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            SectionHeading(title: category.1, count: items.count)
                            ForEach(items) { ItemRow(item: $0, store: store) }
                        }
                    }
                }
                if live.isEmpty { EmptyLine(text: "Nothing to do. Tell Atlas what’s on your mind.") }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeading(title: tabs.first { $0.0 == type }?.1 ?? "", count: live.count)
                    ForEach(live) { ItemRow(item: $0, store: store) }
                    if live.isEmpty { EmptyLine(text: showDone ? "Nothing finished yet." : "Nothing here yet. Tell Atlas what’s on your mind.") }
                }
            }
            if !someday.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Button { withAnimation { showSomeday.toggle() } } label: {
                        HStack {
                            SectionHeading(title: "Someday", count: someday.count)
                            Image(systemName: showSomeday ? "chevron.up" : "chevron.down").font(.caption).foregroundStyle(Theme.secondary)
                        }
                    }.buttonStyle(.plain)
                    Text("Untouched for six weeks. Mention one again and it comes back.").font(.caption).foregroundStyle(Theme.secondary)
                    if showSomeday { ForEach(someday) { ItemRow(item: $0, store: store) } }
                }
            }
        }
    }
    static func order(_ a: PlatformItem, _ b: PlatformItem) -> Bool {
        if a.isDone != b.isDone { return !a.isDone }
        if (a.must == true) != (b.must == true) { return a.must == true }
        if (a.overdue == true) != (b.overdue == true) { return a.overdue == true }
        return (a.dueDay ?? a.dueDate ?? "9999", a.title.localizedLowercase) < (b.dueDay ?? b.dueDate ?? "9999", b.title.localizedLowercase)
    }

    // ---- people ----
    private var people: some View {
        let people = store.dashboard?.people ?? store.items.filter { $0.type == "person" && $0.isActive }
        return VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title: "People", count: people.count)
            Text("Who you haven’t seen for a while comes first.").font(.caption).foregroundStyle(Theme.secondary).padding(.bottom, 4)
            ForEach(people) { person in
                HStack {
                    ItemRow(item: person, subtitle: contactLine(person), store: store)
                    Button { Task { await model.perform("items.contact", input: ["item_id": person.id, "text": ""], key: person.id) } } label: {
                        Image(systemName: "person.wave.2")
                    }.buttonStyle(.bordered).accessibilityLabel("Saw \(person.title) today").disabled(store.pending[person.id] != nil)
                }
            }
            if people.isEmpty { EmptyLine(text: "No one yet. Say “I haven't seen Sam in ages”.") }
        }
    }
    private func contactLine(_ p: PlatformItem) -> String {
        let cadence = p.cadenceDays.map { "every \($0)d" } ?? ""
        guard let days = p.daysSinceContact else { return "Not seen yet · \(cadence)" }
        let since = days < 1 ? "seen today" : "\(Int(days))d ago"
        let late = (p.overdueDays ?? 0) > 0 ? " · \(Int(p.overdueDays!))d overdue" : ""
        return "\(since)\(late) · \(cadence)"
    }

    // ---- projects ----
    private var projects: some View {
        let projects = store.dashboard?.projects ?? []
        return VStack(alignment: .leading, spacing: 12) {
            if let work = store.dashboard?.projectWork, !work.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeading(title: "In progress", count: work.count)
                    ForEach(work) { ItemRow(item: $0, store: store) }
                }
            }
            SectionHeading(title: "Projects", count: projects.count)
            ForEach(projects) { project in
                Button { model.openProjectID = project.id } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(project.title).font(.system(.headline, design: .serif))
                            Spacer()
                            if project.stage == "resting" { Text("Resting").font(.caption).foregroundStyle(Theme.secondary) }
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.secondary)
                        }
                        if let next = project.next { Text("Next: \(next)").font(.subheadline).foregroundStyle(Theme.ink).lineLimit(1) }
                        if let c = project.counts {
                            HStack(spacing: 12) {
                                Label("\(c.todos ?? 0)", systemImage: "checklist")
                                if (c.doing ?? 0) > 0 { Label("\(c.doing ?? 0) doing", systemImage: "hammer") }
                                if (c.blocked ?? 0) > 0 { Label("\(c.blocked ?? 0) blocked", systemImage: "hand.raised").foregroundStyle(Theme.warning) }
                                Label("\(c.ideas ?? 0)", systemImage: "lightbulb")
                            }.font(.caption).foregroundStyle(Theme.secondary)
                        }
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
                        .opacity(project.stage == "resting" ? 0.7 : 1)
                }.buttonStyle(.plain)
            }
            if projects.isEmpty { EmptyLine(text: "No projects yet. Say “new project: …”.") }
        }
    }

    // ---- inbox ----
    private var inbox: some View {
        let inbox = store.dashboard?.inbox ?? []
        let refile = store.dashboard?.refile ?? []
        return VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeading(title: "Inbox", count: inbox.count)
                ForEach(inbox) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        ItemRow(item: item, store: store)
                        if let kind = item.suggestedType {
                            HStack {
                                Text(kind == "drop" ? "Suggest dropping it" : "Looks like a \(PlatformItem.kinds.first { $0.0 == kind }?.1.lowercased() ?? kind)"
                                     + (item.suggestedTitle.map { ": “\($0)”" } ?? ""))
                                    .font(.caption).foregroundStyle(Theme.secondary)
                                Spacer()
                                Button("Accept") { Task { await model.perform("items.accept", input: ["item_id": item.id], key: item.id) } }
                                    .font(.caption.bold()).buttonStyle(.bordered)
                            }
                        }
                    }
                }
                if inbox.isEmpty { EmptyLine(text: "Inbox zero.") }
            }
            if !refile.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeading(title: "Belongs in a project?", count: refile.count)
                    ForEach(refile) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            ItemRow(item: item, subtitle: "→ \(item.suggestedProject ?? "a project")", store: store)
                            HStack {
                                Button("Move it") { Task { await model.perform("items.refile", input: ["item_id": item.id, "accept": true], key: item.id) } }
                                Button("Keep here") { Task { await model.perform("items.refile", input: ["item_id": item.id, "accept": false], key: item.id) } }
                            }.font(.caption.bold()).buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }

    // ---- captures ----
    private var captures: some View {
        let captures = store.dashboard?.captures ?? []
        return VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title: "Recently captured", count: captures.count)
            ForEach(captures) { capture in
                VStack(alignment: .leading, spacing: 6) {
                    Text(capture.rawText).font(.body)
                    if let summary = capture.summary { Text(summary).font(.caption).foregroundStyle(Theme.secondary) }
                    HStack {
                        if let date = parseISODate(capture.receivedAt) { Text(date, style: .relative).font(.caption2).foregroundStyle(Theme.secondary) }
                        Spacer()
                        if store.pending[capture.id] != nil { ProgressView() }
                        else { Button("Undo") { undoing = capture }.font(.caption.bold()) }
                    }
                }.padding(.vertical, 12).hairline()
            }
            if captures.isEmpty { EmptyLine(text: "Nothing captured lately.") }
        }
    }
}

struct NewItemSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: PlatformStore
    @State var type: String
    var projectID: String? = nil
    var column: String? = nil
    @State private var title = ""
    @State private var area = ""
    @State private var today = false
    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title, axis: .vertical).font(.system(.title3, design: .serif))
                if projectID == nil {
                    Picker("Kind", selection: $type) {
                        ForEach([("todo", "To-do"), ("person", "Person"), ("project", "Project"), ("goal", "Goal"), ("habit", "Habit")], id: \.0) { Text($0.1).tag($0.0) }
                    }
                    if type == "todo" || type == "goal" {
                        Picker("Area", selection: $area) {
                            Text("Let Atlas choose").tag("")
                            ForEach(PlatformItem.areas, id: \.0) { Text($0.1).tag($0.0) }
                        }
                    }
                    if type == "todo" { Toggle("Put it on today", isOn: $today) }
                }
                if let error = store.errors["Action"] { Text(error).font(.caption).foregroundStyle(Theme.warning) }
            }
            .navigationTitle(projectID == nil ? "Add to Atlas" : "New card").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.pending["new-item"] != nil ? "Adding…" : "Add") { add() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || title.count > 120 || store.pending["new-item"] != nil)
                }
            }
        }.presentationDetents([.medium])
    }
    private func add() {
        var input: [String: Any] = ["type": type, "title": title.trimmingCharacters(in: .whitespacesAndNewlines)]
        if !area.isEmpty { input["area"] = area }
        if today { input["plan_day"] = store.day?.date ?? dayString() }
        if let projectID { input["project_id"] = projectID; input["board_column"] = column ?? (type == "idea" ? "ideas" : "todo") }
        Task {
            await model.perform("items.create", input: input, key: "new-item")
            if store.errors["Action"] == nil { dismiss() }
        }
    }
}
