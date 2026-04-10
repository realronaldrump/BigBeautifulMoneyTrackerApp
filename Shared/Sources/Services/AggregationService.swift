import Foundation

enum AggregationService {
    static func totalGross(for shifts: [ShiftRecord], in interval: DateInterval? = nil) -> Double {
        filtered(shifts, in: interval).reduce(0) { $0 + $1.grossEarnings }
    }

    static func totalHours(for shifts: [ShiftRecord], in interval: DateInterval? = nil) -> Double {
        filtered(shifts, in: interval).reduce(0) { $0 + $1.totalHours }
    }

    static func totalNightPremium(for shifts: [ShiftRecord], in interval: DateInterval? = nil) -> Double {
        filtered(shifts, in: interval).reduce(0) { $0 + $1.nightPremiumEarnings }
    }

    static func totalOvertimePremium(for shifts: [ShiftRecord], in interval: DateInterval? = nil) -> Double {
        filtered(shifts, in: interval).reduce(0) { $0 + $1.overtimePremiumEarnings }
    }

    static func totalOvertimeHours(for shifts: [ShiftRecord], in interval: DateInterval? = nil) -> Double {
        filtered(shifts, in: interval).reduce(0) { $0 + $1.overtimeHours }
    }

    static func filtered(_ shifts: [ShiftRecord], in interval: DateInterval?) -> [ShiftRecord] {
        guard let interval else { return shifts }
        return shifts.filter { shift in
            max(shift.startDate, interval.start) < min(shift.endDate, interval.end)
        }
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
