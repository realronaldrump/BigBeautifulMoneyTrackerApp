import Foundation
import SwiftData

@MainActor
enum DataBootstrapper {
    static func seedIfNeeded(in context: ModelContext) throws {
        if try first(AppPreferences.self, in: context) == nil {
            context.insert(AppPreferences())
        }

        if try first(NightDifferentialRule.self, in: context) == nil {
            context.insert(NightDifferentialRule())
        }

        if try first(OvertimeRuleSet.self, in: context) == nil {
            context.insert(OvertimeRuleSet())
        }

        if try first(TaxProfile.self, in: context) == nil {
            context.insert(TaxProfile())
        }

        if try first(PaySchedule.self, in: context) == nil {
            context.insert(PaySchedule())
        }

        if try first(WorkplaceLocation.self, in: context) == nil {
            context.insert(WorkplaceLocation())
        }

        try context.save()
    }

    static func first<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws -> T? {
        var descriptor = FetchDescriptor<T>()
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
