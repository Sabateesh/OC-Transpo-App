import ActivityKit
import Foundation

struct JourneyActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let title: String
        let detail: String
        let route: String
        let symbol: String
        let arrival: Date
        let departure: Date?
        let stopsRemaining: Int?
        let updatedAt: Date
        let urgent: Bool
        var legIndex: Int? = nil
        var actionToken: String? = nil
        var onBoard: Bool? = nil
        var canBoard: Bool? = nil
    }
    let sessionID: UUID
    let destination: String
}
