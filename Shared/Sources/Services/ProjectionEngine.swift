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
        calendar: Calendar = .current
    ) -> (payPeriodGross: Double, payPeriodHours: Double, projectedGross: Double, projectedTakeHome: Double, confidenceLabel: String) {
        let payPeriod = payPeriodInterval(for: date, schedule: paySchedule, calendar: calendar)
        let completedInPayPeriod = AggregationService.filtered(shifts, in: payPeriod)
        let completedGross = AggregationService.totalGross(for: completedInPayPeriod)
        let completedHours = AggregationService.totalHours(for: completedInPayPeriod)
        let openGross = openShiftBreakdown?.grossEarnings ?? 0
        let openHours = openShiftBreakdown?.totalHours ?? 0
        let currentPayPeriodGross = completedGross + openGross
        let currentPayPeriodHours = completedHours + openHours

        let enabledTemplates = templates.filter(\.isEnabled)
        guard !enabledTemplates.isEmpty else {
            return (
                payPeriodGross: currentPayPeriodGross,
                payPeriodHours: currentPayPeriodHours,
                projectedGross: currentPayPeriodGross,
                projectedTakeHome: currentPayPeriodGross * (1 - takeHomeRate),
                confidenceLabel: "Earned so far"
            )
        }

        let currentRate = EarningsEngine.payRate(at: date, payRates: payRates)
        var remainingTemplateGross = 0.0
        let normalizedStart = max(date, payPeriod.start)
        var cursor = calendar.startOfDay(for: normalizedStart)

        while cursor < payPeriod.end {
            let weekday = calendar.component(.weekday, from: cursor)
            for template in enabledTemplates where template.weekday.rawValue == weekday {
                let templateStart = calendar.date(bySettingHour: template.startHour, minute: template.startMinute, second: 0, of: cursor) ?? cursor
                if templateStart >= normalizedStart && templateStart < payPeriod.end {
                    remainingTemplateGross += template.scheduledHours * currentRate
                }
            }

            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? payPeriod.end
        }

        let projectedGross = currentPayPeriodGross + remainingTemplateGross
        return (
            payPeriodGross: currentPayPeriodGross,
            payPeriodHours: currentPayPeriodHours,
            projectedGross: projectedGross,
            projectedTakeHome: projectedGross * (1 - takeHomeRate),
            confidenceLabel: "Template projected"
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
        let day = calendar.component(.day, from: anchor)
        let components = calendar.dateComponents([.year, .month], from: date)
        let base = calendar.date(from: components) ?? date
        let startThisMonth = calendar.date(bySetting: .day, value: min(day, calendar.range(of: .day, in: .month, for: base)?.count ?? day), of: base) ?? base
        let start = date >= startThisMonth ? startThisMonth : calendar.date(byAdding: .month, value: -1, to: startThisMonth) ?? startThisMonth
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
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
