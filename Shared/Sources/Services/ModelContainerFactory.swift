import Foundation
import SwiftData

enum AppModelContainerFactory {
    static let schema = Schema([
        ShiftRecord.self,
        OpenShiftState.self,
        PayRateSchedule.self,
        NightDifferentialRule.self,
        OvertimeRuleSet.self,
        TaxProfile.self,
        PaySchedule.self,
        ScheduleTemplate.self,
        MilestoneEvent.self,
        WorkplaceLocation.self,
        AppPreferences.self,
    ])

    static func makeSharedContainer() -> ModelContainer {
        let configuration: ModelConfiguration
        #if targetEnvironment(simulator)
        let fallbackDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "BigBeautifulMoneyTrackerApp", directoryHint: .isDirectory)
        if let fallbackDirectory {
            try? FileManager.default.createDirectory(at: fallbackDirectory, withIntermediateDirectories: true)
            let storeURL = fallbackDirectory.appending(path: "MoneyTracker.sqlite")
            configuration = ModelConfiguration(
                "MoneyTracker",
                schema: schema,
                url: storeURL,
                allowsSave: true,
                cloudKitDatabase: .none
            )
        } else {
            let storeURL = URL.documentsDirectory.appending(path: "MoneyTracker.sqlite")
            configuration = ModelConfiguration(
                "MoneyTracker",
                schema: schema,
                url: storeURL,
                allowsSave: true,
                cloudKitDatabase: .none
            )
        }
        #else
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedConstants.appGroupIdentifier) {
            let storeURL = groupURL.appending(path: "MoneyTracker.sqlite")
            configuration = ModelConfiguration(
                "MoneyTracker",
                schema: schema,
                url: storeURL,
                allowsSave: true,
                cloudKitDatabase: .automatic
            )
        } else {
            let fallbackDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appending(path: "BigBeautifulMoneyTrackerApp", directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: fallbackDirectory ?? .documentsDirectory, withIntermediateDirectories: true)
            let fallbackURL = (fallbackDirectory ?? .documentsDirectory).appending(path: "MoneyTracker.sqlite")
            configuration = ModelConfiguration(
                "MoneyTracker",
                schema: schema,
                url: fallbackURL,
                allowsSave: true,
                cloudKitDatabase: .none
            )
        }
        #endif

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create shared model container: \(error.localizedDescription)")
        }
    }

    static func makeInMemoryContainer() -> ModelContainer {
        let configuration = ModelConfiguration(
            "MoneyTrackerPreview",
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true,
            groupContainer: .none,
            cloudKitDatabase: .none
        )

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create preview model container: \(error.localizedDescription)")
        }
    }
}
