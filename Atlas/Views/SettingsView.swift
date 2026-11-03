import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = Credentials()
    @State private var saving = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Backend", value: AppConfiguration.backendURL.host ?? "")
                    SecureField("Atlas bearer token", text: $draft.token)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: { Text("Hosted Atlas") } footer: { Text("Use the existing ATLAS_TOKEN (formerly NOODLE_TOKEN). Credentials are stored in this device’s Keychain, shared only with Atlas’s widgets and share sheet.") }
                Section {
                    SecureField("Cloudflare client ID", text: $draft.accessID)
                    SecureField("Cloudflare client secret", text: $draft.accessSecret)
                } header: { Text("Cloudflare Access") } footer: { Text("Enter both values if your hosted backend uses a Cloudflare service token.") }
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                RemindersSection(sync: model.reminders)
                Section("Notifications") {
                    Text(model.pushStatus).font(.subheadline)
                    Button("Enable push notifications") { Task { await model.enableNotifications() } }
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
                Section {
                    Label("“Hey Siri, tell Atlas…” files a thought without opening the app.", systemImage: "text.bubble")
                    Label("“What’s on today in Atlas” reads out your day.", systemImage: "sun.max")
                    Label("Set the Action Button or a Control Center control to Talk to Atlas.", systemImage: "waveform")
                    Label("Add the Today and Focus widgets to your Home or Lock Screen; tick to-dos off from there.", systemImage: "square.grid.2x2")
                    Label("Share any page or text to Atlas from the share sheet.", systemImage: "square.and.arrow.up")
                } header: { Text("Around the phone") }
                    .font(.subheadline)
                Section {
                    Text("Voice conversations use OpenAI’s AI voice through your Atlas server. Audio is sent while a conversation is active; leaving the app ends it. Submitted work continues on the server.")
                    Text("Live Activities show open questions and pending work. Tap a question to open Atlas and answer by voice.")
                } header: { Text("Voice & activity") }
                if let error = model.error { Section { Text(error).foregroundStyle(.orange) } }
            }
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") {
                        saving = true
                        Task { await model.save(draft); saving = false }
                    }.disabled(saving || draft.accessID.isEmpty != draft.accessSecret.isEmpty)
                }
            }
            .onAppear { draft = model.credentials }
        }
    }
}

struct RemindersSection: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var sync: ReminderSync
    var body: some View {
        Section {
            Toggle("Sync with Apple Reminders", isOn: $sync.enabled)
            if sync.enabled {
                if !sync.authorized {
                    Button("Allow access to Reminders") { Task { await sync.requestAccess() } }
                } else {
                    Picker("List", selection: $sync.listID) {
                        Text("Choose…").tag(String?.none)
                        ForEach(sync.lists, id: \.calendarIdentifier) { Text($0.title).tag(Optional($0.calendarIdentifier)) }
                    }
                    if !sync.lists.contains(where: { $0.title == "Atlas" }) {
                        Button("Create an “Atlas” list") { sync.createList() }
                    }
                    Button("Sync now") { Task { await sync.sync(api: model.api, force: true) } }
                }
                Text(sync.status).font(.caption).foregroundStyle(Theme.secondary)
                if let last = sync.lastSync { Text("Last synced \(last, style: .relative) ago").font(.caption).foregroundStyle(Theme.secondary) }
            }
        } header: { Text("Reminders") } footer: {
            Text("Replaces the Atlas Sync Shortcut: ticks, snoozes and deletes on the phone reach Atlas, and Atlas’s reminders, ticks and new times reach the phone. It runs when you open Atlas, whenever Reminders changes, right after a capture, and in the background. Use the same list the Shortcut used; once this works you can turn off the Shortcut’s automations.")
        }
        .onChange(of: sync.enabled) { _, on in
            if on { Task { await sync.requestAccess(); await sync.sync(api: model.api, force: true) } }
        }
        .onChange(of: sync.listID) { _, _ in Task { await sync.sync(api: model.api, force: true) } }
    }
}
