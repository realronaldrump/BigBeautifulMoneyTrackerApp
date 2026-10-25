import Foundation

/// One allocation path for dashboards, charts, projections, and pay-period exports.
enum ShiftEarningsAllocation {
    static func completed(
        _ shift: ShiftRecord,
        within interval: DateInterval,
        configuration: JobConfiguration,
        historicalShifts: [ShiftRecord],
        calendar: Calendar = .current
    ) -> EarningsBreakdown {
        let start = max(shift.startDate, interval.start)
        let end = min(shift.endDate, interval.end)
        guard end > start, shift.endDate > shift.startDate else { return .zero }
        let stored = stored(shift)
        if start == shift.startDate, end == shift.endDate { return stored }
        let savedSegments = shift.earningsSegments
        if !savedSegments.isEmpty {
            return allocatedSegments(savedSegments, within: interval)
        }

        let fraction = end.timeIntervalSince(start) / shift.endDate.timeIntervalSince(shift.startDate)
        guard !configuration.payRates.isEmpty else { return stored.scaled(by: fraction) }

        let prior = historicalShifts.filter { $0.id != shift.id && $0.endDate <= shift.startDate }
        let segment = partial(start: shift.startDate, end: end, within: interval, configuration: configuration, historicalShifts: prior, calendar: calendar)
        let full = EarningsEngine.calculate(
            start: shift.startDate, end: shift.endDate,
            payRates: configuration.payRates, nightRule: configuration.nightRule,
            overtimeRule: configuration.overtimeRule, historicalShifts: prior, calendar: calendar
        )

        // Saved earnings are authoritative. If settings have since changed, use
        // the segment weights without creating or losing money between periods.
        func allocated(_ saved: Double, _ part: Double, _ total: Double) -> Double {
            saved * (total > 0.000_001 ? min(1, max(0, part / total)) : fraction)
        }
        let base = allocated(stored.baseEarnings, segment.baseEarnings, full.baseEarnings)
        let night = allocated(stored.nightPremiumEarnings, segment.nightPremiumEarnings, full.nightPremiumEarnings)
        let overtime = allocated(stored.overtimePremiumEarnings, segment.overtimePremiumEarnings, full.overtimePremiumEarnings)
        let gross = base + night + overtime
        return EarningsBreakdown(
            totalHours: stored.totalHours * fraction,
            grossEarnings: gross,
            baseEarnings: base,
            nightPremiumEarnings: night,
            overtimePremiumEarnings: overtime,
            regularHours: allocated(stored.regularHours, segment.regularHours, full.regularHours),
            nightHours: allocated(stored.nightHours, segment.nightHours, full.nightHours),
            overtimeHours: allocated(stored.overtimeHours, segment.overtimeHours, full.overtimeHours),
            effectiveRate: segment.totalHours > 0 ? gross / segment.totalHours : 0
        )
    }

    static func partial(
        start: Date,
        end: Date,
        within interval: DateInterval,
        configuration: JobConfiguration,
        historicalShifts: [ShiftRecord],
        calendar: Calendar = .current
    ) -> EarningsBreakdown {
        let allocatedStart = max(start, interval.start)
        let allocatedEnd = min(end, interval.end)
        guard allocatedEnd > allocatedStart else { return .zero }
        let throughEnd = EarningsEngine.calculate(
            start: start, end: allocatedEnd,
            payRates: configuration.payRates, nightRule: configuration.nightRule,
            overtimeRule: configuration.overtimeRule, historicalShifts: historicalShifts, calendar: calendar
        )
        guard allocatedStart > start else { return throughEnd }
        let before = EarningsEngine.calculate(
            start: start, end: allocatedStart,
            payRates: configuration.payRates, nightRule: configuration.nightRule,
            overtimeRule: configuration.overtimeRule, historicalShifts: historicalShifts, calendar: calendar
        )
        return throughEnd.subtracting(before)
    }

    static func stored(_ shift: ShiftRecord) -> EarningsBreakdown {
        EarningsBreakdown(
            totalHours: shift.totalHours, grossEarnings: shift.grossEarnings,
            baseEarnings: shift.baseEarnings, nightPremiumEarnings: shift.nightPremiumEarnings,
            overtimePremiumEarnings: shift.overtimePremiumEarnings,
            regularHours: shift.regularHours, nightHours: shift.nightHours,
            overtimeHours: shift.overtimeHours, effectiveRate: shift.effectiveRateAtClockOut,
            segments: shift.earningsSegments
        )
    }

    private static func allocatedSegments(_ segments: [EarningsSegment], within interval: DateInterval) -> EarningsBreakdown {
        let parts = segments.compactMap { segment -> EarningsBreakdown? in
            let start = max(segment.startDate, interval.start)
            let end = min(segment.endDate, interval.end)
            guard end > start, segment.hours > 0 else { return nil }
            let hours = end.timeIntervalSince(start) / 3600
            let fraction = hours / segment.hours
            let base = segment.baseEarnings * fraction
            let night = segment.nightPremiumEarnings * fraction
            let overtime = segment.overtimePremiumEarnings * fraction
            return EarningsBreakdown(
                totalHours: hours, grossEarnings: base + night + overtime,
                baseEarnings: base, nightPremiumEarnings: night, overtimePremiumEarnings: overtime,
                regularHours: max(0, hours - segment.nightHours * fraction),
                nightHours: segment.nightHours * fraction, overtimeHours: segment.overtimeHours * fraction,
                effectiveRate: (base + night + overtime) / hours
            )
        }
        func sum(_ field: KeyPath<EarningsBreakdown, Double>) -> Double { parts.reduce(0) { $0 + $1[keyPath: field] } }
        let hours = sum(\.totalHours)
        let gross = sum(\.grossEarnings)
        return EarningsBreakdown(
            totalHours: hours, grossEarnings: gross,
            baseEarnings: sum(\.baseEarnings), nightPremiumEarnings: sum(\.nightPremiumEarnings),
            overtimePremiumEarnings: sum(\.overtimePremiumEarnings),
            regularHours: sum(\.regularHours), nightHours: sum(\.nightHours), overtimeHours: sum(\.overtimeHours),
            effectiveRate: hours > 0 ? gross / hours : 0
        )
    }
}

extension EarningsBreakdown {
    static let zero = EarningsBreakdown(
        totalHours: 0, grossEarnings: 0, baseEarnings: 0, nightPremiumEarnings: 0,
        overtimePremiumEarnings: 0, regularHours: 0, nightHours: 0, overtimeHours: 0, effectiveRate: 0
    )

    func scaled(by fraction: Double) -> EarningsBreakdown {
        EarningsBreakdown(
            totalHours: totalHours * fraction, grossEarnings: grossEarnings * fraction,
            baseEarnings: baseEarnings * fraction, nightPremiumEarnings: nightPremiumEarnings * fraction,
            overtimePremiumEarnings: overtimePremiumEarnings * fraction,
            regularHours: regularHours * fraction, nightHours: nightHours * fraction,
            overtimeHours: overtimeHours * fraction, effectiveRate: effectiveRate
        )
    }

    func subtracting(_ other: EarningsBreakdown) -> EarningsBreakdown {
        let hours = max(0, totalHours - other.totalHours)
        let gross = max(0, grossEarnings - other.grossEarnings)
        return EarningsBreakdown(
            totalHours: hours, grossEarnings: gross,
            baseEarnings: max(0, baseEarnings - other.baseEarnings),
            nightPremiumEarnings: max(0, nightPremiumEarnings - other.nightPremiumEarnings),
            overtimePremiumEarnings: max(0, overtimePremiumEarnings - other.overtimePremiumEarnings),
            regularHours: max(0, regularHours - other.regularHours),
            nightHours: max(0, nightHours - other.nightHours),
            overtimeHours: max(0, overtimeHours - other.overtimeHours),
            effectiveRate: hours > 0 ? gross / hours : 0
        )
    }
}
