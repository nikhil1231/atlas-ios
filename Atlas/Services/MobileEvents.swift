import Foundation

struct MobileEvent: Decodable {
    let id: String
    let sequence: Int
    let type: String
    let payload: JSONValue
}

struct EventFrame: Equatable {
    let id: String?
    let type: String
    let data: String
}

// Byte-level framing bounds even an unterminated line; AsyncBytes.lines alone does not.
struct EventParser {
    private var bytes = Data()
    private var fields: [String] = []
    private var frameBytes = 0
    static let limit = 2 * 1024 * 1024
    mutating func feed(_ byte: UInt8) throws -> EventFrame? {
        if byte != 10 {
            bytes.append(byte)
            guard bytes.count + frameBytes <= Self.limit else { throw StreamError.invalidFrame }
            return nil
        }
        var line = String(decoding: bytes, as: UTF8.self)
        bytes.removeAll(keepingCapacity: true)
        if line.last == "\r" { line.removeLast() }
        if !line.isEmpty {
            if !line.hasPrefix(":") { fields.append(line); frameBytes += line.utf8.count }
            return nil
        }
        defer { fields.removeAll(keepingCapacity: true); frameBytes = 0 }
        var id: String?, type = "message", data: [String] = []
        for field in fields {
            let parts = field.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            var value = parts.count > 1 ? String(parts[1]) : ""
            if value.first == " " { value.removeFirst() }
            switch parts[0] {
            case "id": if !value.contains("\0") { id = value }
            case "event": type = value
            case "data": data.append(value)
            default: break
            }
        }
        return data.isEmpty ? nil : EventFrame(id: id, type: type, data: data.joined(separator: "\n"))
    }
}

enum StreamError: Error { case reset, unavailable(Int), invalidFrame, ended }

struct MobileProjection: Codable {
    var state: MobileState
    var savedAt: Date
    // Never persist read responses until a screen actually consumes them.
    init(state: MobileState = MobileState(requests: [], notifications: []), savedAt: Date = Date()) {
        self.state = state; self.savedAt = savedAt
    }
    mutating func merge(_ request: TrackedRequest) {
        if let old = state.requests.first(where: { $0.id == request.id }) {
            if let a = old.revision, let b = request.revision, a > b { return }
            if old.revision == nil || request.revision == nil,
               let a = parseISODate(old.updatedAt), let b = parseISODate(request.updatedAt), a > b { return }
        }
        state.requests.removeAll { $0.id == request.id }
        state.requests.insert(request, at: 0)
        // Match the server: retain every active request and the newest 200 records.
        state.requests = state.requests.enumerated().filter { $0.offset < 200 || $0.element.isActive }.map(\.element)
    }
    // Return true when the journal payload points to data available only in a full snapshot.
    mutating func apply(_ event: MobileEvent) throws -> Bool {
        guard event.sequence > (state.cursor ?? 0) else { return false }
        var needsSnapshot = false
        switch event.type {
        case "operation.updated":
            let request = try event.payload.decode(TrackedRequest.self)
            merge(request)
            needsSnapshot = !request.isActive || request.isQuestion
        case "notification.updated":
            let note = try event.payload.decode(AtlasNotification.self)
            state.notifications.removeAll { $0.id == note.id }
            state.notifications.insert(note, at: 0)
            state.notifications = Array(state.notifications.prefix(200))
        case "notification.created": needsSnapshot = true
        default: break // Future event types still advance the ordered cursor.
        }
        state.cursor = event.sequence
        savedAt = Date()
        return needsSnapshot
    }
}
