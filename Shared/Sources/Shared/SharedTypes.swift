import Foundation

enum EarningsDisplayMode: String, Codable, CaseIterable, Identifiable, Sendable {
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

    var compactTitle: String {
        switch self {
        case .gross:
            "Gross"
        case .takeHome:
            "Take Home"
        }
    }
}

enum CompensationDisplayMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case actual
    case effective

    var id: String { rawValue }

    var title: String {
        switch self {
        case .actual:
            "True"
        case .effective:
            "Effective"
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

enum JobSupplementKind: String, Codable, CaseIterable, Identifiable {
    case housingStipend
    case reimbursement
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .housingStipend:
            "Housing Stipend"
        case .reimbursement:
            "Reimbursement"
        case .other:
            "Other"
        }
    }

    var suggestedLabel: String {
        switch self {
        case .housingStipend:
            "Housing stipend"
        case .reimbursement:
            "Reimbursed expense"
        case .other:
            "Supplemental pay"
        }
    }

    var defaultTaxTreatment: SupplementTaxTreatment {
        switch self {
        case .housingStipend, .other:
            .taxable
        case .reimbursement:
            .nonTaxable
        }
    }
}

enum SupplementTaxTreatment: String, Codable, CaseIterable, Identifiable {
    case taxable
    case nonTaxable

    var id: String { rawValue }

    var title: String {
        switch self {
        case .taxable:
            "Taxable"
        case .nonTaxable:
            "Non-Taxable"
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
        var input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }
        var sign = ""
        if input.first == "-" || input.first == "+" {
            sign = String(input.removeFirst())
        }
        guard !input.isEmpty else { return nil }

        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        let localeDecimal = formatter.decimalSeparator ?? "."
        let localeGrouping = formatter.groupingSeparator ?? ","
        // Normalize the space variants used for grouping by decimal keyboards.
        let usesSpaceGrouping = localeGrouping.unicodeScalars.allSatisfy { CharacterSet.whitespaces.contains($0) }
        if usesSpaceGrouping {
            for space in [" ", "\u{00a0}", "\u{202f}"] {
                input = input.replacingOccurrences(of: space, with: localeGrouping)
            }
        }

        let allowedSeparators = Set([".", ",", localeDecimal, localeGrouping])
        guard input.allSatisfy({ character in
            character.wholeNumberValue != nil || allowedSeparators.contains(String(character))
        }) else { return nil }

        func validGrouping(_ value: String, separator: String) -> Bool {
            let groups = value.components(separatedBy: separator)
            guard groups.count > 1, let first = groups.first, !first.isEmpty else { return false }
            let primarySize = max(1, formatter.groupingSize)
            let secondarySize = formatter.secondaryGroupingSize > 0 ? formatter.secondaryGroupingSize : primarySize
            guard groups.last?.count == primarySize, first.count <= secondarySize else { return false }
            return groups.enumerated().allSatisfy { index, group in
                !group.isEmpty && group.allSatisfy { $0.wholeNumberValue != nil }
                    && (index == 0 || index == groups.count - 1 || group.count == secondarySize)
            }
        }

        var decimalSeparator: String?
        var groupingSeparator: String?
        if input.contains("."), input.contains(",") {
            decimalSeparator = input.lastIndex(of: ".")! > input.lastIndex(of: ",")! ? "." : ","
            groupingSeparator = decimalSeparator == "." ? "," : "."
        } else if input.contains(localeDecimal) {
            decimalSeparator = localeDecimal
        } else if input.contains(localeGrouping), validGrouping(input, separator: localeGrouping) {
            groupingSeparator = localeGrouping
        } else if input.contains(".") || input.contains(",") {
            decimalSeparator = input.contains(".") ? "." : ","
        }

        let parts = decimalSeparator.map { input.components(separatedBy: $0) } ?? [input]
        guard parts.count <= 2 else { return nil }
        var integer = parts[0]
        if usesSpaceGrouping, integer.contains(localeGrouping) {
            groupingSeparator = localeGrouping
        }
        if let groupingSeparator {
            guard validGrouping(integer, separator: groupingSeparator) else { return nil }
            integer = integer.replacingOccurrences(of: groupingSeparator, with: "")
        }
        let fraction = parts.count == 2 ? parts[1] : ""
        guard integer.allSatisfy({ $0.wholeNumberValue != nil }),
              fraction.allSatisfy({ $0.wholeNumberValue != nil }),
              !integer.isEmpty || !fraction.isEmpty else { return nil }
        let digits = integer.compactMap(\.wholeNumberValue).map(String.init).joined()
        let fractionalDigits = fraction.compactMap(\.wholeNumberValue).map(String.init).joined()
        let normalized = sign + (digits.isEmpty ? "0" : digits) + (parts.count == 2 ? "." + fractionalDigits : "")
        guard let value = Double(normalized), value.isFinite else { return nil }
        return value
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

struct EarningsSegment: Codable, Equatable, Sendable {
    var startDate: Date
    var endDate: Date
    var baseEarnings: Double
    var nightPremiumEarnings: Double
    var overtimePremiumEarnings: Double
    var nightHours: Double
    var overtimeHours: Double

    var hours: Double { endDate.timeIntervalSince(startDate) / 3600 }
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
    var segments: [EarningsSegment] = []
}

struct TaxEstimate: Codable, Equatable {
    var annualizedGrossIncome: Double
    var estimatedWithholdingRate: Double
    var currentShiftNetEstimate: Double
    var estimatedPayrollDeductionRate: Double = 0

    var estimatedNetRate: Double {
        max(0, 1 - estimatedWithholdingRate - estimatedPayrollDeductionRate)
    }
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
    var currentEffectiveGross: Double
    var currentEffectiveTakeHome: Double
}

struct JobSupplementAllocation: Identifiable, Equatable {
    var id: String
    var supplementIdentifier: UUID
    var jobIdentifier: UUID?
    var jobName: String
    var label: String
    var kind: JobSupplementKind
    var frequency: PayFrequency
    var amount: Double
    var taxableAmount: Double
    var nonTaxableAmount: Double
}

struct SupplementTotals: Equatable {
    var total: Double
    var taxableTotal: Double
    var nonTaxableTotal: Double

    static let zero = SupplementTotals(total: 0, taxableTotal: 0, nonTaxableTotal: 0)
}

struct EffectiveCompensationSnapshot: Equatable {
    var supplementalTotal: Double
    var supplementalTaxableTotal: Double
    var supplementalNonTaxableTotal: Double
    var effectiveGross: Double
    var effectiveTakeHome: Double
    var effectiveHourlyRate: Double?

    static let zero = EffectiveCompensationSnapshot(
        supplementalTotal: 0,
        supplementalTaxableTotal: 0,
        supplementalNonTaxableTotal: 0,
        effectiveGross: 0,
        effectiveTakeHome: 0,
        effectiveHourlyRate: nil
    )
}

struct SummaryRollup: Equatable {
    var activeShiftCount: Int
    var scheduledShiftCount: Int
    var completedShiftCount: Int
    var activeGross: Double
    var activeTakeHome: Double
    var activeEffective: EffectiveCompensationSnapshot
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
    var hasSupplementConfiguration: Bool
    var payPeriodEffective: EffectiveCompensationSnapshot
    var projectedEffective: EffectiveCompensationSnapshot
    var allTimeEffective: EffectiveCompensationSnapshot
}

struct JobSummarySnapshot: Identifiable, Equatable {
    var id: UUID
    var name: String
    var accent: JobAccentStyle
    var currentBreakdown: EarningsBreakdown?
    var annualizedGrossIncome: Double
    var annualizedTaxableSupplementIncome: Double
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
    var hasSupplementConfiguration: Bool
    var currentGross: Double
    var currentTakeHome: Double
    var currentEffectiveGross: Double
    var currentEffectiveTakeHome: Double
    var payPeriodAggregation: PayPeriodAggregationState
    var payPeriodGross: Double
    var payPeriodTakeHome: Double
    var payPeriodEffectiveGross: Double
    var payPeriodEffectiveTakeHome: Double
    var payPeriodHours: Double
    var payPeriodNightPremium: Double
    var allTimeGross: Double
    var allTimeTakeHome: Double
    var allTimeEffectiveGross: Double
    var allTimeEffectiveTakeHome: Double
    var projectedPaycheckGross: Double
    var projectedPaycheckTakeHome: Double
    var projectedPaycheckEffectiveGross: Double
    var projectedPaycheckEffectiveTakeHome: Double
    var projectedConfidenceLabel: String
    var allTimeHours: Double
}

private let compensationRateEpsilon = 0.000_001

extension ActiveJobSnapshot {
    func displayAmount(
        for mode: EarningsDisplayMode,
        compensationMode: CompensationDisplayMode
    ) -> Double {
        switch (compensationMode, mode) {
        case (.actual, .gross):
            currentGross
        case (.actual, .takeHome):
            currentTakeHome
        case (.effective, .gross):
            currentEffectiveGross
        case (.effective, .takeHome):
            currentEffectiveTakeHome
        }
    }

    func displayRate(
        for mode: EarningsDisplayMode,
        compensationMode: CompensationDisplayMode
    ) -> Double {
        guard currentBreakdown.totalHours > compensationRateEpsilon else {
            return currentBreakdown.effectiveRate
        }

        return displayAmount(for: mode, compensationMode: compensationMode) / currentBreakdown.totalHours
    }
}

extension DashboardSnapshot {
    var hasSelectableEffectiveCompensation: Bool {
        hasSupplementConfiguration
    }

    func displayAmount(
        for mode: EarningsDisplayMode,
        compensationMode: CompensationDisplayMode
    ) -> Double {
        switch (compensationMode, mode) {
        case (.actual, .gross):
            currentGross
        case (.actual, .takeHome):
            currentTakeHome
        case (.effective, .gross):
            currentEffectiveGross
        case (.effective, .takeHome):
            currentEffectiveTakeHome
        }
    }

    func currentDisplayRate(
        for mode: EarningsDisplayMode,
        compensationMode: CompensationDisplayMode
    ) -> Double? {
        guard let currentBreakdown else {
            return nil
        }
        guard currentBreakdown.totalHours > compensationRateEpsilon else {
            return currentBreakdown.effectiveRate
        }

        return displayAmount(for: mode, compensationMode: compensationMode) / currentBreakdown.totalHours
    }

    func payPeriodAmount(
        for mode: EarningsDisplayMode,
        compensationMode: CompensationDisplayMode
    ) -> Double {
        switch (compensationMode, mode) {
        case (.actual, .gross):
            payPeriodGross
        case (.actual, .takeHome):
            payPeriodTakeHome
        case (.effective, .gross):
            payPeriodEffectiveGross
        case (.effective, .takeHome):
            payPeriodEffectiveTakeHome
        }
    }

    func projectedPaycheckAmount(
        for mode: EarningsDisplayMode,
        compensationMode: CompensationDisplayMode
    ) -> Double {
        switch (compensationMode, mode) {
        case (.actual, .gross):
            projectedPaycheckGross
        case (.actual, .takeHome):
            projectedPaycheckTakeHome
        case (.effective, .gross):
            projectedPaycheckEffectiveGross
        case (.effective, .takeHome):
            projectedPaycheckEffectiveTakeHome
        }
    }

    func allTimeAmount(
        for mode: EarningsDisplayMode,
        compensationMode: CompensationDisplayMode
    ) -> Double {
        switch (compensationMode, mode) {
        case (.actual, .gross):
            allTimeGross
        case (.actual, .takeHome):
            allTimeTakeHome
        case (.effective, .gross):
            allTimeEffectiveGross
        case (.effective, .takeHome):
            allTimeEffectiveTakeHome
        }
    }
}
