import Foundation
import SwiftData

enum ShiftControllerError: LocalizedError {
    case missingPayRate(jobName: String?)
    case noOpenShift
    case invalidShiftRange
    case invalidScheduledEnd
    case noJobsSelected
    case futureStart
    case overlappingShift(jobName: String)
    case futureCompletedShift

    var errorDescription: String? {
        switch self {
        case .missingPayRate(let jobName):
            if let jobName, !jobName.isEmpty {
                return "Add an hourly rate for \(jobName) before tracking a shift."
            }
            return "Add an hourly rate before tracking a shift."
        case .noOpenShift:
            return "There isn’t an active shift to end."
        case .invalidShiftRange:
            return "The shift end needs to be later than the start."
        case .invalidScheduledEnd:
            return "The planned end needs to be later than the shift start."
        case .noJobsSelected:
            return "Pick at least one job to start tracking."
        case .futureStart:
            return "An active shift cannot start in the future. Use a scheduled shift for future work."
        case .overlappingShift(let jobName):
            return "This overlaps another shift for \(jobName). Adjust its timing in History before saving."
        case .futureCompletedShift:
            return "A completed shift cannot end in the future. Use Schedule Future Shift for planned work."
        }
    }
}

struct ScheduledShiftAutomationResult {
    var autoCompletedShifts: [ShiftRecord] = []
    var startedShifts: [OpenShiftState] = []
}

private struct SnapshotData {
    let jobs: [JobProfile]
    let completedShifts: [ShiftRecord]
    let openShifts: [OpenShiftState]
    let scheduledShifts: [ScheduledShift]
    let payRates: [PayRateSchedule]
    let nightRules: [NightDifferentialRule]
    let overtimeRules: [OvertimeRuleSet]
    let paySchedules: [PaySchedule]
    let supplements: [JobSupplement]
    let templates: [ScheduleTemplate]
    let taxProfile: TaxProfile
    let preferences: AppPreferences?
}

enum ShiftController {
    private static let defaultAutoEndReminderOffsets = [30, 15, 5]

    @discardableResult
    static func startShift(
        in context: ModelContext,
        at date: Date = .now,
        note: String = "",
        scheduledEndDate: Date? = nil,
        reminderOffsets: [Int] = []
    ) throws -> OpenShiftState {
        let preferredJob = try preferredHomeJob(in: context)
        let startedShifts = try startShifts(
            in: context,
            jobIdentifiers: [preferredJob.id],
            at: date,
            note: note,
            scheduledEndDate: scheduledEndDate,
            reminderOffsets: reminderOffsets
        )

        guard let openShift = startedShifts.first else {
            throw ShiftControllerError.noJobsSelected
        }

        return openShift
    }

    @discardableResult
    static func startShifts(
        in context: ModelContext,
        jobIdentifiers: [UUID],
        at date: Date = .now,
        note: String = "",
        scheduledEndDate: Date? = nil,
        reminderOffsets: [Int] = []
    ) throws -> [OpenShiftState] {
        try DataBootstrapper.seedIfNeeded(in: context)

        guard date <= .now else { throw ShiftControllerError.futureStart }
        if let scheduledEndDate, scheduledEndDate <= date {
            throw ShiftControllerError.invalidScheduledEnd
        }

        let allJobs = try JobService.jobs(in: context)
        let selectedJobs = allJobs.filter { jobIdentifiers.contains($0.id) }
        guard !selectedJobs.isEmpty else {
            throw ShiftControllerError.noJobsSelected
        }

        let payRates = try context.fetch(FetchDescriptor<PayRateSchedule>())
        let nightRules = try context.fetch(FetchDescriptor<NightDifferentialRule>())
        let overtimeRules = try context.fetch(FetchDescriptor<OvertimeRuleSet>())
        let paySchedules = try context.fetch(FetchDescriptor<PaySchedule>())
        let templates = try context.fetch(FetchDescriptor<ScheduleTemplate>())
        let existingOpenShifts = try context.fetch(FetchDescriptor<OpenShiftState>())
        let completedShifts = try context.fetch(FetchDescriptor<ShiftRecord>())

        for job in selectedJobs {
            let configuration = JobService.configuration(
                for: job,
                payRates: payRates,
                nightRules: nightRules,
                overtimeRules: overtimeRules,
                paySchedules: paySchedules,
                templates: templates
            )

            guard !configuration.payRates.isEmpty else {
                throw ShiftControllerError.missingPayRate(jobName: job.displayName)
            }
            let end = scheduledEndDate ?? .distantFuture
            guard !completedShifts.contains(where: {
                $0.job?.id == job.id && $0.startDate < end && $0.endDate > date
            }) else {
                throw ShiftControllerError.overlappingShift(jobName: job.displayName)
            }
        }

        var resolvedShifts: [OpenShiftState] = []

        for job in selectedJobs {
            if let existing = existingOpenShifts.first(where: { $0.job?.id == job.id }) {
                resolvedShifts.append(existing)
                continue
            }

            let openShift = OpenShiftState(job: job, startDate: date, note: note)
            openShift.scheduledEndDate = scheduledEndDate
            openShift.scheduledReminderOffsets = scheduledEndDate == nil ? [] : reminderOffsets
            context.insert(openShift)
            resolvedShifts.append(openShift)
        }

        try PersistenceService.save(context)
        return resolvedShifts.sorted { $0.startDate < $1.startDate }
    }

    @discardableResult
    static func endShift(in context: ModelContext, at date: Date = .now) throws -> ShiftRecord {
        try DataBootstrapper.seedIfNeeded(in: context)
        let openShifts = try context.fetch(
            FetchDescriptor<OpenShiftState>(sortBy: [SortDescriptor(\OpenShiftState.startDate)])
        )
        guard let firstOpenShift = openShifts.first else {
            throw ShiftControllerError.noOpenShift
        }
        return try endShift(in: context, openShift: firstOpenShift, at: date)
    }

    @discardableResult
    static func endShift(
        in context: ModelContext,
        openShift: OpenShiftState,
        at date: Date = .now
    ) throws -> ShiftRecord {
        let endedShifts = try endShifts(in: context, openShiftIdentifiers: [openShift.id], at: date)
        guard let shift = endedShifts.first else {
            throw ShiftControllerError.noOpenShift
        }
        return shift
    }

    @discardableResult
    static func endAllShifts(in context: ModelContext, at date: Date = .now) throws -> [ShiftRecord] {
        try endShifts(in: context, openShiftIdentifiers: nil, at: date)
    }

    @discardableResult
    static func endShifts(
        in context: ModelContext,
        openShiftIdentifiers: [UUID]?,
        at date: Date = .now
    ) throws -> [ShiftRecord] {
        try DataBootstrapper.seedIfNeeded(in: context)

        let openShiftDescriptor = FetchDescriptor<OpenShiftState>(
            sortBy: [SortDescriptor(\OpenShiftState.startDate)]
        )
        let allOpenShifts = try context.fetch(openShiftDescriptor)

        let targetedOpenShifts: [OpenShiftState]
        if let openShiftIdentifiers {
            targetedOpenShifts = allOpenShifts.filter { openShiftIdentifiers.contains($0.id) }
        } else {
            targetedOpenShifts = allOpenShifts
        }

        guard !targetedOpenShifts.isEmpty else {
            throw ShiftControllerError.noOpenShift
        }

        let payRates = try context.fetch(FetchDescriptor<PayRateSchedule>())
        let nightRules = try context.fetch(FetchDescriptor<NightDifferentialRule>())
        let overtimeRules = try context.fetch(FetchDescriptor<OvertimeRuleSet>())
        let paySchedules = try context.fetch(FetchDescriptor<PaySchedule>())
        let templates = try context.fetch(FetchDescriptor<ScheduleTemplate>())
        var completedShifts = try context.fetch(FetchDescriptor<ShiftRecord>())
        var endedShifts: [ShiftRecord] = []

        // Validate the entire selection before inserting or deleting anything.
        for openShift in targetedOpenShifts {
            let end = min(date, openShift.scheduledEndDate ?? date)
            guard end > openShift.startDate else {
                throw ShiftControllerError.invalidShiftRange
            }
            guard payRates.contains(where: { $0.job?.id == openShift.job?.id }) else {
                throw ShiftControllerError.missingPayRate(jobName: openShift.job?.displayName)
            }
            if completedShifts.contains(where: {
                $0.job?.id == openShift.job?.id && $0.startDate < end && $0.endDate > openShift.startDate
            }) {
                throw ShiftControllerError.overlappingShift(jobName: openShift.job?.displayName ?? "this job")
            }
        }

        for openShift in targetedOpenShifts {
            let job = try resolvedJob(for: openShift.job?.id, in: context)
            let configuration = JobService.configuration(
                for: job,
                payRates: payRates,
                nightRules: nightRules,
                overtimeRules: overtimeRules,
                paySchedules: paySchedules,
                templates: templates
            )

            guard !configuration.payRates.isEmpty else {
                throw ShiftControllerError.missingPayRate(jobName: job.displayName)
            }

            let end = min(date, openShift.scheduledEndDate ?? date)
            let jobHistoricalShifts = completedShifts.filter { $0.job?.id == job.id }
            let breakdown = EarningsEngine.calculate(
                start: openShift.startDate,
                end: end,
                payRates: configuration.payRates,
                nightRule: configuration.nightRule,
                overtimeRule: configuration.overtimeRule,
                historicalShifts: jobHistoricalShifts
            )

            let shift = ShiftRecord(
                job: job,
                startDate: openShift.startDate,
                endDate: end,
                note: openShift.note,
                breakdown: breakdown
            )

            context.insert(shift)
            context.delete(openShift)
            completedShifts.append(shift)
            endedShifts.append(shift)
        }

        for shift in endedShifts {
            if let job = shift.job {
                try recalculateOvertime(in: context, for: job, affectedStart: shift.startDate, affectedEnd: shift.endDate)
            }
        }
        try PersistenceService.save(context)
        return endedShifts.sorted { $0.startDate < $1.startDate }
    }

    static func saveManualShift(
        in context: ModelContext,
        editing shift: ShiftRecord?,
        job: JobProfile,
        startDate: Date,
        endDate: Date,
        note: String = ""
    ) throws {
        try DataBootstrapper.seedIfNeeded(in: context)
        guard endDate > startDate else {
            throw ShiftControllerError.invalidShiftRange
        }
        let oldJob = shift?.job
        let oldStart = shift?.startDate
        let oldEnd = shift?.endDate
        guard endDate <= .now else { throw ShiftControllerError.futureCompletedShift }

        let payRates = try context.fetch(FetchDescriptor<PayRateSchedule>())
        let nightRules = try context.fetch(FetchDescriptor<NightDifferentialRule>())
        let overtimeRules = try context.fetch(FetchDescriptor<OvertimeRuleSet>())
        let paySchedules = try context.fetch(FetchDescriptor<PaySchedule>())
        let templates = try context.fetch(FetchDescriptor<ScheduleTemplate>())
        let configuration = JobService.configuration(
            for: job,
            payRates: payRates,
            nightRules: nightRules,
            overtimeRules: overtimeRules,
            paySchedules: paySchedules,
            templates: templates
        )

        guard !configuration.payRates.isEmpty else {
            throw ShiftControllerError.missingPayRate(jobName: job.displayName)
        }

        let existingShifts = try context.fetch(FetchDescriptor<ShiftRecord>())
            .filter { existing in
                guard let shift else { return existing.job?.id == job.id }
                return existing.id != shift.id && existing.job?.id == job.id
            }

        guard !existingShifts.contains(where: { $0.startDate < endDate && $0.endDate > startDate }) else {
            throw ShiftControllerError.overlappingShift(jobName: job.displayName)
        }
        let activeShifts = try context.fetch(FetchDescriptor<OpenShiftState>())
        guard !activeShifts.contains(where: {
            $0.job?.id == job.id && $0.startDate < endDate && ($0.scheduledEndDate ?? .distantFuture) > startDate
        }) else {
            throw ShiftControllerError.overlappingShift(jobName: job.displayName)
        }

        let breakdown = EarningsEngine.calculate(
            start: startDate,
            end: endDate,
            payRates: configuration.payRates,
            nightRule: configuration.nightRule,
            overtimeRule: configuration.overtimeRule,
            historicalShifts: existingShifts
        )

        if let shift {
            shift.job = job
            shift.startDate = startDate
            shift.endDate = endDate
            shift.note = note
            shift.apply(breakdown)
        } else {
            context.insert(
                ShiftRecord(
                    job: job,
                    startDate: startDate,
                    endDate: endDate,
                    note: note,
                    breakdown: breakdown
                )
            )
        }

        if let oldJob, let oldStart, let oldEnd {
            try recalculateOvertime(in: context, for: oldJob, affectedStart: oldStart, affectedEnd: oldEnd)
        }
        try recalculateOvertime(in: context, for: job, affectedStart: startDate, affectedEnd: endDate)
        try PersistenceService.save(context)
    }

    static func saveScheduledShift(
        in context: ModelContext,
        editing shift: ScheduledShift?,
        job: JobProfile,
        startDate: Date,
        endDate: Date,
        note: String = ""
    ) throws {
        try DataBootstrapper.seedIfNeeded(in: context)
        guard endDate > startDate else {
            throw ShiftControllerError.invalidShiftRange
        }

        let existing = try context.fetch(FetchDescriptor<ScheduledShift>())
        let completed = try context.fetch(FetchDescriptor<ShiftRecord>())
        guard !existing.contains(where: {
            $0.id != shift?.id && $0.job?.id == job.id && $0.startDate < endDate && $0.endDate > startDate
        }), !completed.contains(where: {
            $0.job?.id == job.id && $0.startDate < endDate && $0.endDate > startDate
        }) else {
            throw ShiftControllerError.overlappingShift(jobName: job.displayName)
        }

        if let shift {
            shift.job = job
            shift.startDate = startDate
            shift.endDate = endDate
            shift.note = note
            shift.updatedAt = .now
        } else {
            context.insert(ScheduledShift(job: job, startDate: startDate, endDate: endDate, note: note))
        }

        try PersistenceService.save(context)
    }

    static func deleteShift(_ shift: ShiftRecord, in context: ModelContext) throws {
        let job = shift.job
        let start = shift.startDate
        let end = shift.endDate
        context.delete(shift)
        if let job {
            try recalculateOvertime(in: context, for: job, affectedStart: start, affectedEnd: end)
        }
        try PersistenceService.save(context)
    }

    /// Backdating, moving, or deleting history changes later overtime in the
    /// affected workweeks. Leave unrelated stored pay history untouched.
    private static func recalculateOvertime(
        in context: ModelContext,
        for job: JobProfile,
        affectedStart: Date,
        affectedEnd: Date
    ) throws {
        let configuration = JobService.configuration(
            for: job,
            payRates: try context.fetch(FetchDescriptor<PayRateSchedule>()),
            nightRules: try context.fetch(FetchDescriptor<NightDifferentialRule>()),
            overtimeRules: try context.fetch(FetchDescriptor<OvertimeRuleSet>()),
            paySchedules: try context.fetch(FetchDescriptor<PaySchedule>()),
            templates: []
        )
        guard configuration.overtimeRule?.isEnabled == true, !configuration.payRates.isEmpty else { return }
        let calendar = configuration.overtimeRule?.workCalendar(.current) ?? .current
        let firstWeek = calendar.dateInterval(of: .weekOfYear, for: affectedStart)
        let lastWeek = calendar.dateInterval(of: .weekOfYear, for: max(affectedStart, affectedEnd.addingTimeInterval(-0.001)))
        let start = firstWeek?.start ?? affectedStart
        let end = lastWeek?.end ?? affectedEnd
        let records = try context.fetch(FetchDescriptor<ShiftRecord>(sortBy: [SortDescriptor(\ShiftRecord.startDate)]))
            .filter { $0.job?.id == job.id }
        for record in records where record.startDate < end && record.endDate > start {
            let breakdown = EarningsEngine.calculate(
                start: record.startDate, end: record.endDate,
                payRates: configuration.payRates, nightRule: configuration.nightRule,
                overtimeRule: configuration.overtimeRule,
                historicalShifts: records.filter { $0.id != record.id },
                pricedSegments: record.earningsSegments, calendar: calendar
            )
            record.apply(breakdown)
        }
    }

    static func deleteScheduledShift(_ shift: ScheduledShift, in context: ModelContext) throws {
        context.delete(shift)
        try PersistenceService.save(context)
    }

    static func updateOpenShift(
        in context: ModelContext,
        editing openShift: OpenShiftState? = nil,
        startDate: Date,
        scheduledEndDate: Date?,
        reminderOffsets: [Int]
    ) throws {
        let targetOpenShift: OpenShiftState
        if let openShift {
            targetOpenShift = openShift
        } else if let existing = try DataBootstrapper.first(OpenShiftState.self, in: context) {
            targetOpenShift = existing
        } else {
            throw ShiftControllerError.noOpenShift
        }

        if let scheduledEndDate, scheduledEndDate <= startDate {
            throw ShiftControllerError.invalidScheduledEnd
        }

        guard startDate <= .now else { throw ShiftControllerError.futureStart }
        let completed = try context.fetch(FetchDescriptor<ShiftRecord>())
        let end = scheduledEndDate ?? .distantFuture
        guard !completed.contains(where: {
            $0.job?.id == targetOpenShift.job?.id && $0.startDate < end && $0.endDate > startDate
        }) else {
            throw ShiftControllerError.overlappingShift(jobName: targetOpenShift.job?.displayName ?? "this job")
        }

        targetOpenShift.startDate = startDate
        targetOpenShift.scheduledEndDate = scheduledEndDate
        targetOpenShift.scheduledReminderOffsets = scheduledEndDate == nil ? [] : reminderOffsets
        try PersistenceService.save(context)
    }

    @discardableResult
    static func autoEndShiftsIfNeeded(in context: ModelContext, at date: Date = .now) throws -> [ShiftRecord] {
        let descriptor = FetchDescriptor<OpenShiftState>(
            sortBy: [SortDescriptor(\OpenShiftState.scheduledEndDate)]
        )
        let dueOpenShifts = try context.fetch(descriptor).filter {
            guard let scheduledEndDate = $0.scheduledEndDate else { return false }
            return date >= scheduledEndDate
        }

        guard !dueOpenShifts.isEmpty else {
            return []
        }

        var endedShifts: [ShiftRecord] = []
        for openShift in dueOpenShifts {
            guard let scheduledEndDate = openShift.scheduledEndDate else { continue }
            endedShifts.append(try endShift(in: context, openShift: openShift, at: scheduledEndDate))
        }
        return endedShifts
    }

    static func reconcileScheduledShifts(in context: ModelContext, at date: Date = .now) throws -> ScheduledShiftAutomationResult {
        let scheduledDescriptor = FetchDescriptor<ScheduledShift>(
            sortBy: [SortDescriptor(\ScheduledShift.startDate)]
        )
        let scheduledShifts = try context.fetch(scheduledDescriptor)
        guard scheduledShifts.contains(where: { $0.startDate <= date }) else {
            return ScheduledShiftAutomationResult()
        }
        try DataBootstrapper.seedIfNeeded(in: context)
        let allJobs = try JobService.jobs(in: context)

        let payRates = try context.fetch(FetchDescriptor<PayRateSchedule>())
        let nightRules = try context.fetch(FetchDescriptor<NightDifferentialRule>())
        let overtimeRules = try context.fetch(FetchDescriptor<OvertimeRuleSet>())
        let paySchedules = try context.fetch(FetchDescriptor<PaySchedule>())
        let templates = try context.fetch(FetchDescriptor<ScheduleTemplate>())
        let existingOpenShifts = try context.fetch(FetchDescriptor<OpenShiftState>())
        var activeJobIdentifiers = Set(existingOpenShifts.compactMap { $0.job?.id })
        var completedShifts = try context.fetch(
            FetchDescriptor<ShiftRecord>(sortBy: [SortDescriptor(\ShiftRecord.startDate)])
        )
        var result = ScheduledShiftAutomationResult()
        var discardedArchivedSchedules = false

        // Preflight every due schedule so a later missing rate or conflict cannot
        // leave earlier schedules partly converted in the shared context.
        let dueSchedules = scheduledShifts.filter { $0.startDate <= date && $0.job?.isArchived != true }
        for scheduled in dueSchedules {
            guard scheduled.endDate > scheduled.startDate else { throw ShiftControllerError.invalidShiftRange }
            guard let job = scheduled.job ?? allJobs.first else { continue }
            guard payRates.contains(where: { $0.job?.id == job.id }) else {
                throw ShiftControllerError.missingPayRate(jobName: job.displayName)
            }
            let overlapsCompleted = completedShifts.contains {
                $0.job?.id == job.id && $0.startDate < scheduled.endDate && $0.endDate > scheduled.startDate
            }
            let overlapsOpen = existingOpenShifts.contains {
                $0.job?.id == job.id && $0.startDate < scheduled.endDate && ($0.scheduledEndDate ?? .distantFuture) > scheduled.startDate
            }
            let overlapsSchedule = dueSchedules.contains {
                $0.id != scheduled.id && $0.job?.id == job.id && $0.startDate < scheduled.endDate && $0.endDate > scheduled.startDate
            }
            guard !overlapsCompleted, !overlapsOpen, !overlapsSchedule else {
                throw ShiftControllerError.overlappingShift(jobName: job.displayName)
            }
        }

        for scheduledShift in scheduledShifts {
            guard scheduledShift.startDate <= date else {
                break
            }

            let job: JobProfile?
            if let scheduledJob = scheduledShift.job {
                guard !scheduledJob.isArchived,
                      let activeJob = allJobs.first(where: { $0.id == scheduledJob.id }) else {
                    context.delete(scheduledShift)
                    discardedArchivedSchedules = true
                    continue
                }
                job = activeJob
            } else {
                job = allJobs.first
            }

            guard let job else { continue }

            let configuration = JobService.configuration(
                for: job,
                payRates: payRates,
                nightRules: nightRules,
                overtimeRules: overtimeRules,
                paySchedules: paySchedules,
                templates: templates
            )

            if scheduledShift.endDate <= date {
                guard !configuration.payRates.isEmpty else {
                    throw ShiftControllerError.missingPayRate(jobName: job.displayName)
                }

                let completedShift = makeShiftRecord(
                    from: scheduledShift,
                    configuration: configuration,
                    existingShifts: completedShifts.filter { $0.job?.id == job.id }
                )

                context.insert(completedShift)
                completedShifts.append(completedShift)
                result.autoCompletedShifts.append(completedShift)
                context.delete(scheduledShift)
                continue
            }

            guard !activeJobIdentifiers.contains(job.id) else {
                continue
            }

            guard !configuration.payRates.isEmpty else {
                throw ShiftControllerError.missingPayRate(jobName: job.displayName)
            }

            let startedShift = OpenShiftState(job: job, startDate: scheduledShift.startDate, note: scheduledShift.note)
            startedShift.scheduledEndDate = scheduledShift.endDate
            startedShift.scheduledReminderOffsets = defaultAutoEndReminderOffsets
            context.insert(startedShift)
            context.delete(scheduledShift)
            result.startedShifts.append(startedShift)
            activeJobIdentifiers.insert(job.id)
        }

        if discardedArchivedSchedules || !result.autoCompletedShifts.isEmpty || !result.startedShifts.isEmpty {
            for shift in result.autoCompletedShifts {
                if let job = shift.job {
                    try recalculateOvertime(in: context, for: job, affectedStart: shift.startDate, affectedEnd: shift.endDate)
                }
            }
            try PersistenceService.save(context)
        }

        return result
    }

    static func summarySnapshot(in context: ModelContext, at date: Date = .now, calendar: Calendar = .current) throws -> SummarySnapshot {
        let snapshotData = try loadSnapshotData(in: context)

        let jobSummaries = snapshotData.jobs.filter { !$0.isArchived }.map { job in
            buildJobSummary(for: job, from: snapshotData, at: date, calendar: calendar)
        }

        let combinedBreakdown = combineBreakdowns(jobSummaries.compactMap(\.currentBreakdown))
        let combinedCurrentGross = combinedBreakdown?.grossEarnings ?? 0
        let observedIncome = TaxEstimator.annualizedGrossIncome(
            currentGross: combinedCurrentGross,
            yearToDateGrossExcludingCurrentShift: AggregationService.totalGross(
                for: snapshotData.completedShifts,
                in: DateInterval(start: calendar.dateInterval(of: .year, for: date)?.start ?? date, end: date)
            ),
            currentHourlyRate: 0, templates: [], today: date, calendar: calendar, fallbackExpectedWeeklyHours: 0
        )
        let combinedAnnualizedGrossIncome = max(observedIncome, jobSummaries.reduce(0) { $0 + $1.annualizedGrossIncome })
        let combinedAnnualizedTaxableSupplementIncome = jobSummaries.reduce(0) { $0 + $1.annualizedTaxableSupplementIncome }
        let combinedPayFrequency = combinedPayFrequency(from: snapshotData, jobSummaries: jobSummaries)
        let combinedAnnualExtraWithholding = TaxEstimator.annualExtraWithholding(
            payFrequency: combinedPayFrequency,
            taxProfile: snapshotData.taxProfile
        )
        let combinedTaxEstimate = TaxEstimator.estimate(
            currentGross: combinedCurrentGross,
            annualizedGrossIncome: combinedAnnualizedGrossIncome,
            annualExtraWithholding: combinedAnnualExtraWithholding,
            taxProfile: snapshotData.taxProfile,
            payFrequency: combinedPayFrequency
        )
        let combinedEffectiveEstimate = TaxEstimator.estimate(
            currentGross: 0,
            annualizedGrossIncome: combinedAnnualizedGrossIncome,
            annualizedTaxableSupplementalIncome: combinedAnnualizedTaxableSupplementIncome,
            annualExtraWithholding: combinedAnnualExtraWithholding,
            taxProfile: snapshotData.taxProfile,
            payFrequency: combinedPayFrequency
        )
        let payPeriodAggregation = combinedPayPeriodAggregation(for: jobSummaries)
        let payPeriodGross = payPeriodAggregation == .unified
            ? jobSummaries.reduce(0) { $0 + $1.rollup.payPeriodGross }
            : 0
        let payPeriodHours = payPeriodAggregation == .unified
            ? jobSummaries.reduce(0) { $0 + $1.rollup.payPeriodHours }
            : 0
        let payPeriodNightPremium = payPeriodAggregation == .unified
            ? jobSummaries.reduce(0) { $0 + $1.rollup.payPeriodNightPremium }
            : 0
        let projectedGross = payPeriodAggregation == .unified
            ? jobSummaries.reduce(0) { $0 + $1.rollup.projectedGross }
            : 0
        let combinedAllTimeGross = AggregationService.totalGross(for: snapshotData.completedShifts) + combinedCurrentGross
        let payPeriodSupplementTotals = payPeriodAggregation == .unified
            ? combinedSupplementTotals(jobSummaries.map(\.rollup.payPeriodEffective))
            : .zero
        let activeSupplementTotals = combinedSupplementTotals(jobSummaries.map(\.rollup.activeEffective))
        let projectedSupplementTotals = payPeriodAggregation == .unified
            ? combinedSupplementTotals(jobSummaries.map(\.rollup.projectedEffective))
            : .zero
        var allTimeSupplementTotals = combinedSupplementTotals(jobSummaries.map(\.rollup.allTimeEffective))
        for job in snapshotData.jobs where job.isArchived {
            let supplements = snapshotData.supplements.filter { $0.job?.id == job.id }
            if let window = SupplementAllocationService.lifetimeWindow(through: min(date, job.archivedAt ?? job.updatedAt), supplements: supplements, calendar: calendar) {
                let totals = SupplementAllocationService.totals(for: SupplementAllocationService.allocations(for: supplements, within: window, calendar: calendar))
                allTimeSupplementTotals.total += totals.total
                allTimeSupplementTotals.taxableTotal += totals.taxableTotal
                allTimeSupplementTotals.nonTaxableTotal += totals.nonTaxableTotal
            }
        }
        let combinedAllTimeHours = AggregationService.totalHours(for: snapshotData.completedShifts) + (combinedBreakdown?.totalHours ?? 0)
        let combinedRollup = SummaryRollup(
            activeShiftCount: snapshotData.openShifts.count,
            scheduledShiftCount: snapshotData.scheduledShifts.count,
            completedShiftCount: snapshotData.completedShifts.count,
            activeGross: combinedCurrentGross,
            activeTakeHome: combinedTaxEstimate.currentShiftNetEstimate,
            activeEffective: SupplementAllocationService.effectiveSnapshot(
                regularGross: combinedCurrentGross,
                supplementTotals: activeSupplementTotals,
                estimate: combinedEffectiveEstimate,
                hours: combinedBreakdown?.totalHours ?? 0
            ),
            payPeriodAggregation: payPeriodAggregation,
            payPeriodGross: payPeriodGross,
            payPeriodTakeHome: payPeriodAggregation == .unified
                ? TaxEstimator.estimatedTakeHome(for: payPeriodGross, estimate: combinedTaxEstimate)
                : 0,
            payPeriodHours: payPeriodHours,
            payPeriodNightPremium: payPeriodNightPremium,
            projectedGross: projectedGross,
            projectedTakeHome: payPeriodAggregation == .unified
                ? TaxEstimator.estimatedTakeHome(for: projectedGross, estimate: combinedTaxEstimate)
                : 0,
            allTimeGross: combinedAllTimeGross,
            allTimeTakeHome: TaxEstimator.estimatedTakeHome(for: combinedAllTimeGross, estimate: combinedTaxEstimate),
            allTimeHours: combinedAllTimeHours,
            weeklyGross: jobSummaries.reduce(0) { $0 + $1.rollup.weeklyGross },
            totalNightPremium: AggregationService.totalNightPremium(for: snapshotData.completedShifts) + (combinedBreakdown?.nightPremiumEarnings ?? 0),
            totalOvertimePremium: AggregationService.totalOvertimePremium(for: snapshotData.completedShifts) + (combinedBreakdown?.overtimePremiumEarnings ?? 0),
            totalOvertimeHours: AggregationService.totalOvertimeHours(for: snapshotData.completedShifts) + (combinedBreakdown?.overtimeHours ?? 0),
            averageShiftGross: AggregationService.averageShiftGross(for: snapshotData.completedShifts),
            averageShiftHours: AggregationService.averageShiftHours(for: snapshotData.completedShifts),
            highestShiftGross: AggregationService.highestShift(in: snapshotData.completedShifts)?.grossEarnings ?? 0,
            currentBlendedRate: combinedBreakdown?.effectiveRate ?? 0,
            hasSupplementConfiguration: allTimeSupplementTotals.total > 0 || jobSummaries.contains(where: { $0.rollup.hasSupplementConfiguration }),
            payPeriodEffective: payPeriodAggregation == .unified
                ? SupplementAllocationService.effectiveSnapshot(
                    regularGross: payPeriodGross,
                    supplementTotals: payPeriodSupplementTotals,
                    estimate: combinedEffectiveEstimate,
                    hours: payPeriodHours
                )
                : .zero,
            projectedEffective: payPeriodAggregation == .unified
                ? SupplementAllocationService.effectiveSnapshot(
                    regularGross: projectedGross,
                    supplementTotals: projectedSupplementTotals,
                    estimate: combinedEffectiveEstimate,
                    hours: 0
                )
                : .zero,
            allTimeEffective: SupplementAllocationService.effectiveSnapshot(
                regularGross: combinedAllTimeGross,
                supplementTotals: allTimeSupplementTotals,
                estimate: combinedEffectiveEstimate,
                hours: combinedAllTimeHours
            )
        )

        let projectedConfidenceLabel: String
        if payPeriodAggregation == .variesByJob {
            projectedConfidenceLabel = "Varies by job"
        } else if jobSummaries.contains(where: { $0.rollup.projectedGross > $0.rollup.payPeriodGross + 0.001 }) {
            projectedConfidenceLabel = "Projected from job schedules"
        } else {
            projectedConfidenceLabel = "Earned so far"
        }

        return SummarySnapshot(
            combined: combinedRollup,
            projectedConfidenceLabel: projectedConfidenceLabel,
            jobs: jobSummaries
        )
    }

    static func dashboardSnapshot(in context: ModelContext, at date: Date = .now, calendar: Calendar = .current) throws -> DashboardSnapshot {
        let summary = try summarySnapshot(in: context, at: date, calendar: calendar)
        let openShifts = try context.fetch(
            FetchDescriptor<OpenShiftState>(sortBy: [SortDescriptor(\OpenShiftState.startDate)])
        )
        let jobs = try JobService.jobs(in: context)

        let activeJobs = openShifts.compactMap { openShift -> ActiveJobSnapshot? in
            guard
                let jobIdentifier = openShift.job?.id,
                let summaryJob = summary.jobs.first(where: { $0.id == jobIdentifier }),
                let currentBreakdown = summaryJob.currentBreakdown
            else {
                return nil
            }

            let job = jobs.first(where: { $0.id == jobIdentifier }) ?? openShift.job
            return ActiveJobSnapshot(
                id: summaryJob.id,
                name: summaryJob.name,
                accent: job?.accent ?? summaryJob.accent,
                startDate: openShift.startDate,
                scheduledEndDate: openShift.scheduledEndDate,
                currentBreakdown: currentBreakdown,
                currentGross: summaryJob.rollup.activeGross,
                currentTakeHome: summaryJob.rollup.activeTakeHome,
                currentEffectiveGross: summaryJob.rollup.activeEffective.effectiveGross,
                currentEffectiveTakeHome: summaryJob.rollup.activeEffective.effectiveTakeHome
            )
        }

        return DashboardSnapshot(
            currentBreakdown: combineBreakdowns(activeJobs.map(\.currentBreakdown)),
            activeJobs: activeJobs,
            hasSupplementConfiguration: summary.combined.hasSupplementConfiguration,
            currentGross: summary.combined.activeGross,
            currentTakeHome: summary.combined.activeTakeHome,
            currentEffectiveGross: summary.combined.activeEffective.effectiveGross,
            currentEffectiveTakeHome: summary.combined.activeEffective.effectiveTakeHome,
            payPeriodAggregation: summary.combined.payPeriodAggregation,
            payPeriodGross: summary.combined.payPeriodGross,
            payPeriodTakeHome: summary.combined.payPeriodTakeHome,
            payPeriodEffectiveGross: summary.combined.payPeriodEffective.effectiveGross,
            payPeriodEffectiveTakeHome: summary.combined.payPeriodEffective.effectiveTakeHome,
            payPeriodHours: summary.combined.payPeriodHours,
            payPeriodNightPremium: summary.combined.payPeriodNightPremium,
            allTimeGross: summary.combined.allTimeGross,
            allTimeTakeHome: summary.combined.allTimeTakeHome,
            allTimeEffectiveGross: summary.combined.allTimeEffective.effectiveGross,
            allTimeEffectiveTakeHome: summary.combined.allTimeEffective.effectiveTakeHome,
            projectedPaycheckGross: summary.combined.projectedGross,
            projectedPaycheckTakeHome: summary.combined.projectedTakeHome,
            projectedPaycheckEffectiveGross: summary.combined.projectedEffective.effectiveGross,
            projectedPaycheckEffectiveTakeHome: summary.combined.projectedEffective.effectiveTakeHome,
            projectedConfidenceLabel: summary.projectedConfidenceLabel,
            allTimeHours: summary.combined.allTimeHours
        )
    }

    private static func loadSnapshotData(in context: ModelContext) throws -> SnapshotData {
        SnapshotData(
            jobs: try JobService.jobs(in: context, includeArchived: true),
            completedShifts: try context.fetch(FetchDescriptor<ShiftRecord>()),
            openShifts: try context.fetch(FetchDescriptor<OpenShiftState>()).filter { $0.job?.isArchived != true },
            scheduledShifts: try context.fetch(FetchDescriptor<ScheduledShift>()).filter { $0.job?.isArchived != true },
            payRates: try context.fetch(FetchDescriptor<PayRateSchedule>()),
            nightRules: try context.fetch(FetchDescriptor<NightDifferentialRule>()),
            overtimeRules: try context.fetch(FetchDescriptor<OvertimeRuleSet>()),
            paySchedules: try context.fetch(FetchDescriptor<PaySchedule>()),
            supplements: try context.fetch(FetchDescriptor<JobSupplement>()),
            templates: try context.fetch(FetchDescriptor<ScheduleTemplate>()).filter { $0.job?.isArchived != true },
            taxProfile: try DataBootstrapper.first(TaxProfile.self, in: context) ?? TaxProfile(),
            preferences: try DataBootstrapper.first(AppPreferences.self, in: context)
        )
    }

    private static func buildJobSummary(
        for job: JobProfile,
        from snapshotData: SnapshotData,
        at date: Date,
        calendar: Calendar
    ) -> JobSummarySnapshot {
        let configuration = JobService.configuration(
            for: job,
            payRates: snapshotData.payRates,
            nightRules: snapshotData.nightRules,
            overtimeRules: snapshotData.overtimeRules,
            paySchedules: snapshotData.paySchedules,
            supplements: snapshotData.supplements,
            templates: snapshotData.templates
        )

        let completedShifts = snapshotData.completedShifts.filter { $0.job?.id == job.id }
        let openShifts = snapshotData.openShifts
            .filter { $0.job?.id == job.id }
            .sorted { $0.startDate < $1.startDate }
        let scheduledShifts = snapshotData.scheduledShifts
            .filter { $0.job?.id == job.id }
            .sorted { $0.startDate < $1.startDate }

        let currentBreakdown = combineBreakdowns(
            openShifts.map {
                EarningsEngine.calculate(
                    start: $0.startDate,
                    end: min(date, $0.scheduledEndDate ?? date),
                    payRates: configuration.payRates,
                    nightRule: configuration.nightRule,
                    overtimeRule: configuration.overtimeRule,
                    historicalShifts: completedShifts,
                    calendar: calendar
                )
            }
        )

        let payPeriodInterval = ProjectionEngine.payPeriodInterval(for: date, schedule: configuration.paySchedule, calendar: calendar)
        let payPeriodWindow = DateInterval(start: payPeriodInterval.start, end: min(payPeriodInterval.end, date))
        let payPeriodSupplementTotals = SupplementAllocationService.totals(
            for: SupplementAllocationService.allocations(
                for: configuration.supplements,
                within: payPeriodWindow,
                calendar: calendar
            )
        )
        let projectedSupplementTotals = SupplementAllocationService.totals(
            for: SupplementAllocationService.allocations(
                for: configuration.supplements,
                within: payPeriodInterval,
                calendar: calendar
            )
        )
        let allTimeSupplementTotals = SupplementAllocationService.lifetimeWindow(
            through: date,
            supplements: configuration.supplements,
            calendar: calendar
        )
        .map {
            SupplementAllocationService.totals(
                for: SupplementAllocationService.allocations(
                    for: configuration.supplements,
                    within: $0,
                    calendar: calendar
                )
            )
        } ?? .zero

        let yearInterval = calendar.dateInterval(of: .year, for: date)
        let ytdGrossCompleted = AggregationService.totalGross(for: completedShifts, in: yearInterval)
        let currentRate = currentBreakdown?.effectiveRate ?? EarningsEngine.payRate(at: date, payRates: configuration.payRates)
        let annualizedGrossIncome = TaxEstimator.annualizedGrossIncome(
            currentGross: currentBreakdown?.grossEarnings ?? 0,
            yearToDateGrossExcludingCurrentShift: ytdGrossCompleted,
            currentHourlyRate: currentRate,
            templates: configuration.templates,
            today: date,
            calendar: calendar,
            fallbackExpectedWeeklyHours: snapshotData.taxProfile.expectedWeeklyHours
        )
        let annualizedTaxableSupplementIncome = SupplementAllocationService.annualizedTaxableIncome(
            asOf: date,
            supplements: configuration.supplements,
            calendar: calendar
        )
        let taxEstimate = TaxEstimator.estimate(
            currentGross: currentBreakdown?.grossEarnings ?? 0,
            annualizedGrossIncome: annualizedGrossIncome,
            annualExtraWithholding: TaxEstimator.annualExtraWithholding(
                payFrequency: configuration.paySchedule.frequency,
                taxProfile: snapshotData.taxProfile
            ),
            taxProfile: snapshotData.taxProfile,
            payFrequency: configuration.paySchedule.frequency
        )
        let effectiveTaxEstimate = TaxEstimator.estimate(
            currentGross: 0,
            annualizedGrossIncome: annualizedGrossIncome,
            annualizedTaxableSupplementalIncome: annualizedTaxableSupplementIncome,
            annualExtraWithholding: TaxEstimator.annualExtraWithholding(
                payFrequency: configuration.paySchedule.frequency,
                taxProfile: snapshotData.taxProfile
            ),
            taxProfile: snapshotData.taxProfile,
            payFrequency: configuration.paySchedule.frequency
        )

        let takeHomeRate = 1 - taxEstimate.estimatedNetRate
        let projection = ProjectionEngine.projectedPaycheck(
            asOf: date,
            shifts: completedShifts,
            openShiftBreakdown: currentBreakdown,
            paySchedule: configuration.paySchedule,
            payRates: configuration.payRates,
            templates: configuration.templates,
            takeHomeRate: takeHomeRate,
            configuration: configuration,
            openShifts: openShifts,
            scheduledShifts: scheduledShifts,
            calendar: calendar
        )

        let weeklyInterval = calendar.dateInterval(of: .weekOfYear, for: date)
        func allocatedCompleted(in interval: DateInterval) -> [EarningsBreakdown] {
            completedShifts.map {
                ShiftEarningsAllocation.completed($0, within: interval, configuration: configuration, historicalShifts: completedShifts, calendar: calendar)
            }
        }
        func allocatedOpen(in interval: DateInterval) -> [EarningsBreakdown] {
            openShifts.map {
                ShiftEarningsAllocation.partial(start: $0.startDate, end: min(date, $0.scheduledEndDate ?? date), within: interval, configuration: configuration, historicalShifts: completedShifts, calendar: calendar)
            }
        }
        let periodNightPremium = allocatedCompleted(in: payPeriodWindow).reduce(0) { $0 + $1.nightPremiumEarnings }
            + allocatedOpen(in: payPeriodWindow).reduce(0) { $0 + $1.nightPremiumEarnings }
        let weeklyGross = weeklyInterval.map { interval in
            allocatedCompleted(in: interval).reduce(0) { $0 + $1.grossEarnings }
                + allocatedOpen(in: interval).reduce(0) { $0 + $1.grossEarnings }
        } ?? 0
        let allTimeGross = AggregationService.totalGross(for: completedShifts) + (currentBreakdown?.grossEarnings ?? 0)
        let allTimeHours = AggregationService.totalHours(for: completedShifts) + (currentBreakdown?.totalHours ?? 0)
        let activeSupplementTotals = proratedSupplementTotals(
            currentHours: currentBreakdown?.totalHours ?? 0,
            payPeriodHours: projection.payPeriodHours,
            supplementTotals: payPeriodSupplementTotals
        )

        let rollup = SummaryRollup(
            activeShiftCount: openShifts.count,
            scheduledShiftCount: scheduledShifts.count,
            completedShiftCount: completedShifts.count,
            activeGross: currentBreakdown?.grossEarnings ?? 0,
            activeTakeHome: taxEstimate.currentShiftNetEstimate,
            activeEffective: SupplementAllocationService.effectiveSnapshot(
                regularGross: currentBreakdown?.grossEarnings ?? 0,
                supplementTotals: activeSupplementTotals,
                estimate: effectiveTaxEstimate,
                hours: currentBreakdown?.totalHours ?? 0
            ),
            payPeriodAggregation: .unified,
            payPeriodGross: projection.payPeriodGross,
            payPeriodTakeHome: TaxEstimator.estimatedTakeHome(for: projection.payPeriodGross, estimate: taxEstimate),
            payPeriodHours: projection.payPeriodHours,
            payPeriodNightPremium: periodNightPremium,
            projectedGross: projection.projectedGross,
            projectedTakeHome: projection.projectedTakeHome,
            allTimeGross: allTimeGross,
            allTimeTakeHome: TaxEstimator.estimatedTakeHome(for: allTimeGross, estimate: taxEstimate),
            allTimeHours: allTimeHours,
            weeklyGross: weeklyGross,
            totalNightPremium: AggregationService.totalNightPremium(for: completedShifts) + (currentBreakdown?.nightPremiumEarnings ?? 0),
            totalOvertimePremium: AggregationService.totalOvertimePremium(for: completedShifts) + (currentBreakdown?.overtimePremiumEarnings ?? 0),
            totalOvertimeHours: AggregationService.totalOvertimeHours(for: completedShifts) + (currentBreakdown?.overtimeHours ?? 0),
            averageShiftGross: AggregationService.averageShiftGross(for: completedShifts),
            averageShiftHours: AggregationService.averageShiftHours(for: completedShifts),
            highestShiftGross: AggregationService.highestShift(in: completedShifts)?.grossEarnings ?? 0,
            currentBlendedRate: currentBreakdown?.effectiveRate ?? currentRate,
            hasSupplementConfiguration: !configuration.supplements.isEmpty,
            payPeriodEffective: SupplementAllocationService.effectiveSnapshot(
                regularGross: projection.payPeriodGross,
                supplementTotals: payPeriodSupplementTotals,
                estimate: effectiveTaxEstimate,
                hours: projection.payPeriodHours
            ),
            projectedEffective: SupplementAllocationService.effectiveSnapshot(
                regularGross: projection.projectedGross,
                supplementTotals: projectedSupplementTotals,
                estimate: effectiveTaxEstimate,
                hours: 0
            ),
            allTimeEffective: SupplementAllocationService.effectiveSnapshot(
                regularGross: allTimeGross,
                supplementTotals: allTimeSupplementTotals,
                estimate: effectiveTaxEstimate,
                hours: allTimeHours
            )
        )

        return JobSummarySnapshot(
            id: job.id,
            name: job.displayName,
            accent: job.accent,
            currentBreakdown: currentBreakdown,
            annualizedGrossIncome: annualizedGrossIncome,
            annualizedTaxableSupplementIncome: annualizedTaxableSupplementIncome,
            payPeriodInterval: payPeriodInterval,
            payScheduleFrequency: configuration.paySchedule.frequency,
            projectedConfidenceLabel: projection.confidenceLabel,
            rollup: rollup
        )
    }

    private static func makeShiftRecord(
        from scheduledShift: ScheduledShift,
        configuration: JobConfiguration,
        existingShifts: [ShiftRecord]
    ) -> ShiftRecord {
        let breakdown = EarningsEngine.calculate(
            start: scheduledShift.startDate,
            end: scheduledShift.endDate,
            payRates: configuration.payRates,
            nightRule: configuration.nightRule,
            overtimeRule: configuration.overtimeRule,
            historicalShifts: existingShifts
        )

        return ShiftRecord(
            job: configuration.job,
            startDate: scheduledShift.startDate,
            endDate: scheduledShift.endDate,
            note: scheduledShift.note,
            breakdown: breakdown
        )
    }

    private static func combinedPayFrequency(
        from snapshotData: SnapshotData,
        jobSummaries: [JobSummarySnapshot]
    ) -> PayFrequency {
        if let preferredIdentifier = snapshotData.preferences?.selectedHomeJobIdentifier,
           let preferredJob = jobSummaries.first(where: { $0.id == preferredIdentifier }) {
            return preferredJob.payScheduleFrequency
        }

        return jobSummaries.first?.payScheduleFrequency ?? .biweekly
    }

    private static func combinedPayPeriodAggregation(
        for jobSummaries: [JobSummarySnapshot]
    ) -> PayPeriodAggregationState {
        let participatingSummaries = jobSummaries.filter(participatesInCombinedPayPeriod)
        guard let referenceInterval = participatingSummaries.first?.payPeriodInterval else {
            return .unified
        }

        let intervalsMatch = participatingSummaries.dropFirst().allSatisfy { summary in
            summary.payPeriodInterval == referenceInterval
        }

        return intervalsMatch ? .unified : .variesByJob
    }

    private static func participatesInCombinedPayPeriod(_ summary: JobSummarySnapshot) -> Bool {
        summary.rollup.payPeriodGross > 0.001
            || summary.rollup.payPeriodHours > 0.001
            || summary.rollup.projectedGross > summary.rollup.payPeriodGross + 0.001
            || summary.rollup.payPeriodEffective.supplementalTotal > 0.001
            || summary.rollup.projectedEffective.supplementalTotal > 0.001
    }

    private static func combinedSupplementTotals(_ snapshots: [EffectiveCompensationSnapshot]) -> SupplementTotals {
        snapshots.reduce(into: .zero) { partial, snapshot in
            partial.total += snapshot.supplementalTotal
            partial.taxableTotal += snapshot.supplementalTaxableTotal
            partial.nonTaxableTotal += snapshot.supplementalNonTaxableTotal
        }
    }

    private static func proratedSupplementTotals(
        currentHours: Double,
        payPeriodHours: Double,
        supplementTotals: SupplementTotals
    ) -> SupplementTotals {
        guard currentHours > 0.000_001, payPeriodHours > 0.000_001 else {
            return .zero
        }

        let fraction = min(max(currentHours / payPeriodHours, 0), 1)
        return SupplementTotals(
            total: supplementTotals.total * fraction,
            taxableTotal: supplementTotals.taxableTotal * fraction,
            nonTaxableTotal: supplementTotals.nonTaxableTotal * fraction
        )
    }

    private static func combineBreakdowns(_ breakdowns: [EarningsBreakdown]) -> EarningsBreakdown? {
        guard !breakdowns.isEmpty else {
            return nil
        }

        if breakdowns.count == 1 {
            return breakdowns[0]
        }

        let combined = breakdowns.reduce(
            EarningsBreakdown(
                totalHours: 0,
                grossEarnings: 0,
                baseEarnings: 0,
                nightPremiumEarnings: 0,
                overtimePremiumEarnings: 0,
                regularHours: 0,
                nightHours: 0,
                overtimeHours: 0,
                effectiveRate: 0
            )
        ) { partial, breakdown in
            EarningsBreakdown(
                totalHours: partial.totalHours + breakdown.totalHours,
                grossEarnings: partial.grossEarnings + breakdown.grossEarnings,
                baseEarnings: partial.baseEarnings + breakdown.baseEarnings,
                nightPremiumEarnings: partial.nightPremiumEarnings + breakdown.nightPremiumEarnings,
                overtimePremiumEarnings: partial.overtimePremiumEarnings + breakdown.overtimePremiumEarnings,
                regularHours: partial.regularHours + breakdown.regularHours,
                nightHours: partial.nightHours + breakdown.nightHours,
                overtimeHours: partial.overtimeHours + breakdown.overtimeHours,
                effectiveRate: partial.effectiveRate + breakdown.effectiveRate
            )
        }

        return EarningsBreakdown(
            totalHours: combined.totalHours,
            grossEarnings: combined.grossEarnings,
            baseEarnings: combined.baseEarnings,
            nightPremiumEarnings: combined.nightPremiumEarnings,
            overtimePremiumEarnings: combined.overtimePremiumEarnings,
            regularHours: combined.regularHours,
            nightHours: combined.nightHours,
            overtimeHours: combined.overtimeHours,
            effectiveRate: combined.totalHours > 0
                ? combined.grossEarnings / combined.totalHours
                : 0
        )
    }

    private static func preferredHomeJob(in context: ModelContext) throws -> JobProfile {
        let jobs = try JobService.jobs(in: context)
        guard !jobs.isEmpty else {
            throw ShiftControllerError.noJobsSelected
        }

        let preferences = try DataBootstrapper.first(AppPreferences.self, in: context)
        if let preferredIdentifier = preferences?.selectedHomeJobIdentifier,
           let preferredJob = jobs.first(where: { $0.id == preferredIdentifier }) {
            return preferredJob
        }

        return jobs[0]
    }

    private static func resolvedJob(for identifier: UUID?, in context: ModelContext) throws -> JobProfile {
        let jobs = try JobService.jobs(in: context)
        if let identifier, let job = jobs.first(where: { $0.id == identifier }) {
            return job
        }

        guard let fallbackJob = jobs.first else {
            throw ShiftControllerError.noJobsSelected
        }

        return fallbackJob
    }
}
