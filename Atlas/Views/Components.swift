import SwiftUI

struct SectionHeading: View {
    let title: String
    var count: Int? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(.title2, design: .serif))
            if let count { Text("\(count)").font(.caption).foregroundStyle(Theme.secondary) }
            Spacer(minLength: 0)
        }.padding(.bottom, 8)
    }
}

struct Hairline: ViewModifier {
    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 0.5) }
    }
}
extension View { func hairline() -> some View { modifier(Hairline()) } }

enum Snooze {
    static func options(now: Date = Date()) -> [(String, String)] {
        let iso = ISO8601DateFormatter()
        return [("1 hour", iso.string(from: now.addingTimeInterval(3600))),
                ("Tomorrow", dayString(now, offset: 1)),
                ("Next week", dayString(now, offset: 7)),
                ("Next month", dayString(now, offset: 30))]
    }
}

/// Quick actions on any item, from a long press. They're the same changes the item sheet makes.
struct ItemActions: View {
    @EnvironmentObject private var model: AppModel
    let item: PlatformItem
    var body: some View {
        let update: ([String: Any]) -> Void = { fields in
            Task { await model.perform("items.update", input: fields.merging(["item_id": item.id]) { a, _ in a }, key: item.id) }
        }
        if item.isActive {
            if item.type == "todo" { Button { update(["status": "done"]) } label: { Label("Done", systemImage: "checkmark.circle") } }
            Button { update(["pinned": !(item.pinned ?? false)]) } label: {
                Label(item.pinned == true ? "Unpin from Focus" : "Pin to Focus", systemImage: item.pinned == true ? "pin.slash" : "pin")
            }
            if ["todo", "goal"].contains(item.type) {
                Button { update(["must": !(item.must ?? false)]) } label: {
                    Label(item.must == true ? "Not a must-do" : "Must-do", systemImage: "exclamationmark.circle")
                }
            }
            if ["todo", "goal", "person"].contains(item.type) {
                Menu {
                    Button("Today") { update(["plan_day": model.platform.day?.today ?? dayString()]) }
                    Button("Tomorrow") { update(["plan_day": dayString(parseDay(model.platform.day?.today ?? "") ?? Date(), offset: 1)]) }
                    if item.planDay != nil { Button("Off the day") { update(["plan_day": NSNull()]) } }
                } label: { Label("Plan for…", systemImage: "calendar") }
            }
            Menu {
                ForEach(Snooze.options(), id: \.0) { option in Button(option.0) { update(["snoozed_until": option.1]) } }
            } label: { Label("Snooze", systemImage: "moon.zzz") }
            if item.type == "person" {
                Button { Task { await model.perform("items.contact", input: ["item_id": item.id, "text": ""], key: item.id) } } label: {
                    Label("Saw them today", systemImage: "person.wave.2")
                }
            }
            Button(role: .destructive) { update(["status": "dropped"]) } label: { Label("Drop", systemImage: "xmark.bin") }
        } else {
            Button { update(["status": "active"]) } label: { Label("Reopen", systemImage: "arrow.uturn.backward") }
        }
    }
}

struct ItemRow: View {
    @EnvironmentObject private var model: AppModel
    let item: PlatformItem
    var subtitle: String? = nil
    var showTick = true
    @ObservedObject var store: PlatformStore

    private var pending: Bool { store.pending[item.id] != nil }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if showTick && item.type == "todo" {
                Button {
                    Task { await model.perform("items.update", input: ["item_id": item.id, "status": item.isDone ? "active" : "done"], key: item.id) }
                } label: {
                    if pending { ProgressView().frame(width: 24, height: 24) }
                    else { Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle").font(.title3).frame(width: 24, height: 24) }
                }.buttonStyle(.plain).foregroundStyle(item.must == true && !item.isDone ? Theme.warning : Theme.accent).disabled(pending)
                    .accessibilityLabel(item.isDone ? "Reopen \(item.title)" : "Complete \(item.title)")
            } else if showTick {
                Image(systemName: icon).font(.body).foregroundStyle(Theme.secondary).frame(width: 24, height: 24)
            }
            Button { model.openItemID = item.id } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title).font(.body).strikethrough(item.isDone).foregroundStyle(item.isDone ? Theme.secondary : Theme.ink)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 8) { details }.font(.caption).foregroundStyle(Theme.secondary).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if item.pinned == true { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(Theme.accent).padding(.top, 4) }
        }
        .padding(.vertical, 13).hairline()
        .opacity(pending ? 0.6 : 1)
        .contextMenu { ItemActions(item: item) }
    }
    private var icon: String {
        switch item.type {
        case "person": "person"
        case "goal": "scope"
        case "habit": "repeat"
        case "project": "hammer"
        case "idea": "lightbulb"
        case "inbox": "tray"
        default: "circle"
        }
    }
    @ViewBuilder private var details: some View {
        if let subtitle { Text(subtitle) }
        else {
            if item.must == true && !item.isDone { Text("Must-do").foregroundStyle(Theme.warning) }
            if item.overdue == true && !item.isDone { Text("Overdue").foregroundStyle(Theme.warning) }
            if item.isSnoozed { Label("Snoozed", systemImage: "moon.zzz") }
            if item.type == "todo" || item.type == "goal" { Text(item.category) } else { Text(item.typeLabel) }
            if let remind = item.remindAt.flatMap(parseISODate) { Label { Text(remind, format: .dateTime.weekday().hour().minute()) } icon: { Image(systemName: "bell") } }
            else if let due = item.dueDate.flatMap(parseDay) { Text("Due \(due.formatted(.dateTime.day().month()))") }
            if let project = item.projectId, let name = store.item(project)?.title { Text(name) }
            if let count = item.noteCount, count > 0 { Label("\(count)", systemImage: "text.alignleft") }
        }
    }
}

struct AppointmentRow: View {
    let title: String
    let at: String
    let allDay: Bool
    var kind = "event"
    var source: String? = nil
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Group {
                if allDay { Text("All day") }
                else if let date = parseISODate(at) { Text(date, style: .time) }
                else { Text(at) }
            }.font(.caption.monospacedDigit()).foregroundStyle(Theme.accent).frame(width: 65, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline)
                if let source { Label(source.capitalized, systemImage: kind == "delivery" ? "shippingbox" : "link").font(.caption2).foregroundStyle(Theme.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, 14).hairline()
    }
}

struct EmptyLine: View {
    let text: String
    var body: some View { Text(text).font(.subheadline).foregroundStyle(Theme.secondary).padding(.vertical, 14) }
}

/// Atlas's questions and held-back changes ("Waiting on you" on the dashboard): tap an option, type
/// an answer, send a held change now or cancel it.
struct WaitingCard: View {
    @EnvironmentObject private var model: AppModel
    let waiting: Waiting
    @ObservedObject var store: PlatformStore
    @State private var answer = ""
    private var busy: Bool { store.pending[waiting.id] != nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(waiting.isQuestion ? "Atlas is asking" : "About to go ahead", systemImage: waiting.isQuestion ? "questionmark.bubble" : "clock.arrow.circlepath")
                .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
            Text(waiting.question ?? waiting.summary ?? "").font(.system(.headline, design: .serif))
            if !waiting.isQuestion, let summary = waiting.summary, waiting.question != nil { Text(summary).font(.subheadline) }
            if let run = (waiting.runAt ?? waiting.expiresAt).flatMap(parseISODate), run > Date() {
                HStack(spacing: 4) {
                    Text(waiting.isQuestion ? "Open for" : "Goes ahead in")
                    Text(timerInterval: Date()...run, countsDown: true).monospacedDigit()
                }.font(.caption).foregroundStyle(Theme.secondary)
            }
            if waiting.isQuestion {
                ForEach(Array(waiting.options.enumerated()), id: \.offset) { index, option in
                    Button { send(["option": index + 1]) } label: {
                        Text(option).frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.bordered)
                }
                HStack {
                    TextField("Or type an answer", text: $answer).textFieldStyle(.roundedBorder)
                    Button("Send") { send(["text": answer]) }.disabled(answer.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            HStack {
                if !waiting.isQuestion {
                    Button("Do it now") { run("pending.run") }.buttonStyle(.borderedProminent).foregroundStyle(Color.atlasBackground)
                }
                Button(waiting.isQuestion ? "Never mind" : "Cancel", role: .destructive) { run("pending.cancel") }.buttonStyle(.bordered)
                if busy { ProgressView() }
            }
        }
        .disabled(busy)
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.accent.opacity(0.35), lineWidth: 1))
    }
    private func send(_ fields: [String: Any]) {
        Task { await model.perform("pending.answer", input: fields.merging(["pending_id": waiting.id]) { a, _ in a }, key: waiting.id) }
    }
    private func run(_ handler: String) {
        Task { await model.perform(handler, input: ["pending_id": waiting.id], key: waiting.id) }
    }
}

struct StatusBlock: View {
    @ObservedObject var store: PlatformStore
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ConnectionBanner()
            if store.loading && store.updatedAt == nil { ProgressView("Gathering your Atlas…").font(.caption) }
            if let updated = store.updatedAt {
                Text("Checked \(updated, style: .relative) ago").font(.caption).foregroundStyle(Theme.secondary)
            }
            ForEach(store.errors.keys.sorted(), id: \.self) { key in
                if let message = store.errors[key] {
                    HStack(alignment: .top) {
                        Text(message).font(.caption).foregroundStyle(Theme.warning)
                        if key == "Action" { Button { store.clearActionError() } label: { Image(systemName: "xmark") }.font(.caption2) }
                    }
                }
            }
        }
    }
}
