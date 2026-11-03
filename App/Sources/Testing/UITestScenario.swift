#if DEBUG
import Foundation
import SwiftData

/// UI tests use an isolated in-memory store and never open the user's records.
enum UITestScenario: String {
    case hourlyJobs
    case salaryOnly

    static var current: UITestScenario? {
        ProcessInfo.processInfo.environment["MONEY_TRACKER_UI_SCENARIO"].flatMap(Self.init(rawValue:))
    }

    @MainActor
    func makeContainer() throws -> ModelContainer {
        let container = AppModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        try DataBootstrapper.seedIfNeeded(in: context)
        let job = try JobService.jobs(in: context)[0]
        let preferences = try DataBootstrapper.first(AppPreferences.self, in: context)!
        preferences.onboardingCompleted = true
        preferences.liveActivitiesEnabled = false
        preferences.remindersEnabled = false
        preferences.hapticsEnabled = false

        let anchor = Calendar.current.date(byAdding: .day, value: -7, to: Calendar.current.startOfDay(for: .now))!
        switch self {
        case .hourlyJobs:
            job.name = "Big Beautiful Job"
            let second = try JobService.createJob(in: context, name: "Lululemon", anchorDate: anchor)
            let third = try JobService.createJob(in: context, name: "Business System Support Analyst", anchorDate: anchor)
            for (index, hourlyJob) in [job, second, third].enumerated() {
                context.insert(PayRateSchedule(job: hourlyJob, effectiveDate: anchor, hourlyRate: 25 + Double(index) * 5))
            }
            preferences.selectedHomeJobIdentifier = third.id
        case .salaryOnly:
            job.name = "Salary Job"
            try SalaryService.savePlan(SalaryPlan(effectiveDate: anchor, amount: 78_000, anchorDate: anchor),
                                       for: job, in: context)
            preferences.selectedHomeJobIdentifier = job.id
        }
        try PersistenceService.save(context)
        return container
    }
}
#endif
