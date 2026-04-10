import ActivityKit
import Foundation

@MainActor
enum LiveActivityManager {
    static func startOrUpdate(
        title: String,
        startDate: Date,
        amount: Double,
        rate: Double,
        mode: EarningsDisplayMode
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = ShiftActivityAttributes(title: title)
        let contentState = ShiftActivityAttributes.ContentState(
            mode: mode,
            syncedAmount: amount,
            currentRate: rate,
            startDate: startDate
        )
        let content = ActivityContent(state: contentState, staleDate: Date.now.addingTimeInterval(15 * 60))

        Task {
            if let activity = Activity<ShiftActivityAttributes>.activities.first {
                await activity.update(content)
            } else {
                _ = try? Activity<ShiftActivityAttributes>.request(attributes: attributes, content: content)
            }
        }
    }

    static func end(finalAmount: Double, mode: EarningsDisplayMode) {
        let contentState = ShiftActivityAttributes.ContentState(
            mode: mode,
            syncedAmount: finalAmount,
            currentRate: 0,
            startDate: .now
        )
        let content = ActivityContent(state: contentState, staleDate: nil)

        Task {
            for activity in Activity<ShiftActivityAttributes>.activities {
                await activity.end(content, dismissalPolicy: .immediate)
            }
        }
    }
}
