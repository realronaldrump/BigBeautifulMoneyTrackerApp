import Foundation
import SwiftData

enum ShiftControllerError: LocalizedError {
    case missingPayRate
    case noOpenShift

    var errorDescription: String? {
        switch self {
        case .missingPayRate:
            "Add an hourly rate before tracking a shift."
        case .noOpenShift:
            "There isn’t an active shift to end."
        }
    }
}

@MainActor
enum ShiftController {
    static func startShift(in context: ModelContext, at date: Date = .now) throws {
        try DataBootstrapper.seedIfNeeded(in: context)
        if try DataBootstrapper.first(OpenShiftState.self, in: context) == nil {
            context.insert(OpenShiftState(startDate: date))
            try context.save()
        }
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

    static func deleteShift(_ shift: ShiftRecord, in context: ModelContext) throws {
        context.delete(shift)
        try context.save()
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
}
