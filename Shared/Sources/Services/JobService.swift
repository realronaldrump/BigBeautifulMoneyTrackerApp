import Foundation
import SwiftData

enum JobServiceError: LocalizedError {
    case maxJobsReached

    var errorDescription: String? {
        switch self {
        case .maxJobsReached:
            "You can keep up to six jobs in the app."
        }
    }
}

struct JobConfiguration {
    let job: JobProfile
    let payRates: [PayRateSchedule]
    let nightRule: NightDifferentialRule
    let overtimeRule: OvertimeRuleSet?
    let paySchedule: PaySchedule
    let templates: [ScheduleTemplate]
}

enum JobService {
    static let maxJobs = 6

    static func jobs(in context: ModelContext, includeArchived: Bool = false) throws -> [JobProfile] {
        let descriptor = FetchDescriptor<JobProfile>(
            sortBy: [
                SortDescriptor(\JobProfile.sortOrder),
                SortDescriptor(\JobProfile.createdAt)
            ]
        )
        let allJobs = try context.fetch(descriptor)
        guard !includeArchived else {
            return allJobs
        }
        return allJobs.filter { !$0.isArchived }
    }

    @discardableResult
    static func ensureJobsSeeded(in context: ModelContext) throws -> [JobProfile] {
        var existingJobs = try jobs(in: context, includeArchived: true)

        if existingJobs.isEmpty {
            let defaultJob = JobProfile(name: "Main Job", accent: .emerald, sortOrder: 0)
            context.insert(defaultJob)
            existingJobs = [defaultJob]
        }

        let activeJobs = existingJobs.filter { !$0.isArchived }
        let fallbackJob = activeJobs.first ?? existingJobs.first!

        try migrateUnassignedModels(to: fallbackJob, in: context)

        let sortedJobs = existingJobs.sorted {
            if $0.sortOrder == $1.sortOrder {
                return $0.createdAt < $1.createdAt
            }
            return $0.sortOrder < $1.sortOrder
        }

        for (index, job) in sortedJobs.enumerated() where job.sortOrder != index {
            job.sortOrder = index
            job.updatedAt = .now
        }

        for job in sortedJobs where !job.isArchived {
            ensureConfiguration(for: job, in: context)
        }

        return try jobs(in: context)
    }

    @discardableResult
    static func createJob(
        in context: ModelContext,
        name: String,
        accent: JobAccentStyle? = nil,
        anchorDate: Date = .now
    ) throws -> JobProfile {
        let existingJobs = try jobs(in: context)
        guard existingJobs.count < maxJobs else {
            throw JobServiceError.maxJobsReached
        }

        let newJob = JobProfile(
            name: name,
            accent: accent ?? nextAccent(after: existingJobs),
            sortOrder: existingJobs.count
        )
        context.insert(newJob)
        ensureConfiguration(for: newJob, in: context, anchorDate: anchorDate)
        try context.save()
        return newJob
    }

    static func configuration(
        for job: JobProfile,
        payRates: [PayRateSchedule],
        nightRules: [NightDifferentialRule],
        overtimeRules: [OvertimeRuleSet],
        paySchedules: [PaySchedule],
        templates: [ScheduleTemplate]
    ) -> JobConfiguration {
        let jobPayRates = payRates
            .filter { $0.job?.id == job.id }
            .sorted { $0.effectiveDate < $1.effectiveDate }
        let nightRule = nightRules.first(where: { $0.job?.id == job.id }) ?? NightDifferentialRule(job: job)
        let overtimeRule = overtimeRules.first(where: { $0.job?.id == job.id })
        let paySchedule = paySchedules.first(where: { $0.job?.id == job.id }) ?? PaySchedule(job: job)
        let jobTemplates = templates
            .filter { $0.job?.id == job.id }
            .sorted {
                if $0.weekdayRawValue == $1.weekdayRawValue {
                    return ($0.startHour, $0.startMinute) < ($1.startHour, $1.startMinute)
                }
                return $0.weekdayRawValue < $1.weekdayRawValue
            }

        return JobConfiguration(
            job: job,
            payRates: jobPayRates,
            nightRule: nightRule,
            overtimeRule: overtimeRule,
            paySchedule: paySchedule,
            templates: jobTemplates
        )
    }

    static func nextAccent(after jobs: [JobProfile]) -> JobAccentStyle {
        let usedAccents = Set(jobs.map(\.accent))
        if let next = JobAccentStyle.allCases.first(where: { !usedAccents.contains($0) }) {
            return next
        }
        return JobAccentStyle.allCases[jobs.count % JobAccentStyle.allCases.count]
    }

    private static func ensureConfiguration(
        for job: JobProfile,
        in context: ModelContext,
        anchorDate: Date = .now
    ) {
        let normalizedAnchor = Calendar.current.startOfDay(for: anchorDate)

        if ((try? context.fetch(FetchDescriptor<NightDifferentialRule>())) ?? []).contains(where: { $0.job?.id == job.id }) == false {
            context.insert(NightDifferentialRule(job: job))
        }

        if ((try? context.fetch(FetchDescriptor<OvertimeRuleSet>())) ?? []).contains(where: { $0.job?.id == job.id }) == false {
            context.insert(OvertimeRuleSet(job: job))
        }

        if ((try? context.fetch(FetchDescriptor<PaySchedule>())) ?? []).contains(where: { $0.job?.id == job.id }) == false {
            context.insert(PaySchedule(job: job, anchorDate: normalizedAnchor))
        }
    }

    private static func migrateUnassignedModels(to fallbackJob: JobProfile, in context: ModelContext) throws {
        for shift in try context.fetch(FetchDescriptor<ShiftRecord>()) where shift.job == nil {
            shift.job = fallbackJob
            shift.updatedAt = .now
        }

        for shift in try context.fetch(FetchDescriptor<OpenShiftState>()) where shift.job == nil {
            shift.job = fallbackJob
        }

        for rate in try context.fetch(FetchDescriptor<PayRateSchedule>()) where rate.job == nil {
            rate.job = fallbackJob
        }

        for rule in try context.fetch(FetchDescriptor<NightDifferentialRule>()) where rule.job == nil {
            rule.job = fallbackJob
        }

        for rule in try context.fetch(FetchDescriptor<OvertimeRuleSet>()) where rule.job == nil {
            rule.job = fallbackJob
        }

        for schedule in try context.fetch(FetchDescriptor<PaySchedule>()) where schedule.job == nil {
            schedule.job = fallbackJob
        }

        for template in try context.fetch(FetchDescriptor<ScheduleTemplate>()) where template.job == nil {
            template.job = fallbackJob
        }

        for scheduledShift in try context.fetch(FetchDescriptor<ScheduledShift>()) where scheduledShift.job == nil {
            scheduledShift.job = fallbackJob
            scheduledShift.updatedAt = .now
        }
    }
}
