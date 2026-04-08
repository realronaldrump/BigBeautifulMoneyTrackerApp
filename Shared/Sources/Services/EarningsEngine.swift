import Foundation

enum EarningsEngine {
    static func calculate(
        start: Date,
        end: Date,
        payRates: [PayRateSchedule],
        nightRule: NightDifferentialRule,
        overtimeRule: OvertimeRuleSet?,
        historicalShifts: [ShiftRecord],
        calendar: Calendar = .current
    ) -> EarningsBreakdown {
        guard end > start else {
            return EarningsBreakdown(
                totalHours: 0,
                grossEarnings: 0,
                baseEarnings: 0,
                nightPremiumEarnings: 0,
                overtimePremiumEarnings: 0,
                regularHours: 0,
                nightHours: 0,
                overtimeHours: 0,
                effectiveRate: currentRate(at: start, payRates: payRates, nightRule: nightRule, overtimeRule: overtimeRule, historicalShifts: historicalShifts, calendar: calendar)
            )
        }

        let sortedBoundaries = buildBoundaries(
            start: start,
            end: end,
            payRates: payRates,
            nightRule: nightRule,
            calendar: calendar
        )

        var baseEarnings = 0.0
        var nightPremiumEarnings = 0.0
        var overtimePremiumEarnings = 0.0
        var regularHours = 0.0
        var nightHours = 0.0
        var overtimeHours = 0.0
        var effectiveRate = 0.0

        var currentDayStart: Date?
        var currentWeekStart: Date?
        var dayHoursWorked = 0.0
        var weekHoursWorked = 0.0

        for index in 0..<(sortedBoundaries.count - 1) {
            let segmentStart = sortedBoundaries[index]
            let segmentEnd = sortedBoundaries[index + 1]
            guard segmentEnd > segmentStart else { continue }

            let dayStart = calendar.startOfDay(for: segmentStart)
            if currentDayStart != dayStart {
                currentDayStart = dayStart
                dayHoursWorked = historicalHours(
                    in: DateInterval(start: dayStart, end: calendar.date(byAdding: .day, value: 1, to: dayStart)!),
                    historicalShifts: historicalShifts
                )
            }

            let weekInterval = calendar.dateInterval(of: .weekOfYear, for: segmentStart) ?? DateInterval(start: dayStart, duration: 7 * 24 * 60 * 60)
            if currentWeekStart != weekInterval.start {
                currentWeekStart = weekInterval.start
                weekHoursWorked = historicalHours(
                    in: weekInterval,
                    historicalShifts: historicalShifts
                )
            }

            let baseRate = payRate(at: segmentStart, payRates: payRates)
            let nightPercent = isNightShift(date: segmentStart, rule: nightRule, calendar: calendar) ? nightRule.percentIncrease : 0
            var remainingHours = segmentEnd.timeIntervalSince(segmentStart) / 3600

            while remainingHours > 0.000_001 {
                let dailyThreshold = overtimeRule?.isEnabled == true ? overtimeRule?.dailyThresholdHours : nil
                let weeklyThreshold = overtimeRule?.isEnabled == true ? overtimeRule?.weeklyThresholdHours : nil
                let dailyActive = isThresholdActive(currentHours: dayHoursWorked, threshold: dailyThreshold)
                let weeklyActive = isThresholdActive(currentHours: weekHoursWorked, threshold: weeklyThreshold)

                let hoursUntilDailyThreshold = thresholdDistance(currentHours: dayHoursWorked, threshold: dailyThreshold, alreadyActive: dailyActive)
                let hoursUntilWeeklyThreshold = thresholdDistance(currentHours: weekHoursWorked, threshold: weeklyThreshold, alreadyActive: weeklyActive)
                let nextChunkHours = min(remainingHours, hoursUntilDailyThreshold, hoursUntilWeeklyThreshold)
                let chunkHours = max(nextChunkHours.isFinite ? nextChunkHours : remainingHours, 0.000_001)

                let overtimeMultiplier = resolvedMultiplier(
                    overtimeRule: overtimeRule,
                    dailyActive: dailyActive,
                    weeklyActive: weeklyActive
                )

                let effectiveChunkRate = baseRate * (1 + nightPercent) * overtimeMultiplier
                effectiveRate = effectiveChunkRate

                baseEarnings += baseRate * chunkHours
                nightPremiumEarnings += baseRate * nightPercent * chunkHours
                overtimePremiumEarnings += baseRate * (1 + nightPercent) * max(0, overtimeMultiplier - 1) * chunkHours

                if nightPercent > 0 {
                    nightHours += chunkHours
                } else {
                    regularHours += chunkHours
                }

                if overtimeMultiplier > 1 {
                    overtimeHours += chunkHours
                }

                dayHoursWorked += chunkHours
                weekHoursWorked += chunkHours
                remainingHours -= chunkHours
            }
        }

        let grossEarnings = baseEarnings + nightPremiumEarnings + overtimePremiumEarnings

        return EarningsBreakdown(
            totalHours: end.timeIntervalSince(start) / 3600,
            grossEarnings: grossEarnings,
            baseEarnings: baseEarnings,
            nightPremiumEarnings: nightPremiumEarnings,
            overtimePremiumEarnings: overtimePremiumEarnings,
            regularHours: regularHours,
            nightHours: nightHours,
            overtimeHours: overtimeHours,
            effectiveRate: effectiveRate
        )
    }

    static func currentRate(
        at moment: Date,
        payRates: [PayRateSchedule],
        nightRule: NightDifferentialRule,
        overtimeRule: OvertimeRuleSet?,
        historicalShifts: [ShiftRecord],
        calendar: Calendar = .current
    ) -> Double {
        let oneSecondEarlier = moment.addingTimeInterval(-1)
        let breakdown = calculate(
            start: oneSecondEarlier,
            end: moment,
            payRates: payRates,
            nightRule: nightRule,
            overtimeRule: overtimeRule,
            historicalShifts: historicalShifts,
            calendar: calendar
        )
        return breakdown.effectiveRate
    }

    static func payRate(at date: Date, payRates: [PayRateSchedule]) -> Double {
        let sorted = payRates.sorted { $0.effectiveDate < $1.effectiveDate }
        return sorted.last(where: { $0.effectiveDate <= date })?.hourlyRate ?? sorted.first?.hourlyRate ?? 0
    }

    private static func buildBoundaries(
        start: Date,
        end: Date,
        payRates: [PayRateSchedule],
        nightRule: NightDifferentialRule,
        calendar: Calendar
    ) -> [Date] {
        var boundaries = Set([start, end])

        for rate in payRates where rate.effectiveDate > start && rate.effectiveDate < end {
            boundaries.insert(rate.effectiveDate)
        }

        var midnightCursor = calendar.startOfDay(for: start)
        while let nextMidnight = calendar.date(byAdding: .day, value: 1, to: midnightCursor), nextMidnight < end {
            if nextMidnight > start {
                boundaries.insert(nextMidnight)
            }
            midnightCursor = nextMidnight
        }

        if let weekInterval = calendar.dateInterval(of: .weekOfYear, for: start) {
            var weekCursor = weekInterval.start
            while let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: weekCursor), nextWeek < end {
                if nextWeek > start {
                    boundaries.insert(nextWeek)
                }
                weekCursor = nextWeek
            }
        }

        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        var cursor = calendar.date(byAdding: .day, value: -1, to: startDay) ?? startDay
        let lastCursor = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay

        while cursor <= lastCursor {
            if let nightStart = calendar.date(bySettingHour: nightRule.startHour, minute: 0, second: 0, of: cursor), nightStart > start && nightStart < end {
                boundaries.insert(nightStart)
            }
            if let nightEnd = calendar.date(bySettingHour: nightRule.endHour, minute: 0, second: 0, of: cursor), nightEnd > start && nightEnd < end {
                boundaries.insert(nightEnd)
            }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? lastCursor.addingTimeInterval(1)
        }

        return boundaries.sorted()
    }

    private static func isNightShift(date: Date, rule: NightDifferentialRule, calendar: Calendar) -> Bool {
        guard rule.isEnabled else { return false }
        let hour = calendar.component(.hour, from: date)
        if rule.startHour < rule.endHour {
            return hour >= rule.startHour && hour < rule.endHour
        }
        return hour >= rule.startHour || hour < rule.endHour
    }

    private static func historicalHours(in interval: DateInterval, historicalShifts: [ShiftRecord]) -> Double {
        historicalShifts.reduce(0) { partial, shift in
            partial + overlapHours(
                firstStart: shift.startDate,
                firstEnd: shift.endDate,
                secondStart: interval.start,
                secondEnd: interval.end
            )
        }
    }

    private static func overlapHours(firstStart: Date, firstEnd: Date, secondStart: Date, secondEnd: Date) -> Double {
        let overlapStart = max(firstStart, secondStart)
        let overlapEnd = min(firstEnd, secondEnd)
        guard overlapEnd > overlapStart else { return 0 }
        return overlapEnd.timeIntervalSince(overlapStart) / 3600
    }

    private static func isThresholdActive(currentHours: Double, threshold: Double?) -> Bool {
        guard let threshold else { return false }
        return currentHours >= threshold - 0.000_001
    }

    private static func thresholdDistance(currentHours: Double, threshold: Double?, alreadyActive: Bool) -> Double {
        guard let threshold, !alreadyActive else { return .infinity }
        return max(threshold - currentHours, 0.000_001)
    }

    private static func resolvedMultiplier(
        overtimeRule: OvertimeRuleSet?,
        dailyActive: Bool,
        weeklyActive: Bool
    ) -> Double {
        guard let overtimeRule, overtimeRule.isEnabled else { return 1 }

        let dailyMultiplier = dailyActive ? overtimeRule.dailyMultiplier : 1
        let weeklyMultiplier = weeklyActive ? overtimeRule.weeklyMultiplier : 1

        switch overtimeRule.precedence {
        case .highestRateWins:
            return max(1, dailyMultiplier, weeklyMultiplier)
        case .dailyFirst:
            return dailyActive ? dailyMultiplier : max(1, weeklyMultiplier)
        case .weeklyFirst:
            return weeklyActive ? weeklyMultiplier : max(1, dailyMultiplier)
        }
    }
}
