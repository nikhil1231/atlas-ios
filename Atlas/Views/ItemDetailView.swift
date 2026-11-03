import SwiftUI

/// One item, with everything the dashboard's item sheet can do: plan it, flag it, snooze it, time a
/// reminder, file it in an area, add notes, log contact, tick, drop or delete it.
struct ItemDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let itemID: String
    @ObservedObject var store: PlatformStore
    @State private var title = ""
    @State private var note = ""
    @State private var description = ""
    @State private var due = Date()
    @State private var remind = Date().addingTimeInterval(3600)
    @State private var snoozeUntil = Date().addingTimeInterval(86400)
    @State private var confirmDelete = false
    @State private var editingDescription = false

    private var item: PlatformItem? { store.item(itemID) }
    private var busy: Bool { store.pending[itemID] != nil }

    var body: some View {
        Group {
            if let item { form(item) }
            else { ContentUnavailableView("Not found", systemImage: "questionmark.folder", description: Text("It may have been deleted. Pull to refresh.")) }
        }
        .scrollContentBackground(.hidden).background(Color.atlasBackground)
        .navigationTitle(item?.typeLabel ?? "Item").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .task { await store.loadDetail(itemID, api: model.api) }
        .onAppear { reset() }
        .onChange(of: item?.title) { _, _ in reset() }
        .confirmationDialog("Delete for good?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { run("items.delete", [:]); dismiss() }
        } message: { Text("Dropping keeps it in Atlas's history; deleting removes it, its calendar event and its reminder.") }
    }

    private func reset() {
        guard let item else { return }
        title = item.title
        description = item.description ?? ""
        if let date = item.dueDate.flatMap(parseDay) { due = date }
        if let date = item.remindAt.flatMap(parseISODate) { remind = date }
    }

    @ViewBuilder private func form(_ item: PlatformItem) -> some View {
        Form {
            Section {
                TextField("Title", text: $title, axis: .vertical).font(.system(.title2, design: .serif))
                if title.trimmingCharacters(in: .whitespacesAndNewlines) != item.title {
                    Button("Save title") { update(["title": title.trimmingCharacters(in: .whitespacesAndNewlines)]) }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.count > 120)
                }
                HStack(spacing: 10) {
                    badge(item.typeLabel)
                    if ["todo", "goal"].contains(item.type) { badge(item.category) }
                    if item.isDone { badge("Done") }
                    if item.isSnoozed { badge("Snoozed") }
                    if let stage = item.stage, ["fading", "someday"].contains(stage) { badge(stage.capitalized) }
                }
                if let why = item.mustWhy, item.must == true { Text("Must-do: \(why)").font(.caption).foregroundStyle(Theme.warning) }
                if editingDescription || !description.isEmpty {
                    TextField("Description", text: $description, axis: .vertical).font(.subheadline)
                    if description != (item.description ?? "") {
                        Button("Save description") { update(["description": description.isEmpty ? NSNull() : description]); editingDescription = false }
                    }
                } else if ["project", "todo", "idea"].contains(item.type) {
                    Button("Add a description") { editingDescription = true }
                }
            }
            if busy {
                Section {
                    HStack { ProgressView(); Text("Saving to Atlas…").font(.caption) }
                    if let id = store.pending[itemID], id != "Sending…" {
                        Button("View request") { dismiss(); model.selectedRequestID = id }.font(.caption)
                    }
                }
            }
            if let error = store.errors["Action"] { Section { Text(error).font(.caption).foregroundStyle(Theme.warning) } }

            if item.isActive { activeSections(item) }

            if item.type == "person" { personSection(item) }
            if item.type == "project" {
                Section("Project") {
                    Button { dismiss(); model.route(.project(item.id)) } label: { Label("Open the board", systemImage: "rectangle.split.3x1") }
                    if let repo = item.repo, let url = URL(string: repo) { Link(destination: url) { Label("Repository", systemImage: "chevron.left.forwardslash.chevron.right") } }
                    if let link = item.link, let url = URL(string: link) { Link(destination: url) { Label("Link", systemImage: "link") } }
                }
            }
            if let projectID = item.projectId, let project = store.item(projectID) {
                Section { Button { dismiss(); model.route(.project(projectID)) } label: { Label("In \(project.title)", systemImage: "hammer") } }
            }
            notesSection(item)
            Section {
                if item.isActive {
                    if item.type == "todo" { Button { update(["status": "done"]) } label: { Label("Mark done", systemImage: "checkmark.circle") } }
                    Button(role: .destructive) { update(["status": "dropped"]) } label: { Label("Drop", systemImage: "xmark.bin") }
                } else {
                    Button { update(["status": "active"]) } label: { Label("Reopen", systemImage: "arrow.uturn.backward") }
                }
                Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
            }
            Section {
                Link("Open in the Atlas dashboard", destination: AppConfiguration.backendURL.appendingPathComponent("i/\(item.id)"))
                    .font(.subheadline)
            }
        }
        .disabled(busy)
    }

    @ViewBuilder private func activeSections(_ item: PlatformItem) -> some View {
        Section("Focus") {
            Toggle(isOn: Binding(get: { item.pinned == true }, set: { update(["pinned": $0]) })) {
                Label("Pinned to Focus", systemImage: "pin")
            }
            if ["todo", "goal"].contains(item.type) {
                Toggle(isOn: Binding(get: { item.must == true }, set: { update(["must": $0]) })) {
                    Label("Must-do", systemImage: "exclamationmark.circle")
                }
            }
        }
        if ["todo", "goal", "person"].contains(item.type) {
            Section("Plan") {
                if let planned = item.planDay.flatMap(parseDay) {
                    LabeledContent("On", value: planned.formatted(.dateTime.weekday(.wide).day().month()))
                }
                HStack {
                    Button("Today") { update(["plan_day": store.day?.today ?? dayString()]) }
                    Button("Tomorrow") { update(["plan_day": dayString(parseDay(store.day?.today ?? "") ?? Date(), offset: 1)]) }
                    if item.planDay != nil { Button("Clear") { update(["plan_day": NSNull()]) } }
                }.buttonStyle(.bordered)
            }
        }
        if item.type == "todo" {
            Section("Deadline and reminder") {
                if item.dueDate != nil {
                    DatePicker("Due", selection: $due, displayedComponents: .date)
                    HStack {
                        if dayString(due) != item.dueDate { Button("Save date") { update(["due_date": dayString(due)]) } }
                        Spacer()
                        Button("No deadline", role: .destructive) { update(["due_date": NSNull()]) }
                    }.buttonStyle(.borderless)
                } else {
                    Button { update(["due_date": dayString(offset: 7)]) } label: { Label("Add a deadline", systemImage: "calendar.badge.clock") }
                }
                if item.remindAt != nil {
                    DatePicker("Remind me", selection: $remind)
                    HStack {
                        if item.remindAt.flatMap(parseISODate) != remind {
                            Button("Move reminder") { update(["remind_at": ISO8601DateFormatter().string(from: remind)]) }
                        }
                        Spacer()
                        Button("No reminder", role: .destructive) { update(["remind_at": NSNull()]) }
                    }.buttonStyle(.borderless)
                } else {
                    DatePicker("Remind me at", selection: $remind, in: Date()...)
                    Button { update(["remind_at": ISO8601DateFormatter().string(from: remind)]) } label: { Label("Set reminder", systemImage: "bell") }
                }
                if model.reminders.enabled {
                    Text("The alert goes on your \(model.reminders.selectedList?.title ?? "Atlas") list in Reminders.").font(.caption).foregroundStyle(Theme.secondary)
                }
            }
        }
        if ["todo", "goal"].contains(item.type) {
            Section("Area") {
                Picker("Area", selection: Binding(get: { item.area ?? "" }, set: { update(["area": $0.isEmpty ? NSNull() : $0]) })) {
                    Text("None").tag("")
                    ForEach(PlatformItem.areas, id: \.0) { Text($0.1).tag($0.0) }
                }
            }
        }
        Section("Snooze") {
            if item.isSnoozed {
                if let until = item.snoozedUntil {
                    let end = until.count == 10 ? parseDay(until) : parseISODate(until)
                    if let end { LabeledContent("Until", value: end.formatted(date: .abbreviated, time: until.count == 10 ? .omitted : .shortened)) }
                }
                Button { run("items.touch", [:]) } label: { Label("Wake it up now", systemImage: "sun.max") }
            } else {
                ForEach(Snooze.options(), id: \.0) { option in Button(option.0) { update(["snoozed_until": option.1]) } }
                DatePicker("Until", selection: $snoozeUntil, in: Date()...)
                Button("Snooze until then") { update(["snoozed_until": ISO8601DateFormatter().string(from: snoozeUntil)]) }
            }
            if ["fading", "someday"].contains(item.stage ?? "") {
                Button { run("items.touch", [:]) } label: { Label("Bring it back to fresh", systemImage: "arrow.counterclockwise") }
            }
        }
        if ["todo", "inbox", "goal", "habit", "person"].contains(item.type) {
            Section("Kind") {
                Picker("Kind", selection: Binding(get: { item.type }, set: { update(["type": $0]) })) {
                    ForEach([("todo", "To-do"), ("goal", "Goal"), ("habit", "Habit"), ("person", "Person"), ("inbox", "Inbox")], id: \.0) { Text($0.1).tag($0.0) }
                }
            }
        }
    }

    private func personSection(_ item: PlatformItem) -> some View {
        Section("Keeping in touch") {
            if let days = item.daysSinceContact { LabeledContent("Last seen", value: days < 1 ? "Today" : "\(Int(days)) days ago") }
            else if let last = item.lastContactAt.flatMap(parseISODate) { LabeledContent("Last seen", value: last.formatted(date: .abbreviated, time: .omitted)) }
            else { LabeledContent("Last seen", value: "Not yet") }
            Stepper("Every \(item.cadenceDays ?? 30) days", value: Binding(get: { item.cadenceDays ?? 30 }, set: { update(["cadence_days": $0]) }), in: 1...365, step: 7)
            TextField("How it went (optional)", text: $note)
            Button { run("items.contact", ["text": note]); note = "" } label: { Label("Saw them today", systemImage: "person.wave.2") }
        }
    }

    private func notesSection(_ item: PlatformItem) -> some View {
        Section {
            ForEach(Array((item.notes ?? []).reversed().enumerated()), id: \.offset) { _, note in
                VStack(alignment: .leading, spacing: 4) {
                    Text(note.text).font(.subheadline).textSelection(.enabled)
                    if let at = note.at.flatMap(parseISODate) { Text(at, style: .relative).font(.caption2).foregroundStyle(Theme.secondary) }
                }
            }
            if item.type != "person" {
                HStack {
                    TextField("Add a note", text: $note, axis: .vertical)
                    Button("Add") { run("items.note", ["text": note]); note = "" }
                        .disabled(note.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        } header: {
            Text("Notes" + ((item.noteCount ?? item.notes?.count ?? 0) > 0 ? " · \(item.noteCount ?? item.notes?.count ?? 0)" : ""))
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text).font(.caption).padding(.horizontal, 8).padding(.vertical, 3)
            .background(Theme.accent.opacity(0.15), in: Capsule()).foregroundStyle(Theme.ink)
    }
    private func update(_ fields: [String: Any]) { run("items.update", fields) }
    private func run(_ handler: String, _ input: [String: Any]) {
        Task {
            await model.perform(handler, input: input.merging(["item_id": itemID]) { a, _ in a }, key: itemID)
            await store.loadDetail(itemID, api: model.api)
        }
    }
}

/// A project's board, as on the dashboard: Ideas, To do, Doing, Blocked, Done.
struct ProjectDetailView: View {
    @EnvironmentObject private var model: AppModel
    let projectID: String
    @ObservedObject var store: PlatformStore
    @State private var column = "todo"
    @State private var adding = false
    private var project: ProjectView? { store.projects[projectID] }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if let project {
                    header(project)
                    columnPicker(project)
                    board(project)
                    notes(project)
                } else if let error = store.errors["Project"] {
                    Text(error).font(.caption).foregroundStyle(Theme.warning)
                } else {
                    ProgressView()
                }
            }.padding(24)
        }
        .background(Color.atlasBackground)
        .navigationTitle("Project").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add a card").disabled(column == "done")
            }
        }
        .refreshable { await store.loadProject(projectID, api: model.api) }
        .task(id: store.updatedAt) { await store.loadProject(projectID, api: model.api) }
        .sheet(isPresented: $adding) {
            NewItemSheet(store: store, type: column == "ideas" ? "idea" : "todo", projectID: projectID, column: column)
        }
    }

    private func header(_ project: ProjectView) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(project.title).font(.system(.largeTitle, design: .serif).weight(.medium))
            if let description = project.description, !description.isEmpty {
                Text(description).font(.subheadline).foregroundStyle(Theme.secondary)
            }
            HStack(spacing: 16) {
                if let repo = project.repo, let url = URL(string: repo) { Link("Repository", destination: url) }
                if let link = project.link, let url = URL(string: link) { Link("Link", destination: url) }
                Button("Details") { model.openItemID = projectID }
            }.font(.caption)
        }
    }
    private func columnPicker(_ project: ProjectView) -> some View {
        Picker("Column", selection: $column) {
            ForEach(ProjectView.columns, id: \.0) { option in
                Text(label(option, project)).tag(option.0)
            }
        }.pickerStyle(.segmented)
    }
    private func label(_ option: (String, String), _ project: ProjectView) -> String {
        let count = cards(option.0, in: project).count
        return count > 0 ? "\(option.1) \(count)" : option.1
    }
    private func board(_ project: ProjectView) -> some View {
        let visible = cards(column, in: project)
        let empty = column == "ideas" ? "No ideas yet. Say “idea for \(project.title): …”." : "Nothing here."
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(visible) { card in cardRow(card) }
            if visible.isEmpty { EmptyLine(text: empty) }
        }
    }
    private func cardRow(_ card: PlatformItem) -> some View {
        HStack {
            ItemRow(item: card, subtitle: card.blockedReason, store: store)
            Menu {
                ForEach(ProjectView.columns.filter { $0.0 != column }, id: \.0) { target in
                    Button("Move to \(target.1)") { move(card, to: target.0) }
                }
            } label: { Image(systemName: "arrow.left.arrow.right").padding(8) }
                .disabled(store.pending[card.id] != nil)
        }
    }
    @ViewBuilder private func notes(_ project: ProjectView) -> some View {
        if !project.notes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeading(title: "Notes", count: project.notes.count)
                ForEach(Array(project.notes.reversed().prefix(10).enumerated()), id: \.offset) { _, note in
                    Text(note.text).font(.subheadline).padding(.vertical, 6).hairline()
                }
            }
        }
    }

    private func cards(_ column: String, in project: ProjectView) -> [PlatformItem] {
        if column == "done" { return project.done }
        if column == "ideas" { return project.ideas }
        return project.cards.filter { $0.isActive && $0.type == "todo" && ($0.boardColumn ?? "todo") == column }
    }
    private func move(_ card: PlatformItem, to target: String) {
        Task {
            await model.perform("items.update", input: ["item_id": card.id, "board_column": target], key: card.id)
            await store.loadProject(projectID, api: model.api)
        }
    }
}
