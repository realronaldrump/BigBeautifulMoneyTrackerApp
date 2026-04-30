import Foundation

enum PayPeriodStatus: Equatable {
    case current
    case closed

    var title: String {
        switch self {
        case .current:
            "Current"
        case .closed:
            "Closed"
        }
    }
}

struct PayPeriodShiftSummary: Identifiable, Equatable {
    var id: String
    var shiftIdentifier: UUID
    var jobIdentifier: UUID?
    var jobName: String
    var startDate: Date
    var endDate: Date
    var allocatedStartDate: Date
    var allocatedEndDate: Date
    var note: String
    var allocationFraction: Double
    var isActive: Bool
    var totalHours: Double
    var grossEarnings: Double
    var estimatedTakeHome: Double
    var baseEarnings: Double
    var nightPremiumEarnings: Double
    var overtimePremiumEarnings: Double
    var regularHours: Double
    var nightHours: Double
    var overtimeHours: Double

    var isPartial: Bool {
        allocationFraction < 0.999
    }
}

struct PayPeriodSummary: Identifiable, Equatable {
    var id: String
    var jobIdentifier: UUID?
    var jobName: String
    var accent: JobAccentStyle
    var interval: DateInterval
    var frequency: PayFrequency
    var status: PayPeriodStatus
    var isCombined: Bool
    var shifts: [PayPeriodShiftSummary]
    var supplementAllocations: [JobSupplementAllocation]
    var shiftCount: Int
    var grossEarnings: Double
    var estimatedTakeHome: Double
    var baseEarnings: Double
    var nightPremiumEarnings: Double
    var overtimePremiumEarnings: Double
    var totalHours: Double
    var regularHours: Double
    var nightHours: Double
    var overtimeHours: Double
    var effectiveHourlyRate: Double
    var averageShiftGross: Double
    var bestShiftGross: Double
    var annualizedGrossIncome: Double
    var annualizedTaxableSupplementIncome: Double
    var yearToDateGrossBeforePeriod: Double

    var effectiveCompensation: EffectiveCompensationSnapshot

    var supplementalTotal: Double {
        effectiveCompensation.supplementalTotal
    }

    var supplementalTaxableTotal: Double {
        effectiveCompensation.supplementalTaxableTotal
    }

    var supplementalNonTaxableTotal: Double {
        effectiveCompensation.supplementalNonTaxableTotal
    }

    var effectiveGross: Double {
        effectiveCompensation.effectiveGross
    }

    var effectiveTakeHome: Double {
        effectiveCompensation.effectiveTakeHome
    }

    var effectiveSupplementalHourlyRate: Double? {
        effectiveCompensation.effectiveHourlyRate
    }
}

struct PayPeriodArchiveSection: Identifiable, Equatable {
    var id: String
    var jobIdentifier: UUID?
    var title: String
    var accent: JobAccentStyle
    var isCombined: Bool
    var summaries: [PayPeriodSummary]
}

struct PayPeriodArchiveSnapshot: Equatable {
    var generatedAt: Date
    var rangeStart: Date
    var rangeEnd: Date
    var sections: [PayPeriodArchiveSection]

    var defaultSectionID: String? {
        sections.first?.id
    }

    var latestSummary: PayPeriodSummary? {
        sections
            .lazy
            .flatMap(\.summaries)
            .sorted { first, second in
                if first.interval.start == second.interval.start {
                    return first.jobName < second.jobName
                }
                return first.interval.start > second.interval.start
            }
            .first
    }
}

enum PayPeriodService {
    static let defaultArchiveMonths = 12

    static func archiveSnapshot(
        asOf date: Date = .now,
        jobs: [JobProfile],
        completedShifts: [ShiftRecord],
        openShifts: [OpenShiftState] = [],
        paySchedules: [PaySchedule],
        payRates: [PayRateSchedule],
        nightRules: [NightDifferentialRule],
        overtimeRules: [OvertimeRuleSet],
        supplements: [JobSupplement] = [],
        templates: [ScheduleTemplate],
        taxProfile: TaxProfile,
        calendar: Calendar = .current,
        archiveMonths: Int = defaultArchiveMonths
    ) -> PayPeriodArchiveSnapshot {
        let rangeStart = calendar.startOfDay(
            for: calendar.date(byAdding: .month, value: -archiveMonths, to: date) ?? date
        )
        let sortedJobs = jobs.sorted {
            if $0.sortOrder == $1.sortOrder {
                return $0.createdAt < $1.createdAt
            }
            return $0.sortOrder < $1.sortOrder
        }

        let jobSections = sortedJobs.compactMap { job -> PayPeriodArchiveSection? in
            let configuration = JobService.configuration(
                for: job,
                payRates: payRates,
                nightRules: nightRules,
                overtimeRules: overtimeRules,
                paySchedules: paySchedules,
                supplements: supplements,
                templates: templates
            )
            let jobCompletedShifts = completedShifts.filter { $0.job?.id == job.id }
            let jobOpenShifts = job.isArchived ? [] : openShifts.filter { $0.job?.id == job.id }
            let periods = payPeriodIntervals(
                asOf: date,
                schedule: configuration.paySchedule,
                rangeStart: rangeStart,
                calendar: calendar
            )

            let summaries = periods.compactMap { interval -> PayPeriodSummary? in
                summary(
                    for: job,
                    configuration: configuration,
                    interval: interval,
                    asOf: date,
                    completedShifts: jobCompletedShifts,
                    openShifts: jobOpenShifts,
                    taxProfile: taxProfile,
                    calendar: calendar,
                    forceIncludeCurrent: !job.isArchived
                )
            }

            guard !summaries.isEmpty else {
                return nil
            }

            return PayPeriodArchiveSection(
                id: "job-\(job.id.uuidString)",
                jobIdentifier: job.id,
                title: job.displayName,
                accent: job.accent,
                isCombined: false,
                summaries: summaries
            )
        }

        var sections = jobSections
        if let combinedSection = combinedSection(
            from: jobSections,
            taxProfile: taxProfile,
            calendar: calendar
        ) {
            sections.append(combinedSection)
        }

        return PayPeriodArchiveSnapshot(
            generatedAt: date,
            rangeStart: rangeStart,
            rangeEnd: date,
            sections: sections
        )
    }

    static func payPeriodIntervals(
        asOf date: Date,
        schedule: PaySchedule,
        rangeStart: Date,
        calendar: Calendar = .current
    ) -> [DateInterval] {
        var intervals: [DateInterval] = []
        var current = ProjectionEngine.payPeriodInterval(for: date, schedule: schedule, calendar: calendar)

        while current.end > rangeStart {
            intervals.append(current)

            guard let previousProbe = calendar.date(byAdding: .second, value: -1, to: current.start) else {
                break
            }

            let previous = ProjectionEngine.payPeriodInterval(for: previousProbe, schedule: schedule, calendar: calendar)
            guard previous.start < current.start else {
                break
            }

            current = previous
        }

        return intervals.sorted { $0.start > $1.start }
    }

    private static func summary(
        for job: JobProfile,
        configuration: JobConfiguration,
        interval: DateInterval,
        asOf date: Date,
        completedShifts: [ShiftRecord],
        openShifts: [OpenShiftState],
        taxProfile: TaxProfile,
        calendar: Calendar,
        forceIncludeCurrent: Bool
    ) -> PayPeriodSummary? {
        let isCurrent = interval.contains(date)
        let status: PayPeriodStatus = isCurrent ? .current : .closed
        let periodEndForEstimate = min(interval.end, date)
        let currentRate = EarningsEngine.payRate(at: periodEndForEstimate, payRates: configuration.payRates)
        let supplementWindow = DateInterval(start: interval.start, end: periodEndForEstimate)
        let supplementAllocations = SupplementAllocationService.allocations(
            for: configuration.supplements,
            within: supplementWindow,
            calendar: calendar
        )
        let supplementTotals = SupplementAllocationService.totals(for: supplementAllocations)

        let allocatedCompletedShifts = completedShifts.compactMap { shift in
            allocatedCompletedShift(
                shift,
                configuration: configuration,
                interval: interval,
                jobName: job.displayName,
                completedShifts: completedShifts,
                taxRate: 0,
                calendar: calendar
            )
        }
        let allocatedOpenShifts = isCurrent
            ? openShifts.compactMap { openShift in
                allocatedOpenShift(
                    openShift,
                    configuration: configuration,
                    interval: interval,
                    asOf: date,
                    historicalShifts: completedShifts,
                    taxRate: 0,
                    calendar: calendar
                )
            }
            : []

        let preTaxShifts = allocatedCompletedShifts + allocatedOpenShifts
        let totals = totals(for: preTaxShifts)
        let shouldInclude = !preTaxShifts.isEmpty || !supplementAllocations.isEmpty || (forceIncludeCurrent && isCurrent)
        guard shouldInclude else {
            return nil
        }

        let yearToDateGrossBeforePeriod = allocatedGrossBeforePeriod(
            shifts: completedShifts,
            configuration: configuration,
            interval: interval,
            calendar: calendar
        )
        let annualizedGrossIncome = TaxEstimator.paycheckAnnualizedGross(
            periodGross: totals.gross,
            payFrequency: configuration.paySchedule.frequency
        )
        let annualizedTaxableSupplementIncome = SupplementAllocationService.annualizedTaxableIncome(
            asOf: periodEndForEstimate,
            supplements: configuration.supplements,
            calendar: calendar
        )
        let taxEstimate = TaxEstimator.estimate(
            currentGross: totals.gross,
            annualizedGrossIncome: annualizedGrossIncome,
            annualExtraWithholding: TaxEstimator.annualExtraWithholding(
                payFrequency: configuration.paySchedule.frequency,
                taxProfile: taxProfile
            ),
            taxProfile: taxProfile,
            payFrequency: configuration.paySchedule.frequency
        )
        let effectiveEstimate = TaxEstimator.estimate(
            currentGross: 0,
            annualizedGrossIncome: annualizedGrossIncome,
            annualizedTaxableSupplementalIncome: annualizedTaxableSupplementIncome,
            annualExtraWithholding: TaxEstimator.annualExtraWithholding(
                payFrequency: configuration.paySchedule.frequency,
                taxProfile: taxProfile
            ),
            taxProfile: taxProfile,
            payFrequency: configuration.paySchedule.frequency
        )
        let shifts = preTaxShifts.map { shift in
            var resolved = shift
            resolved.estimatedTakeHome = TaxEstimator.estimatedTakeHome(for: shift.grossEarnings, estimate: taxEstimate)
            return resolved
        }
        let takeHome = TaxEstimator.estimatedTakeHome(for: totals.gross, estimate: taxEstimate)

        return PayPeriodSummary(
            id: summaryID(prefix: "job-\(job.id.uuidString)", interval: interval),
            jobIdentifier: job.id,
            jobName: job.displayName,
            accent: job.accent,
            interval: interval,
            frequency: configuration.paySchedule.frequency,
            status: status,
            isCombined: false,
            shifts: shifts,
            supplementAllocations: supplementAllocations,
            shiftCount: shifts.count,
            grossEarnings: totals.gross,
            estimatedTakeHome: takeHome,
            baseEarnings: totals.base,
            nightPremiumEarnings: totals.nightPremium,
            overtimePremiumEarnings: totals.overtimePremium,
            totalHours: totals.hours,
            regularHours: totals.regularHours,
            nightHours: totals.nightHours,
            overtimeHours: totals.overtimeHours,
            effectiveHourlyRate: totals.hours > 0 ? totals.gross / totals.hours : currentRate,
            averageShiftGross: shifts.isEmpty ? 0 : totals.gross / Double(shifts.count),
            bestShiftGross: shifts.map(\.grossEarnings).max() ?? 0,
            annualizedGrossIncome: annualizedGrossIncome,
            annualizedTaxableSupplementIncome: annualizedTaxableSupplementIncome,
            yearToDateGrossBeforePeriod: yearToDateGrossBeforePeriod,
            effectiveCompensation: SupplementAllocationService.effectiveSnapshot(
                regularGross: totals.gross,
                supplementTotals: supplementTotals,
                estimate: effectiveEstimate,
                hours: totals.hours
            )
        )
    }

    private static func allocatedCompletedShift(
        _ shift: ShiftRecord,
        configuration: JobConfiguration,
        interval: DateInterval,
        jobName: String,
        completedShifts: [ShiftRecord],
        taxRate: Double,
        calendar: Calendar
    ) -> PayPeriodShiftSummary? {
        guard let allocation = allocation(
            originalStart: shift.startDate,
            originalEnd: shift.endDate,
            interval: interval
        ) else {
            return nil
        }

        let breakdown = completedShiftBreakdown(
            for: shift,
            allocation: allocation,
            configuration: configuration,
            completedShifts: completedShifts,
            calendar: calendar
        )

        return PayPeriodShiftSummary(
            id: "\(shift.id.uuidString)-\(Int(interval.start.timeIntervalSince1970))",
            shiftIdentifier: shift.id,
            jobIdentifier: shift.job?.id,
            jobName: jobName,
            startDate: shift.startDate,
            endDate: shift.endDate,
            allocatedStartDate: allocation.start,
            allocatedEndDate: allocation.end,
            note: shift.note,
            allocationFraction: allocation.fraction,
            isActive: false,
            totalHours: breakdown.totalHours,
            grossEarnings: breakdown.grossEarnings,
            estimatedTakeHome: max(0, breakdown.grossEarnings * (1 - taxRate)),
            baseEarnings: breakdown.baseEarnings,
            nightPremiumEarnings: breakdown.nightPremiumEarnings,
            overtimePremiumEarnings: breakdown.overtimePremiumEarnings,
            regularHours: breakdown.regularHours,
            nightHours: breakdown.nightHours,
            overtimeHours: breakdown.overtimeHours
        )
    }

    private static func allocatedOpenShift(
        _ openShift: OpenShiftState,
        configuration: JobConfiguration,
        interval: DateInterval,
        asOf date: Date,
        historicalShifts: [ShiftRecord],
        taxRate: Double,
        calendar: Calendar
    ) -> PayPeriodShiftSummary? {
        guard date > openShift.startDate,
              let allocation = allocation(
                originalStart: openShift.startDate,
                originalEnd: date,
                interval: interval
              )
        else {
            return nil
        }

        let breakdown = partialBreakdown(
            start: openShift.startDate,
            allocation: allocation,
            configuration: configuration,
            historicalShifts: historicalShifts,
            calendar: calendar
        )

        return PayPeriodShiftSummary(
            id: "\(openShift.id.uuidString)-\(Int(interval.start.timeIntervalSince1970))-active",
            shiftIdentifier: openShift.id,
            jobIdentifier: openShift.job?.id,
            jobName: configuration.job.displayName,
            startDate: openShift.startDate,
            endDate: date,
            allocatedStartDate: allocation.start,
            allocatedEndDate: allocation.end,
            note: openShift.note,
            allocationFraction: allocation.fraction,
            isActive: true,
            totalHours: breakdown.totalHours,
            grossEarnings: breakdown.grossEarnings,
            estimatedTakeHome: max(0, breakdown.grossEarnings * (1 - taxRate)),
            baseEarnings: breakdown.baseEarnings,
            nightPremiumEarnings: breakdown.nightPremiumEarnings,
            overtimePremiumEarnings: breakdown.overtimePremiumEarnings,
            regularHours: breakdown.regularHours,
            nightHours: breakdown.nightHours,
            overtimeHours: breakdown.overtimeHours
        )
    }

    private static func combinedSection(
        from jobSections: [PayPeriodArchiveSection],
        taxProfile: TaxProfile,
        calendar: Calendar
    ) -> PayPeriodArchiveSection? {
        guard jobSections.count > 1 else {
            return nil
        }

        let combinedSummaries = uniquePeriodGroups(from: jobSections.flatMap(\.summaries))
            .compactMap { group -> PayPeriodSummary? in
                let matching = jobSections.compactMap { section in
                    section.summaries.first {
                        $0.frequency == group.frequency
                            && intervalsMatch($0.interval, group.interval)
                    }
                }
                guard matching.count > 1 else {
                    return nil
                }
                return combinedSummary(from: matching, taxProfile: taxProfile, calendar: calendar)
            }

        guard !combinedSummaries.isEmpty else {
            return nil
        }

        return PayPeriodArchiveSection(
            id: "combined",
            jobIdentifier: nil,
            title: "Combined",
            accent: .emerald,
            isCombined: true,
            summaries: combinedSummaries
        )
    }

    private static func combinedSummary(
        from summaries: [PayPeriodSummary],
        taxProfile: TaxProfile,
        calendar: Calendar
    ) -> PayPeriodSummary {
        let reference = summaries[0]
        let shifts = summaries
            .flatMap(\.shifts)
            .sorted {
                if $0.allocatedStartDate == $1.allocatedStartDate {
                    return $0.jobName < $1.jobName
                }
                return $0.allocatedStartDate > $1.allocatedStartDate
            }
        let totals = totals(for: shifts)
        let annualizedGrossIncome = summaries.reduce(0) { $0 + $1.annualizedGrossIncome }
        let annualizedTaxableSupplementIncome = summaries.reduce(0) { $0 + $1.annualizedTaxableSupplementIncome }
        let taxEstimate = TaxEstimator.estimate(
            currentGross: totals.gross,
            annualizedGrossIncome: annualizedGrossIncome,
            annualExtraWithholding: TaxEstimator.annualExtraWithholding(
                payFrequency: reference.frequency,
                taxProfile: taxProfile
            ),
            taxProfile: taxProfile,
            payFrequency: reference.frequency
        )
        let effectiveEstimate = TaxEstimator.estimate(
            currentGross: 0,
            annualizedGrossIncome: annualizedGrossIncome,
            annualizedTaxableSupplementalIncome: annualizedTaxableSupplementIncome,
            annualExtraWithholding: TaxEstimator.annualExtraWithholding(
                payFrequency: reference.frequency,
                taxProfile: taxProfile
            ),
            taxProfile: taxProfile,
            payFrequency: reference.frequency
        )
        let resolvedShifts = shifts.map { shift in
            var resolved = shift
            resolved.estimatedTakeHome = TaxEstimator.estimatedTakeHome(for: shift.grossEarnings, estimate: taxEstimate)
            return resolved
        }
        let supplementAllocations = summaries
            .flatMap(\.supplementAllocations)
            .sorted {
                if $0.jobName == $1.jobName {
                    return $0.label < $1.label
                }
                return $0.jobName < $1.jobName
            }
        let supplementTotals = SupplementAllocationService.totals(for: supplementAllocations)

        return PayPeriodSummary(
            id: summaryID(prefix: "combined", interval: reference.interval),
            jobIdentifier: nil,
            jobName: "Combined",
            accent: .emerald,
            interval: reference.interval,
            frequency: reference.frequency,
            status: reference.status,
            isCombined: true,
            shifts: resolvedShifts,
            supplementAllocations: supplementAllocations,
            shiftCount: resolvedShifts.count,
            grossEarnings: totals.gross,
            estimatedTakeHome: TaxEstimator.estimatedTakeHome(for: totals.gross, estimate: taxEstimate),
            baseEarnings: totals.base,
            nightPremiumEarnings: totals.nightPremium,
            overtimePremiumEarnings: totals.overtimePremium,
            totalHours: totals.hours,
            regularHours: totals.regularHours,
            nightHours: totals.nightHours,
            overtimeHours: totals.overtimeHours,
            effectiveHourlyRate: totals.hours > 0 ? totals.gross / totals.hours : 0,
            averageShiftGross: resolvedShifts.isEmpty ? 0 : totals.gross / Double(resolvedShifts.count),
            bestShiftGross: resolvedShifts.map(\.grossEarnings).max() ?? 0,
            annualizedGrossIncome: annualizedGrossIncome,
            annualizedTaxableSupplementIncome: annualizedTaxableSupplementIncome,
            yearToDateGrossBeforePeriod: summaries.reduce(0) { $0 + $1.yearToDateGrossBeforePeriod },
            effectiveCompensation: SupplementAllocationService.effectiveSnapshot(
                regularGross: totals.gross,
                supplementTotals: supplementTotals,
                estimate: effectiveEstimate,
                hours: totals.hours
            )
        )
    }

    private struct PayPeriodGroup {
        var interval: DateInterval
        var frequency: PayFrequency
    }

    private static func uniquePeriodGroups(from summaries: [PayPeriodSummary]) -> [PayPeriodGroup] {
        summaries.reduce(into: [PayPeriodGroup]()) { partial, summary in
            let alreadyIncluded = partial.contains {
                $0.frequency == summary.frequency && intervalsMatch($0.interval, summary.interval)
            }
            if !alreadyIncluded {
                partial.append(PayPeriodGroup(interval: summary.interval, frequency: summary.frequency))
            }
        }
        .sorted {
            if $0.interval.start == $1.interval.start {
                return $0.frequency.rawValue < $1.frequency.rawValue
            }
            return $0.interval.start > $1.interval.start
        }
    }

    private static func allocation(
        originalStart: Date,
        originalEnd: Date,
        interval: DateInterval
    ) -> (start: Date, end: Date, fraction: Double)? {
        guard originalEnd > originalStart else {
            return nil
        }

        let overlapStart = max(originalStart, interval.start)
        let overlapEnd = min(originalEnd, interval.end)
        guard overlapEnd > overlapStart else {
            return nil
        }

        let originalDuration = originalEnd.timeIntervalSince(originalStart)
        let overlapDuration = overlapEnd.timeIntervalSince(overlapStart)
        return (overlapStart, overlapEnd, min(1, max(0, overlapDuration / originalDuration)))
    }

    private static func completedShiftBreakdown(
        for shift: ShiftRecord,
        allocation: (start: Date, end: Date, fraction: Double),
        configuration: JobConfiguration,
        completedShifts: [ShiftRecord],
        calendar: Calendar
    ) -> EarningsBreakdown {
        let stored = storedBreakdown(for: shift)
        guard allocation.fraction < 0.999 else {
            return stored
        }

        guard !configuration.payRates.isEmpty else {
            return proratedBreakdown(stored, fraction: allocation.fraction)
        }

        let historicalShifts = completedShifts.filter {
            $0.id != shift.id && $0.endDate <= shift.startDate
        }

        return partialBreakdown(
            start: shift.startDate,
            allocation: allocation,
            configuration: configuration,
            historicalShifts: historicalShifts,
            calendar: calendar
        )
    }

    private static func partialBreakdown(
        start: Date,
        allocation: (start: Date, end: Date, fraction: Double),
        configuration: JobConfiguration,
        historicalShifts: [ShiftRecord],
        calendar: Calendar
    ) -> EarningsBreakdown {
        let throughEnd = EarningsEngine.calculate(
            start: start,
            end: allocation.end,
            payRates: configuration.payRates,
            nightRule: configuration.nightRule,
            overtimeRule: configuration.overtimeRule,
            historicalShifts: historicalShifts,
            calendar: calendar
        )

        guard allocation.start > start else {
            return throughEnd
        }

        let beforeAllocation = EarningsEngine.calculate(
            start: start,
            end: allocation.start,
            payRates: configuration.payRates,
            nightRule: configuration.nightRule,
            overtimeRule: configuration.overtimeRule,
            historicalShifts: historicalShifts,
            calendar: calendar
        )

        return subtract(beforeAllocation, from: throughEnd)
    }

    private static func storedBreakdown(for shift: ShiftRecord) -> EarningsBreakdown {
        EarningsBreakdown(
            totalHours: shift.totalHours,
            grossEarnings: shift.grossEarnings,
            baseEarnings: shift.baseEarnings,
            nightPremiumEarnings: shift.nightPremiumEarnings,
            overtimePremiumEarnings: shift.overtimePremiumEarnings,
            regularHours: shift.regularHours,
            nightHours: shift.nightHours,
            overtimeHours: shift.overtimeHours,
            effectiveRate: shift.effectiveRateAtClockOut
        )
    }

    private static func proratedBreakdown(_ breakdown: EarningsBreakdown, fraction: Double) -> EarningsBreakdown {
        EarningsBreakdown(
            totalHours: breakdown.totalHours * fraction,
            grossEarnings: breakdown.grossEarnings * fraction,
            baseEarnings: breakdown.baseEarnings * fraction,
            nightPremiumEarnings: breakdown.nightPremiumEarnings * fraction,
            overtimePremiumEarnings: breakdown.overtimePremiumEarnings * fraction,
            regularHours: breakdown.regularHours * fraction,
            nightHours: breakdown.nightHours * fraction,
            overtimeHours: breakdown.overtimeHours * fraction,
            effectiveRate: breakdown.effectiveRate
        )
    }

    private static func subtract(_ subtrahend: EarningsBreakdown, from minuend: EarningsBreakdown) -> EarningsBreakdown {
        let totalHours = max(0, minuend.totalHours - subtrahend.totalHours)
        let grossEarnings = max(0, minuend.grossEarnings - subtrahend.grossEarnings)
        return EarningsBreakdown(
            totalHours: totalHours,
            grossEarnings: grossEarnings,
            baseEarnings: max(0, minuend.baseEarnings - subtrahend.baseEarnings),
            nightPremiumEarnings: max(0, minuend.nightPremiumEarnings - subtrahend.nightPremiumEarnings),
            overtimePremiumEarnings: max(0, minuend.overtimePremiumEarnings - subtrahend.overtimePremiumEarnings),
            regularHours: max(0, minuend.regularHours - subtrahend.regularHours),
            nightHours: max(0, minuend.nightHours - subtrahend.nightHours),
            overtimeHours: max(0, minuend.overtimeHours - subtrahend.overtimeHours),
            effectiveRate: totalHours > 0 ? grossEarnings / totalHours : 0
        )
    }

    private static func allocatedGrossBeforePeriod(
        shifts: [ShiftRecord],
        configuration: JobConfiguration,
        interval: DateInterval,
        calendar: Calendar
    ) -> Double {
        let yearStart = calendar.date(
            from: DateComponents(
                year: calendar.component(.year, from: interval.start),
                month: 1,
                day: 1
            )
        ) ?? interval.start
        let beforeInterval = DateInterval(start: yearStart, end: interval.start)

        return shifts.reduce(0) { partial, shift in
            guard let allocation = allocation(
                originalStart: shift.startDate,
                originalEnd: shift.endDate,
                interval: beforeInterval
            ) else {
                return partial
            }
            let breakdown = completedShiftBreakdown(
                for: shift,
                allocation: allocation,
                configuration: configuration,
                completedShifts: shifts,
                calendar: calendar
            )
            return partial + breakdown.grossEarnings
        }
    }

    private static func totals(for shifts: [PayPeriodShiftSummary]) -> (
        gross: Double,
        hours: Double,
        base: Double,
        nightPremium: Double,
        overtimePremium: Double,
        regularHours: Double,
        nightHours: Double,
        overtimeHours: Double
    ) {
        shifts.reduce(
            (
                gross: 0,
                hours: 0,
                base: 0,
                nightPremium: 0,
                overtimePremium: 0,
                regularHours: 0,
                nightHours: 0,
                overtimeHours: 0
            )
        ) { partial, shift in
            (
                gross: partial.gross + shift.grossEarnings,
                hours: partial.hours + shift.totalHours,
                base: partial.base + shift.baseEarnings,
                nightPremium: partial.nightPremium + shift.nightPremiumEarnings,
                overtimePremium: partial.overtimePremium + shift.overtimePremiumEarnings,
                regularHours: partial.regularHours + shift.regularHours,
                nightHours: partial.nightHours + shift.nightHours,
                overtimeHours: partial.overtimeHours + shift.overtimeHours
            )
        }
    }

    private static func summaryID(prefix: String, interval: DateInterval) -> String {
        "\(prefix)-\(Int(interval.start.timeIntervalSince1970))-\(Int(interval.end.timeIntervalSince1970))"
    }

    private static func intervalsMatch(_ lhs: DateInterval, _ rhs: DateInterval) -> Bool {
        abs(lhs.start.timeIntervalSince(rhs.start)) < 0.5
            && abs(lhs.end.timeIntervalSince(rhs.end)) < 0.5
    }
}
