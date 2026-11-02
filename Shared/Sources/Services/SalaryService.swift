import Foundation
import SwiftData

struct SalaryDashboardSnapshot: Identifiable, Equatable {
    var id: UUID
    var name: String
    var accent: JobAccentStyle
    var interval: DateInterval
    var frequency: PayFrequency
    var gross: Double
    var takeHome: Double
    var expectedGross: Double
    var expectedTakeHome: Double
    var todayGross: Double
    var todayTakeHome: Double
    var monthGross: Double
    var yearGross: Double
    var allTimeGross: Double
    var annualGross: Double
    var payday: Date
    var effectiveDate: Date
    var isUpcoming: Bool
    var accrualDescription: String
    var loggedHours: Double
    var timeZoneIdentifier: String = TimeZone.current.identifier

    var progress: Double { expectedGross > 0 ? min(1, max(0, gross / expectedGross)) : 0 }
    var effectiveHourlyRate: Double? { loggedHours > 0 ? gross / loggedHours : nil }
    func amount(for mode: EarningsDisplayMode) -> Double { mode == .gross ? gross : takeHome }
    func expectedAmount(for mode: EarningsDisplayMode) -> Double { mode == .gross ? expectedGross : expectedTakeHome }
}

enum SalaryEngine {
    static func dateLabel(_ date: Date, calendar: Calendar) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted)
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }

    static func displayRange(_ interval: DateInterval, calendar: Calendar) -> String {
        let lastDay = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
        return "\(dateLabel(interval.start, calendar: calendar)) – \(dateLabel(lastDay, calendar: calendar))"
    }

    static func activePlan(in plans: [SalaryPlan], at date: Date) -> SalaryPlan? {
        plans.filter { $0.effectiveDate <= date && ($0.endDate ?? .distantFuture) > date }
            .max { $0.effectiveDate < $1.effectiveDate }
    }

    static func period(for plan: SalaryPlan, at date: Date) -> DateInterval {
        ProjectionEngine.payPeriodInterval(
            for: date, frequency: plan.frequency, anchorDate: plan.anchorDate, calendar: plan.calendar)
    }

    /// All intervals are half open. Each dated agreement is priced against its
    /// original complete pay period, including partial first/last periods.
    static func gross(for plans: [SalaryPlan], within window: DateInterval, through date: Date) -> Double {
        let cutoff = min(window.end, date)
        guard cutoff > window.start else { return 0 }
        return plans.reduce(0) { total, plan in
            guard plan.amount.isFinite, plan.amount > 0 else { return total }
            let start = max(window.start, plan.effectiveDate)
            let end = min(cutoff, plan.endDate ?? cutoff)
            guard end > start else { return total }
            var cursor = start
            var amount = 0.0
            while cursor < end {
                let interval = period(for: plan, at: cursor)
                let allocatedEnd = min(end, interval.end)
                guard allocatedEnd > cursor else { break }
                amount +=
                    plan.paycheckGross
                    * fraction(
                        for: plan, in: interval,
                        allocated: DateInterval(start: cursor, end: allocatedEnd))
                cursor = allocatedEnd
            }
            return total + amount
        }
    }

    private static func fraction(for plan: SalaryPlan, in period: DateInterval, allocated: DateInterval) -> Double {
        guard period.duration > 0, allocated.duration > 0 else { return 0 }
        if allocated.start <= period.start && allocated.end >= period.end { return 1 }
        if plan.accrualMode == .continuous {
            return min(1, max(0, allocated.duration / period.duration))
        }
        let calendar = plan.calendar
        var day = calendar.startOfDay(for: period.start)
        var total = 0.0
        var elapsed = 0.0
        while day < period.end {
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day), nextDay > day else { break }
            if plan.weekdays.contains(calendar.component(.weekday, from: day)) {
                let start: Date
                let end: Date
                if plan.usesWorkHours {
                    start =
                        calendar.date(
                            bySettingHour: plan.startMinute / 60,
                            minute: plan.startMinute % 60, second: 0, of: day) ?? day
                    end =
                        calendar.date(
                            bySettingHour: plan.endMinute / 60,
                            minute: plan.endMinute % 60, second: 0, of: day) ?? nextDay
                } else {
                    start = day
                    end = nextDay
                }
                let clippedStart = max(start, period.start)
                let clippedEnd = min(end, period.end)
                total += max(0, clippedEnd.timeIntervalSince(clippedStart))
                elapsed += max(0, min(clippedEnd, allocated.end).timeIntervalSince(max(clippedStart, allocated.start)))
            }
            day = nextDay
        }
        return total > 0 ? min(1, max(0, elapsed / total)) : 0
    }

    static func lifetimeGross(for plans: [SalaryPlan], through date: Date) -> Double {
        guard let start = plans.map(\.effectiveDate).min(), date > start else { return 0 }
        return gross(for: plans, within: DateInterval(start: start, end: date), through: date)
    }

    static func periods(for plans: [SalaryPlan], from start: Date, through date: Date) -> [DateInterval] {
        var intervals: Set<DateInterval> = []
        for plan in plans {
            let end = min(date, plan.endDate ?? date)
            var cursor = max(start, plan.effectiveDate)
            while cursor <= end {
                let interval = period(for: plan, at: cursor)
                if interval.end > plan.effectiveDate && interval.start < (plan.endDate ?? .distantFuture) {
                    intervals.insert(interval)
                }
                guard interval.end > cursor else { break }
                cursor = interval.end
            }
        }
        return intervals.sorted { $0.start > $1.start }
    }

    static func nextPayday(for plans: [SalaryPlan], at date: Date, plan: SalaryPlan) -> Date {
        let calendar = plan.calendar
        let today = calendar.startOfDay(for: date)
        let searchStart = calendar.date(byAdding: .day, value: -90, to: today) ?? today
        let current = period(for: plan, at: max(date, plan.effectiveDate))
        let searchEnd = calendar.date(byAdding: .day, value: 90, to: max(date, plan.effectiveDate)) ?? current.end
        let candidates = periods(for: plans, from: searchStart, through: searchEnd).compactMap { interval -> Date? in
            guard gross(for: plans, within: interval, through: interval.end) > 0,
                let agreement = plans.filter({ period(for: $0, at: max(interval.start, $0.effectiveDate)) == interval })
                    .max(by: { $0.effectiveDate < $1.effectiveDate })
            else { return nil }
            let payday =
                agreement.calendar.date(byAdding: .day, value: agreement.paydayOffsetDays, to: interval.end)
                ?? interval.end
            return payday >= today ? payday : nil
        }
        return candidates.min() ?? calendar.date(byAdding: .day, value: plan.paydayOffsetDays, to: current.end)
            ?? current.end
    }

    static func snapshot(
        job: JobProfile, plans: [SalaryPlan], workLogs: [SalaryWorkLog] = [],
        taxProfile: TaxProfile, at date: Date
    ) -> SalaryDashboardSnapshot? {
        let plans = plans.filter { $0.job?.id == job.id }
        guard !job.isArchived,
            let plan = activePlan(in: plans, at: date)
                ?? plans.filter({ $0.effectiveDate > date }).min(by: { $0.effectiveDate < $1.effectiveDate })
        else { return nil }
        let upcoming = plan.effectiveDate > date
        let calendar = plan.calendar
        let interval = period(for: plan, at: upcoming ? plan.effectiveDate : date)
        let earned = gross(for: plans, within: interval, through: date)
        let expected = gross(for: plans, within: interval, through: interval.end)
        let estimate = TaxEstimator.estimate(
            currentGross: 0, annualizedGrossIncome: plan.annualGross,
            annualExtraWithholding: TaxEstimator.annualExtraWithholding(
                payFrequency: plan.frequency, taxProfile: taxProfile),
            taxProfile: taxProfile, payFrequency: plan.frequency)
        let today = calendar.dateInterval(of: .day, for: date)!
        let todayGross = gross(for: plans, within: today, through: date)
        let month = calendar.dateInterval(of: .month, for: date)!
        let year = calendar.dateInterval(of: .year, for: date)!
        return SalaryDashboardSnapshot(
            id: job.id, name: job.displayName, accent: job.accent,
            interval: interval, frequency: plan.frequency, gross: earned,
            takeHome: TaxEstimator.estimatedTakeHome(for: earned, estimate: estimate),
            expectedGross: expected,
            expectedTakeHome: TaxEstimator.estimatedTakeHome(for: expected, estimate: estimate),
            todayGross: todayGross, todayTakeHome: TaxEstimator.estimatedTakeHome(for: todayGross, estimate: estimate),
            monthGross: gross(for: plans, within: month, through: date),
            yearGross: gross(for: plans, within: year, through: date),
            allTimeGross: lifetimeGross(for: plans, through: date), annualGross: plan.annualGross,
            payday: nextPayday(for: plans, at: date, plan: plan),
            effectiveDate: plan.effectiveDate, isUpcoming: upcoming, accrualDescription: plan.accrualDescription,
            loggedHours: workLogs.filter {
                $0.job?.id == job.id && $0.date >= interval.start && $0.date <= date && $0.date < interval.end
            }.reduce(0) { $0 + $1.hours },
            timeZoneIdentifier: plan.timeZoneIdentifier)
    }
}

enum SalaryServiceError: LocalizedError {
    case invalidAmount, invalidSchedule, invalidDate, activeShift, overlapsHistory, backdatedChange, duplicatePayment,
        invalidHours
    var errorDescription: String? {
        switch self {
        case .invalidAmount: "Enter a valid amount greater than zero."
        case .invalidSchedule:
            "Choose at least one workday, valid daytime hours, and a payday from 30 days before to 60 days after the period ends."
        case .invalidDate: "Choose a valid date and a pay period whose end is after its start."
        case .activeShift: "End this job’s active shift before changing its pay type."
        case .overlapsHistory:
            "Salary would overlap hourly shifts. Choose an effective date after this job’s last completed shift."
        case .backdatedChange:
            "Choose a pay-period boundary today or later, after the previous salary start. Earlier earnings and pending changes are preserved."
        case .duplicatePayment: "A paycheck is already recorded for this job and pay period. Edit it in salary history."
        case .invalidHours: "Enter hours greater than zero, with no more than 24 total hours for a day."
        }
    }
}

enum SalaryService {
    static func validate(_ plan: SalaryPlan) throws {
        guard plan.amount.isFinite, plan.amount > 0, plan.amount <= 1_000_000_000 else {
            throw SalaryServiceError.invalidAmount
        }
        guard TimeZone(identifier: plan.timeZoneIdentifier) != nil,
            (-30...60).contains(plan.paydayOffsetDays),
            plan.accrualMode != .workdays
                || (!plan.weekdays.isEmpty && plan.weekdays.allSatisfy { (1...7).contains($0) }
                    && (!plan.usesWorkHours
                        || ((0..<1440).contains(plan.startMinute) && (1..<1440).contains(plan.endMinute)
                            && plan.endMinute > plan.startMinute)))
        else {
            throw SalaryServiceError.invalidSchedule
        }
        guard plan.effectiveDate.timeIntervalSinceReferenceDate.isFinite,
            plan.anchorDate.timeIntervalSinceReferenceDate.isFinite,
            plan.effectiveDate >= plan.calendar.date(from: DateComponents(year: 1900, month: 1, day: 1))!
        else { throw SalaryServiceError.invalidDate }
    }

    /// Save an immutable revision in one transaction. New jobs may begin in the
    /// past; later revisions cannot rewrite dates before today.
    static func savePlan(
        _ plan: SalaryPlan, for job: JobProfile, in context: ModelContext,
        now: Date = .now, save: Bool = true
    ) throws {
        try PersistenceService.requireWritable(context)
        try validate(plan)
        guard !job.isArchived else { throw SalaryServiceError.invalidDate }
        let existing = try context.fetch(FetchDescriptor<SalaryPlan>()).filter { $0.job?.id == job.id }
        let open = try context.fetch(FetchDescriptor<OpenShiftState>())
        guard !open.contains(where: { $0.job?.id == job.id }) else { throw SalaryServiceError.activeShift }
        if let previous = existing.max(by: { $0.effectiveDate < $1.effectiveDate }) {
            guard plan.effectiveDate >= plan.calendar.startOfDay(for: now), plan.effectiveDate > previous.effectiveDate
            else { throw SalaryServiceError.backdatedChange }
            if job.compensationKind == .salary {
                guard SalaryEngine.period(for: previous, at: plan.effectiveDate).start == plan.effectiveDate,
                    SalaryEngine.period(for: plan, at: plan.effectiveDate).start == plan.effectiveDate
                else { throw SalaryServiceError.backdatedChange }
            }
        }
        let shifts = try context.fetch(FetchDescriptor<ShiftRecord>()).filter { $0.job?.id == job.id }
        guard shifts.allSatisfy({ $0.endDate <= plan.effectiveDate }) else { throw SalaryServiceError.overlapsHistory }
        let schedules = try context.fetch(FetchDescriptor<ScheduledShift>()).filter { $0.job?.id == job.id }
        let templates = try context.fetch(FetchDescriptor<ScheduleTemplate>()).filter { $0.job?.id == job.id }
        for previous in existing where (previous.endDate ?? .distantFuture) > plan.effectiveDate {
            previous.endDate = plan.effectiveDate
        }
        plan.job = job
        context.insert(plan)
        job.compensationKind = .salary
        job.updatedAt = now
        // Timed hourly schedules no longer apply to a salaried job.
        for scheduled in schedules { context.delete(scheduled) }
        for template in templates { context.delete(template) }
        if save { try PersistenceService.save(context) }
    }

    static func switchToHourly(job: JobProfile, in context: ModelContext, at date: Date = .now) throws {
        try PersistenceService.requireWritable(context)
        let plans = try context.fetch(FetchDescriptor<SalaryPlan>()).filter { $0.job?.id == job.id }
        guard !plans.contains(where: { $0.effectiveDate > date }) else { throw SalaryServiceError.backdatedChange }
        for plan in plans where (plan.endDate ?? .distantFuture) > date { plan.endDate = date }
        job.compensationKind = .hourly
        job.updatedAt = date
        try PersistenceService.save(context)
    }

    static func cancelUpcomingPlan(_ plan: SalaryPlan, in context: ModelContext, now: Date = .now) throws {
        try PersistenceService.requireWritable(context)
        guard plan.effectiveDate > now, let job = plan.job else { throw SalaryServiceError.backdatedChange }
        let plans = try context.fetch(FetchDescriptor<SalaryPlan>()).filter { $0.job?.id == job.id }
        guard plans.max(by: { $0.effectiveDate < $1.effectiveDate })?.id == plan.id else {
            throw SalaryServiceError.backdatedChange
        }
        for previous in plans where previous.id != plan.id && previous.endDate == plan.effectiveDate {
            previous.endDate = nil
        }
        context.delete(plan)
        job.compensationKind =
            SalaryEngine.activePlan(in: plans.filter { $0.id != plan.id }, at: now) == nil ? .hourly : .salary
        try PersistenceService.save(context)
    }

    static func savePayment(
        job: JobProfile, interval: DateInterval, paidDate: Date, gross: Double,
        takeHome: Double?, note: String, editing: SalaryPayment? = nil,
        in context: ModelContext, now: Date = .now
    ) throws {
        try PersistenceService.requireWritable(context)
        guard interval.duration > 0, paidDate <= now,
            editing == nil || editing?.job?.id == job.id
        else { throw SalaryServiceError.invalidDate }
        let plans = try context.fetch(FetchDescriptor<SalaryPlan>()).filter { $0.job?.id == job.id }
        guard SalaryEngine.gross(for: plans, within: interval, through: interval.end) > 0 else {
            throw SalaryServiceError.invalidDate
        }
        guard gross.isFinite, gross > 0, gross <= 1_000_000_000,
            takeHome == nil || (takeHome!.isFinite && takeHome! >= 0 && takeHome! <= 1_000_000_000)
        else { throw SalaryServiceError.invalidAmount }
        let existing = try context.fetch(FetchDescriptor<SalaryPayment>())
        guard
            !existing.contains(where: {
                $0.id != editing?.id && $0.job?.id == job.id && $0.periodStart < interval.end
                    && $0.periodEnd > interval.start
            })
        else { throw SalaryServiceError.duplicatePayment }
        let record =
            editing
            ?? SalaryPayment(
                job: job, periodStart: interval.start, periodEnd: interval.end, paidDate: paidDate, gross: gross)
        record.periodStart = interval.start
        record.periodEnd = interval.end
        record.paidDate = paidDate
        record.gross = gross
        record.takeHome = takeHome
        record.note = note
        if editing == nil { context.insert(record) }
        try PersistenceService.save(context)
    }

    static func saveWorkLog(
        job: JobProfile, date: Date, hours: Double, note: String,
        editing: SalaryWorkLog? = nil, in context: ModelContext, now: Date = .now
    ) throws {
        try PersistenceService.requireWritable(context)
        guard date <= now, editing == nil || editing?.job?.id == job.id else { throw SalaryServiceError.invalidDate }
        let plans = try context.fetch(FetchDescriptor<SalaryPlan>()).filter { $0.job?.id == job.id }
        let calendar = SalaryEngine.activePlan(in: plans, at: date)?.calendar ?? plans.last?.calendar ?? .current
        let day = calendar.dateInterval(of: .day, for: date)!
        guard plans.contains(where: { $0.effectiveDate < day.end && ($0.endDate ?? .distantFuture) > day.start }) else {
            throw SalaryServiceError.invalidDate
        }
        let existing = try context.fetch(FetchDescriptor<SalaryWorkLog>()).filter {
            $0.job?.id == job.id && $0.id != editing?.id && $0.date >= day.start && $0.date < day.end
        }.reduce(0) { $0 + $1.hours }
        guard hours.isFinite, hours > 0, hours + existing <= 24 else { throw SalaryServiceError.invalidHours }
        let record = editing ?? SalaryWorkLog(job: job, date: date, hours: hours)
        record.date = date
        record.hours = hours
        record.note = note
        if editing == nil { context.insert(record) }
        try PersistenceService.save(context)
    }
}
