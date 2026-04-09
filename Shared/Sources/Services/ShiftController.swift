import Foundation
import SwiftData

enum ShiftControllerError: LocalizedError {
    case missingPayRate
    case noOpenShift
    case invalidShiftRange
    case invalidScheduledEnd

    var errorDescription: String? {
        switch self {
        case .missingPayRate:
            "Add an hourly rate before tracking a shift."
        case .noOpenShift:
            "There isn’t an active shift to end."
        case .invalidShiftRange:
            "The shift end needs to be later than the start."
        case .invalidScheduledEnd:
            "The planned end needs to be later than the shift start."
        }
    }
}

struct ScheduledShiftAutomationResult {
    var autoCompletedShifts: [ShiftRecord] = []
    var startedShift: OpenShiftState?
}

@MainActor
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
        try DataBootstrapper.seedIfNeeded(in: context)
        if let existingShift = try DataBootstrapper.first(OpenShiftState.self, in: context) {
            return existingShift
        }

        if let scheduledEndDate, scheduledEndDate <= date {
            throw ShiftControllerError.invalidScheduledEnd
        }

        let openShift = OpenShiftState(startDate: date, note: note)
        openShift.scheduledEndDate = scheduledEndDate
        openShift.scheduledReminderOffsets = scheduledEndDate == nil ? [] : reminderOffsets
        context.insert(openShift)
        try context.save()
        return openShift
    }

    @discardableResult
    static func endShift(in context: ModelContext, at date: Date = .now) throws -> ShiftRecord {
        try DataBootstrapper.seedIfNeeded(in: context)
        guard let openShift = try DataBootstrapper.first(OpenShiftState.self, in: context) else {
            throw ShiftControllerError.noOpenShift
        }

        let payRates = try context.fetch(FetchDescriptor<PayRateSchedule>())
        guard !payRates.isEmpty else {
            throw ShiftControllerError.missingPayRate
        }

        let existingShifts = try context.fetch(FetchDescriptor<ShiftRecord>())
        let nightRule = try DataBootstrapper.first(NightDifferentialRule.self, in: context) ?? NightDifferentialRule()
        let overtimeRule = try DataBootstrapper.first(OvertimeRuleSet.self, in: context)

        let breakdown = EarningsEngine.calculate(
            start: openShift.startDate,
            end: date,
            payRates: payRates,
            nightRule: nightRule,
            overtimeRule: overtimeRule,
            historicalShifts: existingShifts
        )

        let shift = ShiftRecord(
            startDate: openShift.startDate,
            endDate: date,
            note: openShift.note,
            breakdown: breakdown
        )

        context.insert(shift)
        context.delete(openShift)
        try recordMilestones(for: shift, existingShifts: existingShifts, in: context)
        try context.save()
        return shift
    }

    static func saveManualShift(
        in context: ModelContext,
        editing shift: ShiftRecord?,
        startDate: Date,
        endDate: Date,
        note: String = ""
    ) throws {
        try DataBootstrapper.seedIfNeeded(in: context)
        guard endDate > startDate else {
            throw ShiftControllerError.invalidShiftRange
        }

        let payRates = try context.fetch(FetchDescriptor<PayRateSchedule>())
        guard !payRates.isEmpty else {
            throw ShiftControllerError.missingPayRate
        }

        let existingShifts = try context.fetch(FetchDescriptor<ShiftRecord>())
            .filter { existing in
                guard let shift else { return true }
                return existing.id != shift.id
            }
        let nightRule = try DataBootstrapper.first(NightDifferentialRule.self, in: context) ?? NightDifferentialRule()
        let overtimeRule = try DataBootstrapper.first(OvertimeRuleSet.self, in: context)

        let breakdown = EarningsEngine.calculate(
            start: startDate,
            end: endDate,
            payRates: payRates,
            nightRule: nightRule,
            overtimeRule: overtimeRule,
            historicalShifts: existingShifts
        )

        if let shift {
            shift.startDate = startDate
            shift.endDate = endDate
            shift.note = note
            shift.totalHours = breakdown.totalHours
            shift.grossEarnings = breakdown.grossEarnings
            shift.baseEarnings = breakdown.baseEarnings
            shift.nightPremiumEarnings = breakdown.nightPremiumEarnings
            shift.overtimePremiumEarnings = breakdown.overtimePremiumEarnings
            shift.regularHours = breakdown.regularHours
            shift.nightHours = breakdown.nightHours
            shift.overtimeHours = breakdown.overtimeHours
            shift.effectiveRateAtClockOut = breakdown.effectiveRate
            shift.updatedAt = .now
        } else {
            let newShift = ShiftRecord(startDate: startDate, endDate: endDate, note: note, breakdown: breakdown)
            context.insert(newShift)
        }

        try context.save()
    }

    static func saveScheduledShift(
        in context: ModelContext,
        editing shift: ScheduledShift?,
        startDate: Date,
        endDate: Date,
        note: String = ""
    ) throws {
        try DataBootstrapper.seedIfNeeded(in: context)
        guard endDate > startDate else {
            throw ShiftControllerError.invalidShiftRange
        }

        if let shift {
            shift.startDate = startDate
            shift.endDate = endDate
            shift.note = note
            shift.updatedAt = .now
        } else {
            context.insert(ScheduledShift(startDate: startDate, endDate: endDate, note: note))
        }

        try context.save()
    }

    static func deleteShift(_ shift: ShiftRecord, in context: ModelContext) throws {
        context.delete(shift)
        try context.save()
    }

    static func deleteScheduledShift(_ shift: ScheduledShift, in context: ModelContext) throws {
        context.delete(shift)
        try context.save()
    }

    static func updateOpenShift(
        in context: ModelContext,
        startDate: Date,
        scheduledEndDate: Date?,
        reminderOffsets: [Int]
    ) throws {
        guard let openShift = try DataBootstrapper.first(OpenShiftState.self, in: context) else {
            throw ShiftControllerError.noOpenShift
        }

        if let scheduledEndDate, scheduledEndDate <= startDate {
            throw ShiftControllerError.invalidScheduledEnd
        }

        openShift.startDate = startDate
        openShift.scheduledEndDate = scheduledEndDate
        openShift.scheduledReminderOffsets = scheduledEndDate == nil ? [] : reminderOffsets
        try context.save()
    }

    @discardableResult
    static func autoEndShiftIfNeeded(in context: ModelContext, at date: Date = .now) throws -> ShiftRecord? {
        guard let openShift = try DataBootstrapper.first(OpenShiftState.self, in: context),
              let scheduledEndDate = openShift.scheduledEndDate,
              date >= scheduledEndDate else {
            return nil
        }

        return try endShift(in: context, at: scheduledEndDate)
    }

    static func reconcileScheduledShifts(in context: ModelContext, at date: Date = .now) throws -> ScheduledShiftAutomationResult {
        try DataBootstrapper.seedIfNeeded(in: context)

        guard try DataBootstrapper.first(OpenShiftState.self, in: context) == nil else {
            return ScheduledShiftAutomationResult()
        }

        let scheduledDescriptor = FetchDescriptor<ScheduledShift>(
            sortBy: [SortDescriptor(\ScheduledShift.startDate)]
        )
        let scheduledShifts = try context.fetch(scheduledDescriptor)
        guard !scheduledShifts.isEmpty else {
            return ScheduledShiftAutomationResult()
        }

        guard scheduledShifts.contains(where: { $0.startDate <= date }) else {
            return ScheduledShiftAutomationResult()
        }

        let payRates = try context.fetch(FetchDescriptor<PayRateSchedule>())
        guard !payRates.isEmpty else {
            throw ShiftControllerError.missingPayRate
        }

        let nightRule = try DataBootstrapper.first(NightDifferentialRule.self, in: context) ?? NightDifferentialRule()
        let overtimeRule = try DataBootstrapper.first(OvertimeRuleSet.self, in: context)
        var completedShifts = try context.fetch(
            FetchDescriptor<ShiftRecord>(sortBy: [SortDescriptor(\ShiftRecord.startDate)])
        )
        var result = ScheduledShiftAutomationResult()

        for scheduledShift in scheduledShifts {
            if scheduledShift.endDate <= date {
                let completedShift = makeShiftRecord(
                    from: scheduledShift,
                    payRates: payRates,
                    nightRule: nightRule,
                    overtimeRule: overtimeRule,
                    existingShifts: completedShifts
                )

                context.insert(completedShift)
                try recordMilestones(for: completedShift, existingShifts: completedShifts, in: context)
                completedShifts.append(completedShift)
                result.autoCompletedShifts.append(completedShift)
                context.delete(scheduledShift)
                continue
            }

            guard scheduledShift.startDate <= date else {
                break
            }

            let startedShift = OpenShiftState(startDate: scheduledShift.startDate, note: scheduledShift.note)
            startedShift.scheduledEndDate = scheduledShift.endDate
            startedShift.scheduledReminderOffsets = defaultAutoEndReminderOffsets
            context.insert(startedShift)
            context.delete(scheduledShift)
            result.startedShift = startedShift
            break
        }

        if !result.autoCompletedShifts.isEmpty || result.startedShift != nil {
            try context.save()
        }

        return result
    }

    static func dashboardSnapshot(in context: ModelContext, at date: Date = .now) throws -> DashboardSnapshot {
        try DataBootstrapper.seedIfNeeded(in: context)

        let completedShifts = try context.fetch(FetchDescriptor<ShiftRecord>())
        let payRates = try context.fetch(FetchDescriptor<PayRateSchedule>())
        let templates = try context.fetch(FetchDescriptor<ScheduleTemplate>())
        let openShift = try DataBootstrapper.first(OpenShiftState.self, in: context)
        let nightRule = try DataBootstrapper.first(NightDifferentialRule.self, in: context) ?? NightDifferentialRule()
        let overtimeRule = try DataBootstrapper.first(OvertimeRuleSet.self, in: context)
        let taxProfile = try DataBootstrapper.first(TaxProfile.self, in: context) ?? TaxProfile()
        let paySchedule = try DataBootstrapper.first(PaySchedule.self, in: context) ?? PaySchedule()

        let currentBreakdown: EarningsBreakdown?
        if let openShift {
            currentBreakdown = EarningsEngine.calculate(
                start: openShift.startDate,
                end: date,
                payRates: payRates,
                nightRule: nightRule,
                overtimeRule: overtimeRule,
                historicalShifts: completedShifts
            )
        } else {
            currentBreakdown = nil
        }

        let yearInterval = Calendar.current.dateInterval(of: .year, for: date)
        let ytdGrossCompleted = AggregationService.totalGross(for: completedShifts, in: yearInterval)
        let effectiveRate = currentBreakdown?.effectiveRate ?? EarningsEngine.payRate(at: date, payRates: payRates)
        let taxEstimate = TaxEstimator.estimate(
            currentGross: currentBreakdown?.grossEarnings ?? 0,
            yearToDateGrossExcludingCurrentShift: ytdGrossCompleted,
            payFrequency: paySchedule.frequency,
            taxProfile: taxProfile,
            currentHourlyRate: effectiveRate,
            templates: templates
        )

        let takeHomeRate = taxEstimate.estimatedWithholdingRate
        let projection = ProjectionEngine.projectedPaycheck(
            asOf: date,
            shifts: completedShifts,
            openShiftBreakdown: currentBreakdown,
            paySchedule: paySchedule,
            payRates: payRates,
            templates: templates,
            takeHomeRate: takeHomeRate
        )

        let payPeriodInterval = ProjectionEngine.payPeriodInterval(for: date, schedule: paySchedule)
        let payPeriodNightPremium = AggregationService.totalNightPremium(for: completedShifts, in: payPeriodInterval) + (currentBreakdown?.nightPremiumEarnings ?? 0)
        let weeklyInterval = Calendar.current.dateInterval(of: .weekOfYear, for: date)
        let allTimeGross = AggregationService.totalGross(for: completedShifts) + (currentBreakdown?.grossEarnings ?? 0)
        let allTimeHours = AggregationService.totalHours(for: completedShifts) + (currentBreakdown?.totalHours ?? 0)

        return DashboardSnapshot(
            currentBreakdown: currentBreakdown,
            currentGross: currentBreakdown?.grossEarnings ?? 0,
            currentTakeHome: taxEstimate.currentShiftNetEstimate,
            payPeriodGross: projection.payPeriodGross,
            payPeriodTakeHome: projection.payPeriodGross * (1 - takeHomeRate),
            payPeriodHours: projection.payPeriodHours,
            payPeriodNightPremium: payPeriodNightPremium,
            allTimeGross: allTimeGross,
            allTimeTakeHome: allTimeGross * (1 - takeHomeRate),
            projectedPaycheckGross: projection.projectedGross,
            projectedPaycheckTakeHome: projection.projectedTakeHome,
            projectedConfidenceLabel: projection.confidenceLabel,
            weeklyGross: AggregationService.totalGross(for: completedShifts, in: weeklyInterval) + (currentBreakdown?.grossEarnings ?? 0),
            allTimeHours: allTimeHours
        )
    }

    private static func recordMilestones(for newShift: ShiftRecord, existingShifts: [ShiftRecord], in context: ModelContext) throws {
        if newShift.grossEarnings >= 100 {
            context.insert(MilestoneEvent(kind: .firstHundred, amount: newShift.grossEarnings, shiftIdentifier: newShift.id))
        }

        let previousBestShift = existingShifts.map(\.grossEarnings).max() ?? 0
        if newShift.grossEarnings > previousBestShift {
            context.insert(MilestoneEvent(kind: .allTimeRecord, amount: newShift.grossEarnings, shiftIdentifier: newShift.id))
        }

        let weekInterval = Calendar.current.dateInterval(of: .weekOfYear, for: newShift.endDate)
        let existingWeekGross = AggregationService.totalGross(for: existingShifts, in: weekInterval)
        let newWeekGross = existingWeekGross + newShift.grossEarnings

        let allOtherWeeks = Dictionary(grouping: existingShifts) { shift in
            Calendar.current.dateInterval(of: .weekOfYear, for: shift.startDate)?.start ?? shift.startDate
        }
        let previousBestPeriod = allOtherWeeks.values.map { AggregationService.totalGross(for: $0) }.max() ?? 0
        if newWeekGross > previousBestPeriod {
            context.insert(MilestoneEvent(kind: .weeklyRecord, amount: newWeekGross, shiftIdentifier: newShift.id))
        }
    }

    private static func makeShiftRecord(
        from scheduledShift: ScheduledShift,
        payRates: [PayRateSchedule],
        nightRule: NightDifferentialRule,
        overtimeRule: OvertimeRuleSet?,
        existingShifts: [ShiftRecord]
    ) -> ShiftRecord {
        let breakdown = EarningsEngine.calculate(
            start: scheduledShift.startDate,
            end: scheduledShift.endDate,
            payRates: payRates,
            nightRule: nightRule,
            overtimeRule: overtimeRule,
            historicalShifts: existingShifts
        )

        return ShiftRecord(
            startDate: scheduledShift.startDate,
            endDate: scheduledShift.endDate,
            note: scheduledShift.note,
            breakdown: breakdown
        )
    }
}
