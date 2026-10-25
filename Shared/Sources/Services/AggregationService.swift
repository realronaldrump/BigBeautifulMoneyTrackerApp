import Foundation

enum AggregationService {
    static func totalGross(for shifts: [ShiftRecord], in interval: DateInterval? = nil) -> Double {
        shifts.reduce(0) { $0 + $1.grossEarnings * allocationFraction(for: $1, in: interval) }
    }

    static func totalHours(for shifts: [ShiftRecord], in interval: DateInterval? = nil) -> Double {
        shifts.reduce(0) { $0 + $1.totalHours * allocationFraction(for: $1, in: interval) }
    }

    static func totalNightPremium(for shifts: [ShiftRecord], in interval: DateInterval? = nil) -> Double {
        shifts.reduce(0) { $0 + $1.nightPremiumEarnings * allocationFraction(for: $1, in: interval) }
    }

    static func totalOvertimePremium(for shifts: [ShiftRecord], in interval: DateInterval? = nil) -> Double {
        shifts.reduce(0) { $0 + $1.overtimePremiumEarnings * allocationFraction(for: $1, in: interval) }
    }

    static func totalOvertimeHours(for shifts: [ShiftRecord], in interval: DateInterval? = nil) -> Double {
        shifts.reduce(0) { $0 + $1.overtimeHours * allocationFraction(for: $1, in: interval) }
    }

    static func filtered(_ shifts: [ShiftRecord], in interval: DateInterval?) -> [ShiftRecord] {
        guard let interval else { return shifts }
        return shifts.filter { shift in
            max(shift.startDate, interval.start) < min(shift.endDate, interval.end)
        }
    }

    // Without rate/rule history, allocate stored totals by elapsed time. Callers
    // with a job configuration use ShiftEarningsAllocation for exact segments.
    private static func allocationFraction(for shift: ShiftRecord, in interval: DateInterval?) -> Double {
        guard let interval else { return 1 }
        let duration = shift.endDate.timeIntervalSince(shift.startDate)
        guard duration > 0 else { return 0 }
        let overlap = min(shift.endDate, interval.end).timeIntervalSince(max(shift.startDate, interval.start))
        return min(1, max(0, overlap / duration))
    }

    static func highestShift(in shifts: [ShiftRecord]) -> ShiftRecord? {
        shifts.max { $0.grossEarnings < $1.grossEarnings }
    }
    static func averageShiftGross(for shifts: [ShiftRecord]) -> Double {
        guard !shifts.isEmpty else { return 0 }
        return totalGross(for: shifts) / Double(shifts.count)
    }

    static func averageShiftHours(for shifts: [ShiftRecord]) -> Double {
        guard !shifts.isEmpty else { return 0 }
        return totalHours(for: shifts) / Double(shifts.count)
    }
}
