import SwiftUI

struct NotificationsView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ConnectionBanner()
                if model.notifications.isEmpty {
                    ContentUnavailableView("You’re all caught up", systemImage: "tray", description: Text("Answers, completed requests, failures, and updates from Atlas will land here."))
                }
                ForEach(model.notifications) { note in
                    Button { Task { await model.openNotification(note) } } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Circle().fill(note.read ? .clear : Theme.accent).frame(width: 7, height: 7).padding(.top, 6)
                            VStack(alignment: .leading, spacing: 7) {
                                Text(note.title).font(.subheadline.weight(.semibold))
                                Text(note.body).font(.subheadline).foregroundStyle(Theme.secondary).lineLimit(5)
                                if let date = parseISODate(note.createdAt) { Text(date, style: .relative).font(.caption).foregroundStyle(Theme.secondary) }
                            }
                            Spacer(minLength: 0)
                        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
                    }.buttonStyle(.plain)
                }
            }.padding(20)
        }.background(Color.atlasBackground).navigationTitle("Inbox")
            .refreshable { await model.refresh() }
    }
}
