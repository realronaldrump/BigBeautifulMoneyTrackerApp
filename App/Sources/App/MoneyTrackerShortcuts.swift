import AppIntents
import SwiftData

struct StartShiftIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Shift"
    static let description = IntentDescription("Starts a new tracked shift.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let container = AppModelContainerFactory.makeSharedContainer()
        try await MainActor.run {
            let context = ModelContext(container)
            try ShiftController.startShift(in: context)
        }
        return .result(dialog: IntentDialog("Shift started."))
    }
}

struct EndShiftIntent: AppIntent {
    static let title: LocalizedStringResource = "End Shift"
    static let description = IntentDescription("Ends the current tracked shift.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let container = AppModelContainerFactory.makeSharedContainer()
        try await MainActor.run {
            let context = ModelContext(container)
            _ = try ShiftController.endShift(in: context)
        }
        return .result(dialog: IntentDialog("Shift ended."))
    }
}

struct MoneyTrackerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartShiftIntent(),
            phrases: [
                "Start my shift in \(.applicationName)",
                "Clock in with \(.applicationName)"
            ],
            shortTitle: "Start Shift",
            systemImageName: "play.fill"
        )

        AppShortcut(
            intent: EndShiftIntent(),
            phrases: [
                "End my shift in \(.applicationName)",
                "Clock out with \(.applicationName)"
            ],
            shortTitle: "End Shift",
            systemImageName: "stop.fill"
        )
    }
}
