import SwiftUI

struct ActivityListView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ConnectionBanner()
                if let error = model.activityError { Text(error).font(.footnote).foregroundStyle(.orange) }
                if model.visibleRequests.isEmpty {
                    ContentUnavailableView("Room to think", systemImage: "circle.dotted.circle", description: Text("Questions, pending work, and completed requests appear here after you talk to Atlas."))
                } else {
                    if !model.activeRequests.isEmpty {
                        Text("IN MOTION").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(Theme.secondary)
                        ForEach(model.activeRequests) { request in row(request) }
                    }
                    let finished = model.visibleRequests.filter { !$0.isActive }
                    if !finished.isEmpty {
                        Text("RECENTLY").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(Theme.secondary).padding(.top, 12)
                        ForEach(finished) { request in row(request) }
                    }
                }
            }.padding(20)
        }
        .background(Color.atlasBackground).navigationTitle("Activity")
        .refreshable { await model.refresh() }
    }
    private func row(_ request: TrackedRequest) -> some View {
        Button { model.selectedRequestID = request.id } label: { RequestRow(request: request) }.buttonStyle(.plain)
    }
}

struct RequestDetailView: View {
    @EnvironmentObject private var model: AppModel
    let request: TrackedRequest
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Label(request.statusLabel, systemImage: request.isQuestion ? "questionmark.bubble" : "circle.dotted.circle")
                    .font(.subheadline).foregroundStyle(Theme.accent)
                Text(request.title).font(.title2.bold())
                Text(request.summary).textSelection(.enabled)
                if request.text != request.title {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Original request").font(.caption.bold()).foregroundStyle(Theme.secondary)
                        Text(request.text).font(.subheadline).textSelection(.enabled)
                    }
                }
                if request.isQuestion {
                    Button { model.answer(request) } label: { Label("Answer with your voice", systemImage: "mic.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).foregroundStyle(Color.atlasBackground)
                }
                if request.canCancel {
                    Button(request.isQuestion ? "Dismiss question" : "Cancel pending request", role: .destructive) {
                        Task { await model.cancel(request) }
                    }.buttonStyle(.bordered)
                }
                Link("Open Atlas dashboard", destination: AppConfiguration.backendURL).font(.subheadline)
            }.padding(24)
        }.background(Color.atlasBackground).navigationTitle("Request").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { model.selectedRequestID = nil } } }
    }
}
