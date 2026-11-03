import ActivityKit
import Foundation

struct AtlasActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var status: String
        var summary: String
        var executeAt: String? = nil
        var phase: String? = nil
    }
    var requestID: String
    var kind: String
}
