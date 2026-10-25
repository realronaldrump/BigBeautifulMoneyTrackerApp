import Foundation
import SwiftData
import SQLite3

enum AppModelContainerFactory {
    static let schema = Schema([
        JobProfile.self,
        ShiftRecord.self,
        OpenShiftState.self,
        PayRateSchedule.self,
        NightDifferentialRule.self,
        OvertimeRuleSet.self,
        TaxProfile.self,
        PaySchedule.self,
        JobSupplement.self,
        ScheduleTemplate.self,
        ScheduledShift.self,
        AppPreferences.self,
    ])

    static func makeSharedContainer(forWidget: Bool = false) throws -> ModelContainer {
        let fileManager = FileManager.default
        let legacyDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "BigBeautifulMoneyTrackerApp", directoryHint: .isDirectory) ?? .documentsDirectory
        let legacyURL = legacyDirectory.appending(path: "MoneyTracker.sqlite")
        let storeURL: URL

        if let groupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: SharedConstants.appGroupIdentifier) {
            storeURL = groupURL.appending(path: "MoneyTracker.sqlite")
            let migrationMarker = groupURL.appending(path: "SharedStore.ready")
            if forWidget {
                // The extension cannot see the app's legacy sandbox. Let the app
                // migrate it before an extension can create an empty shared store.
                guard fileManager.fileExists(atPath: migrationMarker.path) else {
                    throw StoreAccessError.openAppFirst
                }
            } else {
                if !fileManager.fileExists(atPath: storeURL.path), fileManager.fileExists(atPath: legacyURL.path) {
                    try copyLegacyStore(from: legacyURL, to: storeURL)
                }
                // Open successfully before publishing the ready marker.
                let container = try makeContainer(at: storeURL)
                if !fileManager.fileExists(atPath: migrationMarker.path) {
                    try Data().write(to: migrationMarker, options: .atomic)
                }
                return container
            }
        } else {
            guard !forWidget else { throw StoreAccessError.openAppFirst }
            try fileManager.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
            storeURL = legacyURL
        }

        return try makeContainer(at: storeURL, allowsSave: !forWidget)
    }

    private static func makeContainer(at url: URL, allowsSave: Bool = true) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "MoneyTracker", schema: schema, url: url,
            allowsSave: allowsSave, cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// SQLite's online backup includes committed WAL pages, even while the old
    /// store is open. Copying only the .sqlite file can silently drop recent pay.
    static func copyLegacyStore(from source: URL, to destination: URL) throws {
        guard !FileManager.default.fileExists(atPath: destination.path) else { return }
        let temporary = destination.deletingLastPathComponent().appending(path: "Migration-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: temporary) }
        var sourceDB: OpaquePointer?
        var destinationDB: OpaquePointer?
        guard sqlite3_open_v2(source.path, &sourceDB, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            if let sourceDB { sqlite3_close(sourceDB) }
            throw StoreAccessError.migrationFailed
        }
        defer { sqlite3_close(sourceDB) }
        guard sqlite3_open_v2(temporary.path, &destinationDB, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            if let destinationDB { sqlite3_close(destinationDB) }
            throw StoreAccessError.migrationFailed
        }
        defer { sqlite3_close(destinationDB) }
        sqlite3_busy_timeout(sourceDB, 5_000)
        sqlite3_busy_timeout(destinationDB, 5_000)
        guard let backup = sqlite3_backup_init(destinationDB, "main", sourceDB, "main") else {
            throw StoreAccessError.migrationFailed
        }
        let result = sqlite3_backup_step(backup, -1)
        let finished = sqlite3_backup_finish(backup)
        guard result == SQLITE_DONE, finished == SQLITE_OK else { throw StoreAccessError.migrationFailed }
        try FileManager.default.moveItem(at: temporary, to: destination)
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

enum StoreAccessError: LocalizedError {
    case openAppFirst
    case migrationFailed

    var errorDescription: String? {
        switch self {
        case .openAppFirst:
            "Open Money Tracker to prepare your shared data."
        case .migrationFailed:
            "Your saved data could not be copied to shared storage. The original data is still on this device. Try opening the app again."
        }
    }
}
