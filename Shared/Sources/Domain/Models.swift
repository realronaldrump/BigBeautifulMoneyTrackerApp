import Foundation
import SwiftData

@Model
final class JobProfile {
    @Attribute(.unique) var id: UUID
    var name: String
    var accentRawValue: String
    var sortOrder: Int
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String = "Main Job",
        accent: JobAccentStyle = .emerald,
        sortOrder: Int = 0,
        isArchived: Bool = false
    ) {
        self.id = id
        self.name = name
        self.accentRawValue = accent.rawValue
        self.sortOrder = sortOrder
        self.isArchived = isArchived
        self.createdAt = .now
        self.updatedAt = .now
    }

    var accent: JobAccentStyle {
        get { JobAccentStyle(rawValue: accentRawValue) ?? .emerald }
        set { accentRawValue = newValue.rawValue }
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Job" : trimmed
    }
}

@Model
final class ShiftRecord {
    @Attribute(.unique) var id: UUID
    var job: JobProfile?
    var startDate: Date
    var endDate: Date
    var note: String
    var totalHours: Double
    var grossEarnings: Double
    var baseEarnings: Double
    var nightPremiumEarnings: Double
    var overtimePremiumEarnings: Double
    var regularHours: Double
    var nightHours: Double
    var overtimeHours: Double
    var effectiveRateAtClockOut: Double
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        job: JobProfile? = nil,
        startDate: Date,
        endDate: Date,
        note: String = "",
        breakdown: EarningsBreakdown
    ) {
        self.id = id
        self.job = job
        self.startDate = startDate
        self.endDate = endDate
        self.note = note
        self.totalHours = breakdown.totalHours
        self.grossEarnings = breakdown.grossEarnings
        self.baseEarnings = breakdown.baseEarnings
        self.nightPremiumEarnings = breakdown.nightPremiumEarnings
        self.overtimePremiumEarnings = breakdown.overtimePremiumEarnings
        self.regularHours = breakdown.regularHours
        self.nightHours = breakdown.nightHours
        self.overtimeHours = breakdown.overtimeHours
        self.effectiveRateAtClockOut = breakdown.effectiveRate
        self.createdAt = .now
        self.updatedAt = .now
    }
}

@Model
final class OpenShiftState {
    private static let defaultScheduledReminderOffsets = [30, 15, 5]

    @Attribute(.unique) var id: UUID
    var job: JobProfile?
    var startDate: Date
    var note: String
    var celebratedFirstHundred: Bool
    var scheduledEndDate: Date?
    var scheduledReminderOffsetsRawValue: String?

    init(id: UUID = UUID(), job: JobProfile? = nil, startDate: Date = .now, note: String = "") {
        self.id = id
        self.job = job
        self.startDate = startDate
        self.note = note
        self.celebratedFirstHundred = false
        self.scheduledEndDate = nil
        self.scheduledReminderOffsetsRawValue = Self.serializeScheduledReminderOffsets(Self.defaultScheduledReminderOffsets)
    }

    var scheduledReminderOffsets: [Int] {
        get {
            guard let scheduledReminderOffsetsRawValue else {
                return Self.defaultScheduledReminderOffsets
            }

            return scheduledReminderOffsetsRawValue
                .split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                .sorted(by: >)
        }
        set {
            scheduledReminderOffsetsRawValue = Self.serializeScheduledReminderOffsets(newValue)
        }
    }

    private static func serializeScheduledReminderOffsets(_ offsets: [Int]) -> String {
        offsets
            .sorted(by: >)
            .map(String.init)
            .joined(separator: ",")
    }
}

@Model
final class PayRateSchedule {
    @Attribute(.unique) var id: UUID
    var job: JobProfile?
    var effectiveDate: Date
    var hourlyRate: Double

    init(id: UUID = UUID(), job: JobProfile? = nil, effectiveDate: Date, hourlyRate: Double) {
        self.id = id
        self.job = job
        self.effectiveDate = effectiveDate
        self.hourlyRate = hourlyRate
    }
}

@Model
final class NightDifferentialRule {
    @Attribute(.unique) var id: UUID
    var job: JobProfile?
    var startHour: Int
    var endHour: Int
    var percentIncrease: Double
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        job: JobProfile? = nil,
        startHour: Int = 18,
        endHour: Int = 6,
        percentIncrease: Double = 0.07,
        isEnabled: Bool = false
    ) {
        self.id = id
        self.job = job
        self.startHour = startHour
        self.endHour = endHour
        self.percentIncrease = percentIncrease
        self.isEnabled = isEnabled
    }
}

@Model
final class OvertimeRuleSet {
    @Attribute(.unique) var id: UUID
    var job: JobProfile?
    var isEnabled: Bool
    var dailyThresholdHours: Double?
    var weeklyThresholdHours: Double?
    var dailyMultiplier: Double
    var weeklyMultiplier: Double
    var precedenceRawValue: String

    init(
        id: UUID = UUID(),
        job: JobProfile? = nil,
        isEnabled: Bool = false,
        dailyThresholdHours: Double? = 8,
        weeklyThresholdHours: Double? = 40,
        dailyMultiplier: Double = 1.5,
        weeklyMultiplier: Double = 1.5,
        precedence: OvertimePrecedence = .highestRateWins
    ) {
        self.id = id
        self.job = job
        self.isEnabled = isEnabled
        self.dailyThresholdHours = dailyThresholdHours
        self.weeklyThresholdHours = weeklyThresholdHours
        self.dailyMultiplier = dailyMultiplier
        self.weeklyMultiplier = weeklyMultiplier
        self.precedenceRawValue = precedence.rawValue
    }

    var precedence: OvertimePrecedence {
        get { OvertimePrecedence(rawValue: precedenceRawValue) ?? .highestRateWins }
        set { precedenceRawValue = newValue.rawValue }
    }
}

@Model
final class TaxProfile {
    @Attribute(.unique) var id: UUID
    var filingStatusRawValue: String
    var usesStandardDeduction: Bool
    var annualPretaxInsurance: Double
    var annualRetirementContribution: Double
    var extraFederalWithholdingPerPeriod: Double
    var extraStateWithholdingPerPeriod: Double
    var expectedWeeklyHours: Double

    init(
        id: UUID = UUID(),
        filingStatus: FilingStatus = .single,
        usesStandardDeduction: Bool = true,
        annualPretaxInsurance: Double = 0,
        annualRetirementContribution: Double = 0,
        extraFederalWithholdingPerPeriod: Double = 0,
        extraStateWithholdingPerPeriod: Double = 0,
        expectedWeeklyHours: Double = SharedConstants.fallbackExpectedWeeklyHours
    ) {
        self.id = id
        self.filingStatusRawValue = filingStatus.rawValue
        self.usesStandardDeduction = usesStandardDeduction
        self.annualPretaxInsurance = annualPretaxInsurance
        self.annualRetirementContribution = annualRetirementContribution
        self.extraFederalWithholdingPerPeriod = extraFederalWithholdingPerPeriod
        self.extraStateWithholdingPerPeriod = extraStateWithholdingPerPeriod
        self.expectedWeeklyHours = expectedWeeklyHours
    }

    var filingStatus: FilingStatus {
        get { FilingStatus(rawValue: filingStatusRawValue) ?? .single }
        set { filingStatusRawValue = newValue.rawValue }
    }
}

@Model
final class PaySchedule {
    @Attribute(.unique) var id: UUID
    var job: JobProfile?
    var frequencyRawValue: String
    var anchorDate: Date

    init(id: UUID = UUID(), job: JobProfile? = nil, frequency: PayFrequency = .biweekly, anchorDate: Date = .now) {
        self.id = id
        self.job = job
        self.frequencyRawValue = frequency.rawValue
        self.anchorDate = anchorDate
    }

    var frequency: PayFrequency {
        get { PayFrequency(rawValue: frequencyRawValue) ?? .biweekly }
        set { frequencyRawValue = newValue.rawValue }
    }
}

@Model
final class ScheduleTemplate {
    @Attribute(.unique) var id: UUID
    var job: JobProfile?
    var name: String
    var weekdayRawValue: Int
    var startHour: Int
    var startMinute: Int
    var endHour: Int
    var endMinute: Int
    var reminderMinutesBefore: Int
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        job: JobProfile? = nil,
        name: String,
        weekday: ScheduleWeekday,
        startHour: Int,
        startMinute: Int = 0,
        endHour: Int,
        endMinute: Int = 0,
        reminderMinutesBefore: Int = 30,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.job = job
        self.name = name
        self.weekdayRawValue = weekday.rawValue
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
        self.reminderMinutesBefore = reminderMinutesBefore
        self.isEnabled = isEnabled
    }

    var weekday: ScheduleWeekday {
        get { ScheduleWeekday(rawValue: weekdayRawValue) ?? .monday }
        set { weekdayRawValue = newValue.rawValue }
    }

    var scheduledHours: Double {
        let start = Double(startHour) + Double(startMinute) / 60
        let end = Double(endHour) + Double(endMinute) / 60
        return end >= start ? (end - start) : ((24 - start) + end)
    }
}

@Model
final class ScheduledShift {
    @Attribute(.unique) var id: UUID
    var job: JobProfile?
    var startDate: Date
    var endDate: Date
    var note: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        job: JobProfile? = nil,
        startDate: Date,
        endDate: Date,
        note: String = ""
    ) {
        self.id = id
        self.job = job
        self.startDate = startDate
        self.endDate = endDate
        self.note = note
        self.createdAt = .now
        self.updatedAt = .now
    }

    var duration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }
}

@Model
final class AppPreferences {
    @Attribute(.unique) var id: UUID
    var selectedDisplayModeRawValue: String
    var selectedHomeJobIdentifierRawValue: String?
    var hapticsEnabled: Bool
    var remindersEnabled: Bool
    var liveActivitiesEnabled: Bool
    var lockScreenWidgetsEnabled: Bool
    var cloudSyncEnabled: Bool
    var onboardingCompleted: Bool

    init(
        id: UUID = UUID(),
        selectedDisplayMode: EarningsDisplayMode = .gross,
        hapticsEnabled: Bool = true,
        remindersEnabled: Bool = false,
        liveActivitiesEnabled: Bool = true,
        lockScreenWidgetsEnabled: Bool = true,
        cloudSyncEnabled: Bool = true,
        onboardingCompleted: Bool = false
    ) {
        self.id = id
        self.selectedDisplayModeRawValue = selectedDisplayMode.rawValue
        self.selectedHomeJobIdentifierRawValue = nil
        self.hapticsEnabled = hapticsEnabled
        self.remindersEnabled = remindersEnabled
        self.liveActivitiesEnabled = liveActivitiesEnabled
        self.lockScreenWidgetsEnabled = lockScreenWidgetsEnabled
        self.cloudSyncEnabled = cloudSyncEnabled
        self.onboardingCompleted = onboardingCompleted
    }

    var selectedDisplayMode: EarningsDisplayMode {
        get { EarningsDisplayMode(rawValue: selectedDisplayModeRawValue) ?? .gross }
        set { selectedDisplayModeRawValue = newValue.rawValue }
    }

    var selectedHomeJobIdentifier: UUID? {
        get {
            guard let selectedHomeJobIdentifierRawValue else { return nil }
            return UUID(uuidString: selectedHomeJobIdentifierRawValue)
        }
        set {
            selectedHomeJobIdentifierRawValue = newValue?.uuidString
        }
    }
}
