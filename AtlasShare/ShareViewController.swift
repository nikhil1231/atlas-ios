import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Share sheet → Atlas. The shared text or link (plus anything you add) goes through the same capture
/// pipeline as speaking a thought, so Atlas files it as a to-do, idea, note or question.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let model = ShareModel(context: extensionContext)
        let host = UIHostingController(rootView: ShareView(model: model))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        Task { await model.loadAttachments() }
    }
}

@MainActor
final class ShareModel: ObservableObject {
    @Published var shared = ""
    @Published var note = ""
    @Published var state: SendState = .editing
    enum SendState: Equatable { case editing, sending, sent(String), failed(String) }
    private let context: NSExtensionContext?
    private let id = UUID()  // a retry after an uncertain failure reuses it, so Atlas files it once

    init(context: NSExtensionContext?) { self.context = context }

    func loadAttachments() async {
        var parts: [String] = []
        for item in context?.inputItems.compactMap({ $0 as? NSExtensionItem }) ?? [] {
            if let text = item.attributedContentText?.string, !text.isEmpty { parts.append(text) }
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                    parts.append(url.absoluteString)
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                          let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                    parts.append(text)
                }
            }
        }
        shared = Array(NSOrderedSet(array: parts)).compactMap { $0 as? String }.joined(separator: "\n")
    }

    var text: String {
        [note.trimmingCharacters(in: .whitespacesAndNewlines), shared.trimmingCharacters(in: .whitespacesAndNewlines)]
            .filter { !$0.isEmpty }.joined(separator: "\n")
    }

    func send() async {
        guard !text.isEmpty, text.count <= 5000 else { return }
        state = .sending
        do {
            let client = try AtlasClient.load()
            let request = try await client.submit(text, id: id)
            state = .sent(request.status == "queued" ? "Sent. Atlas is filing it now." : request.summary)
            try? await Task.sleep(for: .seconds(1.2))
            done()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
    func done() { context?.completeRequest(returningItems: nil) }
    func cancel() { context?.cancelRequest(withError: CocoaError(.userCancelled)) }
}

struct ShareView: View {
    @ObservedObject var model: ShareModel
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Add a thought (optional)", text: $model.note, axis: .vertical)
                        .lineLimit(2...5)
                } footer: {
                    Text("For example “read this at the weekend” or “idea for the garden project”.")
                }
                Section("Sharing") {
                    Text(model.shared.isEmpty ? "Nothing to share" : model.shared)
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(8)
                }
                switch model.state {
                case .sent(let message): Section { Label(message, systemImage: "checkmark.circle") }
                case .failed(let message):
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        Text("Sending again is safe: Atlas won't file it twice.").font(.caption)
                    }
                default: EmptyView()
                }
            }
            .navigationTitle("Send to Atlas").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { model.cancel() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.state == .sending ? "Sending…" : "Send") { Task { await model.send() } }
                        .disabled(model.text.isEmpty || model.state == .sending || model.text.count > 5000)
                }
            }
        }
    }
}
