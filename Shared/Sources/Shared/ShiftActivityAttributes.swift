import ActivityKit
import Foundation

struct ShiftActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var mode: EarningsDisplayMode
        var syncedAmount: Double
        var currentRate: Double
        var startDate: Date
    }

    var title: String
}
