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

    static func filtered(_ shifts: [ShiftRecord], in interval: DateInterval?) -> [ShiftRecord] {
        guard let interval else { return shifts }
        return shifts.filter { shift in
            max(shift.startDate, interval.start) < min(shift.endDate, interval.end)
        }
    }

    static func highestShift(in shifts: [ShiftRecord]) -> ShiftRecord? {
        shifts.max { $0.grossEarnings < $1.grossEarnings }
    }

    static func highestPayPeriod(
        in shifts: [ShiftRecord],
        paySchedule: PaySchedule,
        calendar: Calendar = .current
    ) -> HighestPeriodRecord? {
        let grouped = Dictionary(grouping: shifts) { shift in
            ProjectionEngine.payPeriodInterval(for: shift.startDate, schedule: paySchedule, calendar: calendar).start
        }

        guard let best = grouped.max(by: { lhs, rhs in
            totalGross(for: lhs.value) < totalGross(for: rhs.value)
        }) else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let interval = ProjectionEngine.payPeriodInterval(for: best.key, schedule: paySchedule, calendar: calendar)
        return HighestPeriodRecord(
            label: "\(formatter.string(from: interval.start)) - \(formatter.string(from: interval.end.addingTimeInterval(-1)))",
            gross: totalGross(for: best.value)
        )
    }
}
