import SwiftUI

extension Color {
    static let atlasBackground = Theme.paper
}
enum Theme {
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
    static let paper = adaptive(0xf8f7f3, 0x1a1916)
    static let ink = adaptive(0x2a2925, 0xe8e4db)
    static let accent = adaptive(0x9d7a4a, 0xc9a36f)
    static let secondary = adaptive(0x8a857b, 0x8f8a80)
    static let card = adaptive(0xfdfcf9, 0x23221e)
    static let line = adaptive(0xe7e3db, 0x2f2d29)
    static let warning = adaptive(0xa8432c, 0xe0745a)
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        TabView(selection: $model.selectedTab) {
            NavigationStack { PlatformView(store: model.platform, today: true) }
                .tabItem { Label("Today", systemImage: "sun.max") }.tag(3)
            NavigationStack { PlatformView(store: model.platform, today: false) }
                .tabItem { Label("Everything", systemImage: "checklist") }.tag(4)
            NavigationStack { VoiceView(voice: model.voice) }
                .tabItem { Label("Talk", systemImage: "waveform") }.tag(0)
            NavigationStack { ActivityListView() }
                .tabItem { Label("Activity", systemImage: "circle.dotted.circle") }
                .badge(model.activeRequests.count).tag(1)
            NavigationStack { NotificationsView() }
                .tabItem { Label("Inbox", systemImage: "tray") }
                .badge(model.unreadCount).tag(2)
        }
        .foregroundStyle(Theme.ink)
        .sheet(isPresented: $model.showSettings) { SettingsView() }
        .sheet(item: Binding(get: { model.openItemID.map(ItemLink.init) }, set: { model.openItemID = $0?.id })) { link in
            NavigationStack { ItemDetailView(itemID: link.id, store: model.platform) }
        }
        .sheet(item: $model.selectedNotification) { note in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(note.title).font(.title2.bold())
                        Text(note.body).textSelection(.enabled)
                        Link("Open Atlas dashboard", destination: AppConfiguration.backendURL)
                    }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                }.navigationTitle("Update").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { model.selectedNotification = nil } } }
            }
        }
        .sheet(isPresented: Binding(get: { model.selectedRequestID != nil }, set: { if !$0 { model.selectedRequestID = nil } })) {
            NavigationStack {
                if let request = model.requests.first(where: { $0.id == model.selectedRequestID }) {
                    RequestDetailView(request: request)
                } else {
                    ContentUnavailableView("Request unavailable", systemImage: "clock", description: Text("Pull to refresh Activity, or check the hosted Atlas dashboard for older work."))
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { model.selectedRequestID = nil } } }
                }
            }
        }
    }
}

struct ConnectionBanner: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        if model.showingSavedState || (model.lastSynced != nil && model.connection != .live) {
            HStack {
                Image(systemName: "clock")
                if let date = model.lastSynced {
                    if model.showingSavedState { Text("Saved update from \(date, style: .relative) ago") }
                    else { Text("Updated \(date, style: .relative) ago") }
                }
                if model.connection == .connecting { Text("· Updating…") }
            }.font(.caption).foregroundStyle(Theme.secondary)
        }
        if model.sourceHealth?.connected == false {
            Text("Some information may be out of date while Atlas reconnects.")
                .font(.caption).foregroundStyle(.orange)
        }
        if let error = model.error {
            VStack(alignment: .leading, spacing: 6) {
                Label("Couldn’t sync", systemImage: "wifi.exclamationmark").font(.subheadline.bold())
                Text(error).font(.caption)
                Button("Try again") { Task { await model.refresh() } }.font(.caption.bold())
            }
            .foregroundStyle(.orange).padding().frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

struct RequestRow: View {
    let request: TrackedRequest
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: request.isQuestion ? "questionmark.bubble" : request.status == "completed" ? "checkmark.circle" : "circle.dotted.circle")
                .font(.title3).foregroundStyle(request.isQuestion ? .orange : Theme.accent)
            VStack(alignment: .leading, spacing: 5) {
                Text(request.title).font(.subheadline.weight(.medium)).lineLimit(2)
                Text(request.statusLabel).font(.caption).foregroundStyle(Theme.secondary)
                if request.status == "queued", let date = request.executeAt.flatMap(parseISODate), date > Date() {
                    Text(date, style: .relative).font(.caption.monospacedDigit()).foregroundStyle(Theme.accent)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.secondary)
        }.padding(.vertical, 16).overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 0.5) }
    }
}

struct ItemLink: Identifiable { let id: String }
