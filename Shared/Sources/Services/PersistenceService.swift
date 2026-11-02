import SwiftData
import Foundation

enum PersistenceService {
    static let saveFailed = Notification.Name("MoneyTrackerSaveFailed")

    static func save(_ context: ModelContext) throws {
        do {
            try context.save()
        } catch {
            // A failed save must not leave a shift visually ended or a new
            // record waiting for an unrelated autosave to commit it later.
            context.rollback()
            throw error
        }
    }

    /// Navigation can remove the editing view before it can present an error.
    /// Route those failures to the app root while ordinary editors show theirs.
    static func saveReportingFailure(_ context: ModelContext) {
        do { try save(context) }
        catch { NotificationCenter.default.post(name: saveFailed, object: error.localizedDescription) }
    }
}
