import Foundation

enum EarningsDisplayMode: String, Codable, CaseIterable, Identifiable {
    case gross
    case takeHome

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gross:
            "Gross"
        case .takeHome:
            "Estimated Take Home"
        }
    }
}

enum FilingStatus: String, Codable, CaseIterable, Identifiable {
    case single
    case marriedFilingJointly
    case marriedFilingSeparately
    case headOfHousehold

    var id: String { rawValue }

    var title: String {
        switch self {
        case .single:
            "Single"
        case .marriedFilingJointly:
            "Married Filing Jointly"
        case .marriedFilingSeparately:
            "Married Filing Separately"
        case .headOfHousehold:
            "Head of Household"
        }
    }
}

enum PayFrequency: String, Codable, CaseIterable, Identifiable {
    case weekly
    case biweekly
    case semiMonthly
    case monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weekly:
            "Weekly"
        case .biweekly:
            "Biweekly"
        case .semiMonthly:
            "Semi-Monthly"
        case .monthly:
            "Monthly"
        }
    }

    var periodsPerYear: Double {
        switch self {
        case .weekly:
            52
        case .biweekly:
            26
        case .semiMonthly:
            24
        case .monthly:
            12
        }
    }
}

enum OvertimePrecedence: String, Codable, CaseIterable, Identifiable {
    case highestRateWins
    case dailyFirst
    case weeklyFirst

    var id: String { rawValue }

    var title: String {
        switch self {
        case .highestRateWins:
            "Highest Rate Wins"
        case .dailyFirst:
            "Daily First"
        case .weeklyFirst:
            "Weekly First"
        }
    }
}

enum ScheduleWeekday: Int, Codable, CaseIterable, Identifiable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7

    var id: Int { rawValue }

    var shortTitle: String {
        let calendar = Calendar.current
        return calendar.shortWeekdaySymbols[rawValue - 1]
    }

    var title: String {
        let calendar = Calendar.current
        return calendar.weekdaySymbols[rawValue - 1]
    }
}

enum MilestoneKind: String, Codable, CaseIterable, Identifiable {
    case firstHundred
    case weeklyRecord
    case allTimeRecord

    var id: String { rawValue }

    var title: String {
        switch self {
        case .firstHundred:
            "First $100"
        case .weeklyRecord:
            "Weekly Record"
        case .allTimeRecord:
            "All-Time Record"
        }
    }
}

struct EarningsBreakdown: Codable, Equatable {
    var totalHours: Double
    var grossEarnings: Double
    var baseEarnings: Double
    var nightPremiumEarnings: Double
    var overtimePremiumEarnings: Double
    var regularHours: Double
    var nightHours: Double
    var overtimeHours: Double
    var effectiveRate: Double
}

struct TaxEstimate: Codable, Equatable {
    var annualizedGrossIncome: Double
    var annualizedNetIncome: Double
    var estimatedWithholdingRate: Double
    var currentShiftNetEstimate: Double
}

struct EarningsTotals: Equatable {
    var gross: Double
    var takeHome: Double
    var hours: Double
}

struct HighestPeriodRecord: Equatable {
    var label: String
    var gross: Double
}

struct DashboardSnapshot: Equatable {
    var currentBreakdown: EarningsBreakdown?
    var currentGross: Double
    var currentTakeHome: Double
    var payPeriodGross: Double
    var payPeriodTakeHome: Double
    var payPeriodHours: Double
    var payPeriodNightPremium: Double
    var allTimeGross: Double
    var allTimeTakeHome: Double
    var projectedPaycheckGross: Double
    var projectedPaycheckTakeHome: Double
    var projectedConfidenceLabel: String
    var weeklyGross: Double
    var allTimeHours: Double
}
