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
}

enum JobAccentStyle: String, Codable, CaseIterable, Identifiable {
    case emerald
    case sky
    case amber
    case coral
    case rose
    case slate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .emerald:
            "Emerald"
        case .sky:
            "Sky"
        case .amber:
            "Amber"
        case .coral:
            "Coral"
        case .rose:
            "Rose"
        case .slate:
            "Slate"
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

    var title: String {
        let calendar = Calendar.current
        return calendar.weekdaySymbols[rawValue - 1]
    }
}

enum LocalizedNumericInput {
    static func decimalValue(from text: String, locale: Locale = .current) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal

        if let value = formatter.number(from: trimmed)?.doubleValue {
            return value
        }

        let allowedCharacters = CharacterSet(charactersIn: "0123456789-.,")
        let sanitizedScalars = trimmed.unicodeScalars.filter { allowedCharacters.contains($0) }
        var sanitized = String(String.UnicodeScalarView(sanitizedScalars))
        guard !sanitized.isEmpty else {
            return nil
        }

        let isNegative = sanitized.hasPrefix("-")
        sanitized.removeAll { $0 == "-" }

        let separatorCharacter: Character?
        if let lastDot = sanitized.lastIndex(of: "."),
           let lastComma = sanitized.lastIndex(of: ",") {
            separatorCharacter = lastDot > lastComma ? "." : ","
        } else if sanitized.contains(".") {
            separatorCharacter = "."
        } else if sanitized.contains(",") {
            separatorCharacter = ","
        } else {
            separatorCharacter = nil
        }

        let localeDecimalSeparator = formatter.decimalSeparator ?? "."
        let decimalIndex = separatorCharacter.flatMap { sanitized.lastIndex(of: $0) }
        var normalizedDigits = ""

        for index in sanitized.indices {
            let character = sanitized[index]
            if character.isNumber {
                normalizedDigits.append(character)
            } else if let decimalIndex, index == decimalIndex {
                normalizedDigits.append(contentsOf: localeDecimalSeparator)
            }
        }

        let normalized = (isNegative ? "-" : "") + normalizedDigits

        return formatter.number(from: normalized)?.doubleValue
    }

    static func decimalText(for value: Double, locale: Locale = .current, maximumFractionDigits: Int = 2) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maximumFractionDigits

        return formatter.string(from: NSNumber(value: value)) ?? value.formatted()
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
    var estimatedWithholdingRate: Double
    var currentShiftNetEstimate: Double
}

enum PayPeriodAggregationState: Equatable {
    case unified
    case variesByJob
}

struct ActiveJobSnapshot: Identifiable, Equatable {
    var id: UUID
    var name: String
    var accent: JobAccentStyle
    var startDate: Date
    var scheduledEndDate: Date?
    var currentBreakdown: EarningsBreakdown
    var currentGross: Double
    var currentTakeHome: Double
}

struct SummaryRollup: Equatable {
    var activeShiftCount: Int
    var scheduledShiftCount: Int
    var completedShiftCount: Int
    var activeGross: Double
    var activeTakeHome: Double
    var payPeriodAggregation: PayPeriodAggregationState
    var payPeriodGross: Double
    var payPeriodTakeHome: Double
    var payPeriodHours: Double
    var payPeriodNightPremium: Double
    var projectedGross: Double
    var projectedTakeHome: Double
    var allTimeGross: Double
    var allTimeTakeHome: Double
    var allTimeHours: Double
    var weeklyGross: Double
    var totalNightPremium: Double
    var totalOvertimePremium: Double
    var totalOvertimeHours: Double
    var averageShiftGross: Double
    var averageShiftHours: Double
    var highestShiftGross: Double
    var currentBlendedRate: Double
}

struct JobSummarySnapshot: Identifiable, Equatable {
    var id: UUID
    var name: String
    var accent: JobAccentStyle
    var currentBreakdown: EarningsBreakdown?
    var annualizedGrossIncome: Double
    var payPeriodInterval: DateInterval
    var payScheduleFrequency: PayFrequency
    var projectedConfidenceLabel: String
    var rollup: SummaryRollup
}

struct SummarySnapshot: Equatable {
    var combined: SummaryRollup
    var projectedConfidenceLabel: String
    var jobs: [JobSummarySnapshot]
}

struct DashboardSnapshot: Equatable {
    var currentBreakdown: EarningsBreakdown?
    var activeJobs: [ActiveJobSnapshot]
    var currentGross: Double
    var currentTakeHome: Double
    var payPeriodAggregation: PayPeriodAggregationState
    var payPeriodGross: Double
    var payPeriodTakeHome: Double
    var payPeriodHours: Double
    var payPeriodNightPremium: Double
    var allTimeGross: Double
    var allTimeTakeHome: Double
    var projectedPaycheckGross: Double
    var projectedPaycheckTakeHome: Double
    var projectedConfidenceLabel: String
    var allTimeHours: Double
}
