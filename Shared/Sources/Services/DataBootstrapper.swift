import Foundation
import SwiftData

enum DataBootstrapper {
    static func seedIfNeeded(in context: ModelContext) throws {
        if try first(AppPreferences.self, in: context) == nil {
            context.insert(AppPreferences())
        }

        if try first(TaxProfile.self, in: context) == nil {
            context.insert(TaxProfile())
        }

        let jobs = try JobService.ensureJobsSeeded(in: context)

        if let preferences = try first(AppPreferences.self, in: context),
           let preferredJobIdentifier = preferences.selectedHomeJobIdentifier,
           jobs.contains(where: { $0.id == preferredJobIdentifier }) == false {
            preferences.selectedHomeJobIdentifier = jobs.first?.id
        } else if let preferences = try first(AppPreferences.self, in: context),
                  preferences.selectedHomeJobIdentifier == nil {
            preferences.selectedHomeJobIdentifier = jobs.first?.id
        }

        try context.save()
    }

    static func first<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws -> T? {
        var descriptor = FetchDescriptor<T>()
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
