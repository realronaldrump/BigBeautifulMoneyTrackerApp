import Foundation

enum ProjectionEngine {
    static func payPeriodInterval(
        for date: Date,
        schedule: PaySchedule,
        calendar: Calendar = .current
    ) -> DateInterval {
        switch schedule.frequency {
        case .weekly:
            return repeatingInterval(for: date, anchor: schedule.anchorDate, everyDays: 7, calendar: calendar)
        case .biweekly:
            return repeatingInterval(for: date, anchor: schedule.anchorDate, everyDays: 14, calendar: calendar)
        case .monthly:
            return monthlyInterval(for: date, anchor: schedule.anchorDate, calendar: calendar)
        case .semiMonthly:
            return semiMonthlyInterval(for: date, anchor: schedule.anchorDate, calendar: calendar)
        }
    }

    static func projectedPaycheck(
        asOf date: Date,
        shifts: [ShiftRecord],
        openShiftBreakdown: EarningsBreakdown?,
        paySchedule: PaySchedule,
        payRates: [PayRateSchedule],
        templates: [ScheduleTemplate],
        takeHomeRate: Double,
        configuration: JobConfiguration? = nil,
        openShifts: [OpenShiftState] = [],
        scheduledShifts: [ScheduledShift] = [],
        calendar: Calendar = .current
    ) -> (payPeriodGross: Double, payPeriodHours: Double, projectedGross: Double, projectedTakeHome: Double, confidenceLabel: String) {
        let payPeriod = payPeriodInterval(for: date, schedule: paySchedule, calendar: calendar)
        let earnedWindow = DateInterval(start: payPeriod.start, end: min(date, payPeriod.end))
        let completedGross: Double
        let completedHours: Double
        if let configuration {
            let allocated = shifts.map {
                ShiftEarningsAllocation.completed($0, within: earnedWindow, configuration: configuration, historicalShifts: shifts, calendar: calendar)
            }
            completedGross = allocated.reduce(0) { $0 + $1.grossEarnings }
            completedHours = allocated.reduce(0) { $0 + $1.totalHours }
        } else {
            completedGross = AggregationService.totalGross(for: shifts, in: earnedWindow)
            completedHours = AggregationService.totalHours(for: shifts, in: earnedWindow)
        }
        var openGross = openShiftBreakdown?.grossEarnings ?? 0
        var openHours = openShiftBreakdown?.totalHours ?? 0
        if let configuration, !openShifts.isEmpty {
            let allocated = openShifts.map {
                ShiftEarningsAllocation.partial(
                    start: $0.startDate, end: min(date, $0.scheduledEndDate ?? date), within: earnedWindow,
                    configuration: configuration, historicalShifts: shifts, calendar: calendar
                )
            }
            openGross = allocated.reduce(0) { $0 + $1.grossEarnings }
            openHours = allocated.reduce(0) { $0 + $1.totalHours }
        }
        let currentPayPeriodGross = completedGross + openGross
        let currentPayPeriodHours = completedHours + openHours
        let enabledTemplates = templates.filter(\.isEnabled)
        let resolvedConfiguration = configuration ?? JobConfiguration(
            job: JobProfile(), payRates: payRates, nightRule: NightDifferentialRule(),
            overtimeRule: nil, paySchedule: paySchedule, supplements: [], templates: templates
        )

        var planned: [DateInterval] = scheduledShifts.compactMap {
            let start = max(date, $0.startDate)
            let end = min(payPeriod.end, $0.endDate)
            return end > start ? DateInterval(start: start, end: end) : nil
        }
        planned += openShifts.compactMap {
            guard let endDate = $0.scheduledEndDate else { return nil }
            let end = min(payPeriod.end, endDate)
            return end > date ? DateInterval(start: date, end: end) : nil
        }
        var cursor = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: date)) ?? date
        while cursor < payPeriod.end {
            let weekday = calendar.component(.weekday, from: cursor)
            for template in enabledTemplates where template.weekday.rawValue == weekday && template.scheduledHours > 0 {
                let start = calendar.date(bySettingHour: template.startHour, minute: template.startMinute, second: 0, of: cursor) ?? cursor
                var end = calendar.date(bySettingHour: template.endHour, minute: template.endMinute, second: 0, of: cursor) ?? start
                if end <= start { end = calendar.date(byAdding: .day, value: 1, to: end) ?? end }
                let allocatedStart = max(date, start)
                let allocatedEnd = min(payPeriod.end, end)
                if allocatedEnd > allocatedStart {
                    planned.append(DateInterval(start: allocatedStart, end: allocatedEnd))
                }
            }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? payPeriod.end
        }

        // One-off schedules and repeating templates can describe the same work.
        // Project their union once, and carry actual hours into overtime.
        var history = shifts.filter { $0.endDate <= date }
        for open in openShifts {
            let end = min(date, open.scheduledEndDate ?? date)
            guard end > open.startDate else { continue }
            let breakdown = EarningsEngine.calculate(
                start: open.startDate, end: end, payRates: payRates,
                nightRule: resolvedConfiguration.nightRule, overtimeRule: resolvedConfiguration.overtimeRule,
                historicalShifts: history, calendar: calendar
            )
            history.append(ShiftRecord(startDate: open.startDate, endDate: end, breakdown: breakdown))
        }
        let ordered = planned.sorted { $0.start < $1.start }
        var merged: [DateInterval] = []
        for interval in ordered {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }
        var futureGross = 0.0
        for interval in merged {
            let breakdown = EarningsEngine.calculate(
                start: interval.start, end: interval.end, payRates: payRates,
                nightRule: resolvedConfiguration.nightRule, overtimeRule: resolvedConfiguration.overtimeRule,
                historicalShifts: history, calendar: calendar
            )
            futureGross += breakdown.grossEarnings
            history.append(ShiftRecord(startDate: interval.start, endDate: interval.end, breakdown: breakdown))
        }
        let projectedGross = currentPayPeriodGross + futureGross
        return (
            payPeriodGross: currentPayPeriodGross,
            payPeriodHours: currentPayPeriodHours,
            projectedGross: projectedGross,
            projectedTakeHome: max(0, projectedGross * (1 - takeHomeRate)),
            confidenceLabel: futureGross > 0 ? "Schedule projected" : "Earned so far"
        )
    }

    private static func repeatingInterval(
        for date: Date,
        anchor: Date,
        everyDays: Int,
        calendar: Calendar
    ) -> DateInterval {
        let normalizedAnchor = calendar.startOfDay(for: anchor)
        let normalizedDate = calendar.startOfDay(for: date)
        let daysSinceAnchor = calendar.dateComponents([.day], from: normalizedAnchor, to: normalizedDate).day ?? 0
        let periodIndex = Int(floor(Double(daysSinceAnchor) / Double(everyDays)))
        let start = calendar.date(byAdding: .day, value: periodIndex * everyDays, to: normalizedAnchor) ?? normalizedAnchor
        let end = calendar.date(byAdding: .day, value: everyDays, to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    private static func monthlyInterval(
        for date: Date,
        anchor: Date,
        calendar: Calendar
    ) -> DateInterval {
        let anchorDay = calendar.component(.day, from: anchor)
        let monthBase = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        func boundary(in month: Date) -> Date {
            let day = min(anchorDay, calendar.range(of: .day, in: .month, for: month)?.count ?? anchorDay)
            return calendar.date(byAdding: .day, value: day - 1, to: month) ?? month
        }
        let thisBoundary = boundary(in: monthBase)
        let startMonth = date >= thisBoundary ? monthBase : calendar.date(byAdding: .month, value: -1, to: monthBase) ?? monthBase
        let endMonth = calendar.date(byAdding: .month, value: 1, to: startMonth) ?? monthBase
        let start = boundary(in: startMonth)
        let end = boundary(in: endMonth)
        return DateInterval(start: start, end: end)
    }

    private static func semiMonthlyInterval(
        for date: Date,
        anchor: Date,
        calendar: Calendar
    ) -> DateInterval {
        let day = calendar.component(.day, from: date)
        let monthBase = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        let firstBoundaryDay = min(calendar.component(.day, from: anchor), 15)
        let secondBoundaryDay = 16

        let firstBoundary = calendar.date(bySetting: .day, value: firstBoundaryDay, of: monthBase) ?? monthBase
        let secondBoundary = calendar.date(bySetting: .day, value: secondBoundaryDay, of: monthBase) ?? monthBase

        if day >= secondBoundaryDay {
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthBase) ?? monthBase
            let nextFirst = calendar.date(bySetting: .day, value: firstBoundaryDay, of: nextMonth) ?? nextMonth
            return DateInterval(start: secondBoundary, end: nextFirst)
        }

        if day >= firstBoundaryDay {
            return DateInterval(start: firstBoundary, end: secondBoundary)
        }

        let previousMonth = calendar.date(byAdding: .month, value: -1, to: monthBase) ?? monthBase
        let previousSecond = calendar.date(bySetting: .day, value: secondBoundaryDay, of: previousMonth) ?? previousMonth
        return DateInterval(start: previousSecond, end: firstBoundary)
    }
}

enum SupplementAllocationService {
    static func allocations(
        for supplements: [JobSupplement],
        within window: DateInterval,
        calendar: Calendar = .current
    ) -> [JobSupplementAllocation] {
        supplements
            .filter(\.isEnabled)
            .compactMap { allocation(for: $0, within: window, calendar: calendar) }
            .sorted {
                if $0.jobName == $1.jobName {
                    if $0.label == $1.label {
                        return $0.frequency.rawValue < $1.frequency.rawValue
                    }
                    return $0.label < $1.label
                }
                return $0.jobName < $1.jobName
            }
    }

    static func totals(for allocations: [JobSupplementAllocation]) -> SupplementTotals {
        allocations.reduce(into: .zero) { partial, allocation in
            partial.total += allocation.amount
            partial.taxableTotal += allocation.taxableAmount
            partial.nonTaxableTotal += allocation.nonTaxableAmount
        }
    }

    static func effectiveSnapshot(
        regularGross: Double,
        supplementTotals: SupplementTotals,
        estimate: TaxEstimate,
        hours: Double
    ) -> EffectiveCompensationSnapshot {
        let effectiveGross = regularGross + supplementTotals.total

        return EffectiveCompensationSnapshot(
            supplementalTotal: supplementTotals.total,
            supplementalTaxableTotal: supplementTotals.taxableTotal,
            supplementalNonTaxableTotal: supplementTotals.nonTaxableTotal,
            effectiveGross: effectiveGross,
            effectiveTakeHome: TaxEstimator.effectiveTakeHome(
                for: regularGross,
                taxableSupplemental: supplementTotals.taxableTotal,
                nonTaxableSupplemental: supplementTotals.nonTaxableTotal,
                estimate: estimate
            ),
            effectiveHourlyRate: hours > 0 ? effectiveGross / hours : nil
        )
    }

    static func annualizedTaxableIncome(
        asOf date: Date,
        supplements: [JobSupplement],
        calendar: Calendar = .current
    ) -> Double {
        supplements
            .filter(\.isEnabled)
            .filter { isActive($0, at: date, calendar: calendar) }
            .filter { $0.taxTreatment == .taxable }
            .reduce(0) { $0 + ($1.amountPerInterval * $1.frequency.periodsPerYear) }
    }

    static func lifetimeWindow(
        through date: Date,
        supplements: [JobSupplement],
        calendar: Calendar = .current
    ) -> DateInterval? {
        let activeSupplements = supplements.filter(\.isEnabled)
        guard let start = activeSupplements.map(\.startDate).min(), date > start else {
            return nil
        }

        return DateInterval(start: calendar.startOfDay(for: start), end: date)
    }

    private static func allocation(
        for supplement: JobSupplement,
        within window: DateInterval,
        calendar: Calendar
    ) -> JobSupplementAllocation? {
        guard let activeInterval = activeInterval(for: supplement, calendar: calendar),
              let relevantWindow = intersection(window, activeInterval)
        else {
            return nil
        }

        let schedule = PaySchedule(
            frequency: supplement.frequency,
            anchorDate: calendar.startOfDay(for: supplement.anchorDate)
        )
        var resolvedInterval = ProjectionEngine.payPeriodInterval(
            for: relevantWindow.start,
            schedule: schedule,
            calendar: calendar
        )
        var totalAmount = 0.0

        while resolvedInterval.start < relevantWindow.end {
            if let overlap = intersection(relevantWindow, resolvedInterval), resolvedInterval.duration > 0 {
                let fraction = overlap.duration / resolvedInterval.duration
                totalAmount += supplement.amountPerInterval * fraction
            }

            let nextProbe = resolvedInterval.end.addingTimeInterval(1)
            let nextInterval = ProjectionEngine.payPeriodInterval(for: nextProbe, schedule: schedule, calendar: calendar)
            guard nextInterval.start > resolvedInterval.start else {
                break
            }
            resolvedInterval = nextInterval
        }

        guard totalAmount > 0.000_001 else {
            return nil
        }

        let taxableAmount = supplement.taxTreatment == .taxable ? totalAmount : 0
        let nonTaxableAmount = supplement.taxTreatment == .nonTaxable ? totalAmount : 0

        return JobSupplementAllocation(
            id: "\(supplement.id.uuidString)-\(Int(window.start.timeIntervalSince1970))-\(Int(window.end.timeIntervalSince1970))",
            supplementIdentifier: supplement.id,
            jobIdentifier: supplement.job?.id,
            jobName: supplement.job?.displayName ?? "Unknown Job",
            label: supplement.displayLabel,
            kind: supplement.kind,
            frequency: supplement.frequency,
            amount: totalAmount,
            taxableAmount: taxableAmount,
            nonTaxableAmount: nonTaxableAmount
        )
    }

    private static func activeInterval(
        for supplement: JobSupplement,
        calendar: Calendar
    ) -> DateInterval? {
        let start = calendar.startOfDay(for: supplement.startDate)
        let end = supplement.endDate.map {
            calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0)) ?? $0
        } ?? .distantFuture

        guard end > start else {
            return nil
        }

        return DateInterval(start: start, end: end)
    }

    private static func isActive(_ supplement: JobSupplement, at date: Date, calendar: Calendar) -> Bool {
        guard let interval = activeInterval(for: supplement, calendar: calendar) else {
            return false
        }

        return date >= interval.start && date < interval.end
    }

    private static func intersection(_ lhs: DateInterval, _ rhs: DateInterval) -> DateInterval? {
        let start = max(lhs.start, rhs.start)
        let end = min(lhs.end, rhs.end)
        guard end > start else {
            return nil
        }
        return DateInterval(start: start, end: end)
    }
}
