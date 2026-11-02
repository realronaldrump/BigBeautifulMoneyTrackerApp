import Foundation
import SwiftData

enum CompensationKind: String, CaseIterable, Identifiable, Codable {
    case hourly, salary
    var id: String { rawValue }
    var title: String { self == .hourly ? "Hourly" : "Salary" }
}

enum SalaryAmountBasis: String, CaseIterable, Identifiable, Codable {
    case annual, perPaycheck
    var id: String { rawValue }
    var title: String { self == .annual ? "Annual salary" : "Per paycheck" }
}

enum SalaryAccrualMode: String, CaseIterable, Identifiable, Codable {
    case continuous, workdays
    var id: String { rawValue }
    var title: String { self == .continuous ? "Continuous" : "Selected workdays" }
}

/// A dated salary agreement. Revisions close the previous agreement; its
/// amount, pay cycle, time zone and visualization settings remain intact.
@Model
final class SalaryPlan {
    @Attribute(.unique) var id: UUID
    var job: JobProfile?
    var effectiveDate: Date
    var endDate: Date?
    var amount: Double
    var amountBasisRawValue: String
    var frequencyRawValue: String
    var anchorDate: Date
    var paydayOffsetDays: Int
    var accrualModeRawValue: String
    var weekdaysRawValue: String
    var usesWorkHours: Bool
    var startMinute: Int
    var endMinute: Int
    var timeZoneIdentifier: String

    init(
        id: UUID = UUID(), job: JobProfile? = nil, effectiveDate: Date,
        amount: Double, amountBasis: SalaryAmountBasis = .annual,
        frequency: PayFrequency = .biweekly, anchorDate: Date,
        paydayOffsetDays: Int = 0, accrualMode: SalaryAccrualMode = .continuous,
        weekdays: Set<Int> = [2, 3, 4, 5, 6], usesWorkHours: Bool = false,
        startMinute: Int = 9 * 60, endMinute: Int = 17 * 60,
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) {
        self.id = id
        self.job = job
        self.effectiveDate = effectiveDate
        self.amount = amount
        self.amountBasisRawValue = amountBasis.rawValue
        self.frequencyRawValue = frequency.rawValue
        self.anchorDate = anchorDate
        self.paydayOffsetDays = paydayOffsetDays
        self.accrualModeRawValue = accrualMode.rawValue
        self.weekdaysRawValue = weekdays.sorted().map(String.init).joined(separator: ",")
        self.usesWorkHours = usesWorkHours
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    var amountBasis: SalaryAmountBasis { SalaryAmountBasis(rawValue: amountBasisRawValue) ?? .annual }
    var frequency: PayFrequency { PayFrequency(rawValue: frequencyRawValue) ?? .biweekly }
    var accrualMode: SalaryAccrualMode { SalaryAccrualMode(rawValue: accrualModeRawValue) ?? .continuous }
    var weekdays: Set<Int> { Set(weekdaysRawValue.split(separator: ",").compactMap { Int($0) }) }
    var paycheckGross: Double { amountBasis == .annual ? amount / frequency.periodsPerYear : amount }
    var annualGross: Double { paycheckGross * frequency.periodsPerYear }
    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return value
    }
    var paySchedule: PaySchedule { PaySchedule(frequency: frequency, anchorDate: anchorDate) }
    var accrualDescription: String {
        accrualMode == .continuous
            ? "Across every day of the pay period"
            : (usesWorkHours ? "During your selected workdays and hours" : "Across your selected workdays")
    }
}

/// Actual deposits are entered explicitly and never counted as extra earnings.
@Model
final class SalaryPayment {
    @Attribute(.unique) var id: UUID
    var job: JobProfile?
    var periodStart: Date
    var periodEnd: Date
    var paidDate: Date
    var gross: Double
    var takeHome: Double?
    var note: String

    init(
        id: UUID = UUID(), job: JobProfile? = nil, periodStart: Date, periodEnd: Date,
        paidDate: Date, gross: Double, takeHome: Double? = nil, note: String = ""
    ) {
        self.id = id
        self.job = job
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.paidDate = paidDate
        self.gross = gross
        self.takeHome = takeHome
        self.note = note
    }
}

/// Optional hours measure effective pay without changing fixed salary earnings.
@Model
final class SalaryWorkLog {
    @Attribute(.unique) var id: UUID
    var job: JobProfile?
    var date: Date
    var hours: Double
    var note: String

    init(id: UUID = UUID(), job: JobProfile? = nil, date: Date, hours: Double, note: String = "") {
        self.id = id
        self.job = job
        self.date = date
        self.hours = hours
        self.note = note
    }
}
