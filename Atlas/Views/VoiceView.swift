import SwiftUI

struct VoiceView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var voice: VoiceSession
    @State private var message = ""
    @FocusState private var messageFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ConnectionBanner()
                VStack(alignment: .leading, spacing: 8) {
                    Text("What’s on your mind?").font(.system(.largeTitle, design: .serif))
                    Text("A thought, a plan, or a question. Atlas will find its place.")
                        .font(.subheadline).foregroundStyle(Theme.secondary)
                }
                VStack(spacing: 18) {
                    TimelineView(.animation(minimumInterval: 1.0 / 12, paused: !voice.isConnected || reduceMotion)) { context in
                        let pulse = voice.isConnected && !reduceMotion ? sin(context.date.timeIntervalSinceReferenceDate * 2) * 0.035 : 0
                        ZStack {
                            Circle().fill(Theme.accent.opacity(0.035)).frame(width: 230, height: 230)
                            Circle().stroke(Theme.accent.opacity(0.12), lineWidth: 1).frame(width: 200, height: 200)
                            Circle().fill(RadialGradient(colors: [Theme.accent, Theme.accent.opacity(0.45), Theme.card], center: .topLeading, startRadius: 8, endRadius: 170))
                                .frame(width: 158, height: 158).scaleEffect(1 + pulse)
                                .shadow(color: Theme.accent.opacity(0.15), radius: 30)
                            Image(systemName: voice.isConnected ? "waveform" : "waveform.path")
                                .font(.system(size: 40, weight: .light)).foregroundStyle(.white.opacity(0.9))
                        }.frame(maxWidth: .infinity).accessibilityHidden(true)
                    }
                    Text(model.loadingCredentials ? "Loading…" : voice.state.rawValue).font(.subheadline).foregroundStyle(Theme.secondary)
                    Button {
                        if voice.isConnected { voice.disconnect() } else { model.startVoice() }
                    } label: {
                        Label(voice.isConnected ? "End conversation" : "Start talking", systemImage: voice.isConnected ? "stop.fill" : "mic.fill")
                            .font(.headline).padding(.vertical, 15).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(voice.isConnected ? .gray : Theme.accent)
                    .foregroundStyle(Color.atlasBackground)
                    .disabled(model.loadingCredentials)

                }
                if let error = voice.error { Text(error).font(.footnote).foregroundStyle(.orange) }
                if !model.openQuestions.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("WAITING FOR YOU").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(Theme.secondary)
                        ForEach(model.openQuestions.prefix(3)) { question in
                            Button { model.answer(question) } label: { RequestRow(request: question) }.buttonStyle(.plain)
                        }
                    }
                }
                if !voice.transcript.isEmpty {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("THIS CONVERSATION").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(Theme.secondary)
                        ForEach(voice.transcript) { line in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(line.role).font(.caption.bold()).foregroundStyle(line.role == "You" ? Theme.secondary : Theme.accent)
                                Text(line.text).font(.body).textSelection(.enabled)
                            }
                        }
                    }
                }
            }.padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                if let error = model.messageError {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
                if let question = model.voiceQuestion, model.openQuestions.contains(where: { $0.id == question.id }) {
                    HStack {
                        Text("Replying: \(question.title)").font(.caption).lineLimit(2)
                        Spacer()
                        Button("Cancel") { model.voiceQuestion = nil }
                    }.foregroundStyle(Theme.secondary)
                }
                HStack(alignment: .bottom, spacing: 12) {
                    TextField("Message Atlas", text: $message, axis: .vertical)
                        .lineLimit(1...5).focused($messageFocused)
                        .padding(12).background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
                    Button {
                        let sent = message
                        Task {
                            if await model.sendMessage(sent), message == sent {
                                message = ""
                                messageFocused = false
                            }
                        }
                    } label: {
                        Group {
                            if model.sendingMessage { ProgressView() }
                            else { Image(systemName: "arrow.up.circle.fill").font(.system(size: 34)) }
                        }.frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Send message")
                    .disabled(model.loadingCredentials || model.sendingMessage || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || message.trimmingCharacters(in: .whitespacesAndNewlines).count > 5000)
                }
                if message.trimmingCharacters(in: .whitespacesAndNewlines).count > 5000 {
                    Text("Messages can be up to 5,000 characters.").font(.caption).foregroundStyle(.orange)
                }
                if let latest = model.requests.first, !model.sendingMessage {
                    Button { model.selectedRequestID = latest.id } label: {
                        HStack {
                            Text(latest.title).lineLimit(1)
                            Spacer()
                            Text(latest.statusLabel)
                        }.font(.caption).foregroundStyle(Theme.secondary)
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 20).padding(.vertical, 12)
                .background(Color.atlasBackground)
        }
        .background(Color.atlasBackground)
        .navigationTitle("Atlas").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { model.showSettings = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Settings").disabled(model.loadingCredentials) } }
    }
}
