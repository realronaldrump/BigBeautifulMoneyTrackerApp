import ActivityKit
import Foundation

struct ShiftActivityAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        var mode: EarningsDisplayMode
        var compensationMode: CompensationDisplayMode
        var syncedAmount: Double
        var currentRate: Double
        var startDate: Date
        var lastSyncedDate: Date
    }

    var title: String
}
