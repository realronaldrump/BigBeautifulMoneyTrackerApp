import ActivityKit
import Foundation

struct ShiftLiveActivityPayload: Equatable {
    var title: String
    var contentState: ShiftActivityAttributes.ContentState
    var staleDate: Date
}

enum ShiftLiveActivitySyncAction: Equatable {
    case update(ShiftLiveActivityPayload)
    case end(ShiftActivityAttributes.ContentState)
}

@MainActor
enum LiveActivityManager {
    static let staleInterval: TimeInterval = 2 * 60

    static func sync(
        for snapshot: DashboardSnapshot,
        mode: EarningsDisplayMode,
        compensationMode: CompensationDisplayMode
    ) {
        perform(makeSyncAction(for: snapshot, mode: mode, compensationMode: compensationMode))
    }

    static func makeSyncAction(
        for snapshot: DashboardSnapshot,
        mode: EarningsDisplayMode,
        compensationMode: CompensationDisplayMode,
        now: Date = .now
    ) -> ShiftLiveActivitySyncAction {
        let syncedAmount = snapshot.displayAmount(for: mode, compensationMode: compensationMode)

        guard !snapshot.activeJobs.isEmpty else {
            return .end(
                makeContentState(
                    mode: mode,
                    compensationMode: compensationMode,
                    syncedAmount: syncedAmount,
                    currentRate: 0,
                    startDate: now,
                    lastSyncedDate: now
                )
            )
        }

        let title = snapshot.activeJobs.count == 1
            ? snapshot.activeJobs[0].name
            : "\(snapshot.activeJobs.count) Jobs Active"
        let contentState = makeContentState(
            mode: mode,
            compensationMode: compensationMode,
            syncedAmount: syncedAmount,
            currentRate: snapshot.currentDisplayRate(for: mode, compensationMode: compensationMode) ?? 0,
            startDate: snapshot.activeJobs.map(\.startDate).min() ?? now,
            lastSyncedDate: now
        )

        return .update(
            ShiftLiveActivityPayload(
                title: title,
                contentState: contentState,
                staleDate: now.addingTimeInterval(staleInterval)
            )
        )
    }

    static func startOrUpdate(
        title: String,
        startDate: Date,
        syncedAmount: Double,
        currentRate: Double,
        mode: EarningsDisplayMode,
        compensationMode: CompensationDisplayMode,
        now: Date = .now
    ) {
        let contentState = makeContentState(
            mode: mode,
            compensationMode: compensationMode,
            syncedAmount: syncedAmount,
            currentRate: currentRate,
            startDate: startDate,
            lastSyncedDate: now
        )
        let payload = ShiftLiveActivityPayload(
            title: title,
            contentState: contentState,
            staleDate: now.addingTimeInterval(staleInterval)
        )

        startOrUpdate(payload)
    }

    static func startOrUpdate(_ payload: ShiftLiveActivityPayload) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = ShiftActivityAttributes(title: payload.title)
        let content = ActivityContent(state: payload.contentState, staleDate: payload.staleDate)

        Task {
            if let activity = Activity<ShiftActivityAttributes>.activities.first {
                await activity.update(content)
            } else {
                _ = try? Activity<ShiftActivityAttributes>.request(attributes: attributes, content: content)
            }
        }
    }

    static func end(
        finalAmount: Double,
        mode: EarningsDisplayMode,
        compensationMode: CompensationDisplayMode,
        now: Date = .now
    ) {
        let contentState = makeContentState(
            mode: mode,
            compensationMode: compensationMode,
            syncedAmount: finalAmount,
            currentRate: 0,
            startDate: now,
            lastSyncedDate: now
        )

        end(contentState)
    }

    private static func perform(_ action: ShiftLiveActivitySyncAction) {
        switch action {
        case .update(let payload):
            startOrUpdate(payload)
        case .end(let contentState):
            end(contentState)
        }
    }

    private static func end(_ contentState: ShiftActivityAttributes.ContentState) {
        let content = ActivityContent(state: contentState, staleDate: nil)

        Task {
            for activity in Activity<ShiftActivityAttributes>.activities {
                await activity.end(content, dismissalPolicy: .immediate)
            }
        }
    }

    private static func makeContentState(
        mode: EarningsDisplayMode,
        compensationMode: CompensationDisplayMode,
        syncedAmount: Double,
        currentRate: Double,
        startDate: Date,
        lastSyncedDate: Date
    ) -> ShiftActivityAttributes.ContentState {
        ShiftActivityAttributes.ContentState(
            mode: mode,
            compensationMode: compensationMode,
            syncedAmount: syncedAmount,
            currentRate: currentRate,
            startDate: startDate,
            lastSyncedDate: lastSyncedDate
        )
    }
}
