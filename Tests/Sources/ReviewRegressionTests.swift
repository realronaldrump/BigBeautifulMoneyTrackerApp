import Foundation
import SwiftData
import XCTest
#if SWIFT_PACKAGE
@testable import MoneyTrackerCore
#else
@testable import BigBeautifulMoneyTracker
#endif

final class ReviewRegressionTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private func date(_ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private func record(job: JobProfile? = nil, start: Date, end: Date, rate: Double = 20) -> ShiftRecord {
        ShiftRecord(job: job, startDate: start, endDate: end, breakdown: EarningsEngine.calculate(
            start: start, end: end,
            payRates: [PayRateSchedule(effectiveDate: date(1, 1), hourlyRate: rate)],
            nightRule: NightDifferentialRule(), overtimeRule: nil, historicalShifts: [], calendar: calendar
        ))
    }

    private let sampleStatement = """
    Period Start Date 04/05/2026
    Pay Date 04/24/2026
    Pay Rate $25.0000
    Pay Frequency Biweekly
    Regular 40.000000 $0.0000 $1,000.00 $9,000.00
    Pay Summary
    Gross FIT Taxable Wages Taxes Deductions Net Pay
    Current $1,000.00 $970.00 $145.00 $45.00 $810.00
    YTD $9,000.00 $8,730.00 $1,305.00 $405.00 $7,290.00
    """

    func testStatementUsesReconciledCurrentTotalsAndBaseRate() throws {
        let statement = try XCTUnwrap(PayStatement(text: sampleStatement, calendar: calendar))
        XCTAssertEqual(statement.paycheck.gross, 1_000)
        XCTAssertEqual(statement.paycheck.net, 810)
        XCTAssertEqual(statement.hourlyRate, 25)
        XCTAssertEqual(statement.frequency, .biweekly)
        XCTAssertEqual(statement.periodStart, date(4, 5))
        XCTAssertEqual(statement.paidDate, date(4, 24))
        XCTAssertNil(PayStatement(text: sampleStatement.replacingOccurrences(of: "$145.00", with: "$140.00")))
        XCTAssertNil(PayStatement(text: sampleStatement.replacingOccurrences(of: "Current $", with: "YTD $")))
        XCTAssertNil(PayStatement(text: sampleStatement + "\n" + sampleStatement))
        XCTAssertNil(PaycheckReference(gross: 0, net: 0))
        XCTAssertNil(PaycheckReference(gross: .infinity, net: 10))
        XCTAssertNil(PaycheckReference(gross: 10, net: .nan))
        XCTAssertNil(PaycheckReference(gross: 10, net: 11))
        XCTAssertEqual(PaycheckReference(gross: 10, net: 0)?.netRate, 0)
        XCTAssertEqual(PaycheckReference(gross: 10, net: 10)?.netRate, 1)
    }

    @MainActor
    func testImportedPaycheckDrivesLiveAndArchivedEstimatesPerJob() throws {
        let container = AppModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        try DataBootstrapper.seedIfNeeded(in: context)
        let job = try XCTUnwrap(try JobService.jobs(in: context).first)
        let second = try JobService.createJob(in: context, name: "Second")
        let secondSchedule = try XCTUnwrap(try context.fetch(FetchDescriptor<PaySchedule>()).first { $0.job?.id == second.id })
        secondSchedule.anchorDate = date(4, 5)
        let statement = try XCTUnwrap(PayStatement(text: sampleStatement, calendar: calendar))
        let priorRate = PayRateSchedule(job: job, effectiveDate: date(3, 1), hourlyRate: 20)
        let nextRate = PayRateSchedule(job: job, effectiveDate: date(5, 1), hourlyRate: 30)
        context.insert(priorRate)
        context.insert(nextRate)
        for _ in 0..<2 {
            try JobService.savePaycheckReference(statement.paycheck, for: job, hourlyDetails: statement, in: context, calendar: calendar)
        }
        var rates = try context.fetch(FetchDescriptor<PayRateSchedule>())
        XCTAssertEqual(rates.count, 3)
        XCTAssertEqual(EarningsEngine.payRate(at: date(4, 1), payRates: rates), 20)
        XCTAssertEqual(EarningsEngine.payRate(at: date(4, 6), payRates: rates), 25)
        XCTAssertEqual(EarningsEngine.payRate(at: date(5, 5), payRates: rates), 30)
        XCTAssertNil(second.paycheckReference)
        try JobService.savePaycheckReference(PaycheckReference(gross: 100, net: 65), for: second, in: context)
        let schedule = try XCTUnwrap(try context.fetch(FetchDescriptor<PaySchedule>()).first { $0.job?.id == job.id })
        XCTAssertEqual(schedule.anchorDate, date(4, 5))
        context.insert(PayRateSchedule(job: second, effectiveDate: date(4, 5), hourlyRate: 40))
        let shift = record(job: job, start: date(4, 6), end: date(4, 7, 16), rate: 25)
        context.insert(shift)
        context.insert(OpenShiftState(job: second, startDate: date(4, 8, 10)))
        try context.save()
        let asOf = date(4, 8, 12)
        let home = try ShiftController.dashboardSnapshot(in: context, at: asOf, calendar: calendar)
        XCTAssertEqual(home.currentTakeHome, 52, accuracy: 0.001)
        XCTAssertEqual(home.payPeriodTakeHome, 862, accuracy: 0.001)
        XCTAssertEqual(home.projectedPaycheckTakeHome, 862, accuracy: 0.001)
        let schedules = try context.fetch(FetchDescriptor<PaySchedule>())
        rates = try context.fetch(FetchDescriptor<PayRateSchedule>())
        let tax = TaxProfile(extraFederalWithholdingPerPeriod: 90)
        let history = TaxEstimator.estimatedTakeHome(for: shift, allShifts: [shift], payRates: rates,
            paySchedules: schedules, templates: [], taxProfile: tax, calendar: calendar)
        XCTAssertEqual(history, 810, accuracy: 0.001)
        let archive = PayPeriodService.archiveSnapshot(asOf: asOf, jobs: [job, second], completedShifts: [shift],
            openShifts: try context.fetch(FetchDescriptor<OpenShiftState>()), paySchedules: schedules, payRates: rates,
            nightRules: [], overtimeRules: [], templates: [], taxProfile: tax, calendar: calendar)
        let combined = try XCTUnwrap(archive.sections.first { $0.isCombined }?.summaries.first)
        XCTAssertEqual(combined.estimatedTakeHome, 862, accuracy: 0.001)
        XCTAssertEqual(combined.shifts.reduce(0) { $0 + $1.estimatedTakeHome }, 862, accuracy: 0.001)
        XCTAssertEqual(combined.effectiveTakeHome, 862, accuracy: 0.001)
        try JobService.archiveJob(job, in: context)
        let archivedHome = try ShiftController.dashboardSnapshot(in: context, at: asOf, calendar: calendar)
        XCTAssertEqual(archivedHome.allTimeTakeHome, 862, accuracy: 0.001)
        try JobService.savePaycheckReference(nil, for: second, in: context)
        XCTAssertNil(second.paycheckReference)
    }

    func testFutureHistoryDoesNotMoveEarlierHoursIntoOvertime() {
        let result = EarningsEngine.calculate(
            start: date(4, 6, 8), end: date(4, 6, 16),
            payRates: [PayRateSchedule(effectiveDate: date(1, 1), hourlyRate: 20)],
            nightRule: NightDifferentialRule(),
            overtimeRule: OvertimeRuleSet(isEnabled: true, dailyThresholdHours: nil, weeklyThresholdHours: 40),
            historicalShifts: [record(start: date(4, 7, 8), end: date(4, 9, 0))],
            calendar: calendar
        )
        XCTAssertEqual(result.grossEarnings, 160, accuracy: 0.001)
        XCTAssertEqual(result.overtimeHours, 0, accuracy: 0.001)
    }

    func testCurrentRateUsesNewRateAtExactBoundary() {
        let boundary = date(4, 6, 12)
        let rate = EarningsEngine.currentRate(
            at: boundary,
            payRates: [
                PayRateSchedule(effectiveDate: date(1, 1), hourlyRate: 20),
                PayRateSchedule(effectiveDate: boundary, hourlyRate: 30)
            ],
            nightRule: NightDifferentialRule(), overtimeRule: nil, historicalShifts: [], calendar: calendar
        )
        XCTAssertEqual(rate, 30, accuracy: 0.001)
    }

    func testMonthlyAnchorKeepsOriginalDayAcrossShortMonths() {
        let schedule = PaySchedule(frequency: .monthly, anchorDate: date(1, 31))
        let january = ProjectionEngine.payPeriodInterval(for: date(2, 1), schedule: schedule, calendar: calendar)
        let february = ProjectionEngine.payPeriodInterval(for: date(3, 1), schedule: schedule, calendar: calendar)
        let march = ProjectionEngine.payPeriodInterval(for: date(3, 31), schedule: schedule, calendar: calendar)
        XCTAssertEqual(january.start, date(1, 31))
        XCTAssertEqual(january.end, date(2, 28))
        XCTAssertEqual(february.start, date(2, 28))
        XCTAssertEqual(february.end, date(3, 31))
        XCTAssertEqual(march.start, february.end)
    }

    func testProjectionAllocatesOnlyHoursInsideThePayPeriod() {
        let shift = record(start: date(4, 5, 20), end: date(4, 6, 4))
        let projection = ProjectionEngine.projectedPaycheck(
            asOf: date(4, 6, 12), shifts: [shift], openShiftBreakdown: nil,
            paySchedule: PaySchedule(frequency: .weekly, anchorDate: date(4, 6)),
            payRates: [], templates: [], takeHomeRate: 0, calendar: calendar
        )
        XCTAssertEqual(projection.payPeriodHours, 4, accuracy: 0.001)
        XCTAssertEqual(projection.payPeriodGross, 80, accuracy: 0.001)
    }

    func testAggregationConservesTotalsAcrossAdjacentWindows() {
        let shift = record(start: date(4, 5, 20), end: date(4, 6, 4))
        let first = DateInterval(start: date(4, 5), end: date(4, 6))
        let second = DateInterval(start: date(4, 6), end: date(4, 7))
        XCTAssertEqual(AggregationService.totalGross(for: [shift], in: first), 80, accuracy: 0.001)
        XCTAssertEqual(AggregationService.totalHours(for: [shift], in: second), 4, accuracy: 0.001)
        XCTAssertEqual(
            AggregationService.totalGross(for: [shift], in: first) + AggregationService.totalGross(for: [shift], in: second),
            shift.grossEarnings, accuracy: 0.001
        )
    }

    func testNumericInputRejectsPartialAndMalformedValues() {
        for text in ["12abc", "abc12", "12-34", "1.2.3", "--12", "NaN", "Infinity"] {
            XCTAssertNil(LocalizedNumericInput.decimalValue(from: text, locale: Locale(identifier: "en_US")), text)
        }
    }

    func testNumericInputReadsGroupedLocaleValues() throws {
        XCTAssertEqual(try XCTUnwrap(LocalizedNumericInput.decimalValue(from: "1,234.56", locale: Locale(identifier: "en_US"))), 1234.56, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(LocalizedNumericInput.decimalValue(from: "1.234,56", locale: Locale(identifier: "de_DE"))), 1234.56, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(LocalizedNumericInput.decimalValue(from: "1\u{202f}234,56", locale: Locale(identifier: "fr_FR"))), 1234.56, accuracy: 0.001)
    }

    func testReminderCarriesIntoPreviousHourAndWeekday() {
        let template = ScheduleTemplate(name: "Early", weekday: .sunday, startHour: 0, startMinute: 15, endHour: 8, reminderMinutesBefore: 90)
        let reminder = ReminderSchedule.weeklyComponents(for: template, calendar: calendar)
        XCTAssertEqual(reminder.weekday, ScheduleWeekday.saturday.rawValue)
        XCTAssertEqual(reminder.hour, 22)
        XCTAssertEqual(reminder.minute, 45)
    }

    func testPayrollDeductionsReduceCashTakeHomeAndInsuranceReducesFICA() {
        let insurance = TaxEstimator.estimate(
            currentGross: 1_000, annualizedGrossIncome: 52_000, annualExtraWithholding: 0,
            taxProfile: TaxProfile(annualPretaxInsurance: 5_200), payFrequency: .weekly
        )
        let retirement = TaxEstimator.estimate(
            currentGross: 1_000, annualizedGrossIncome: 52_000, annualExtraWithholding: 0,
            taxProfile: TaxProfile(annualRetirementContribution: 5_200), payFrequency: .weekly
        )
        XCTAssertEqual(insurance.estimatedPayrollDeductionRate, 0.1, accuracy: 0.0001)
        XCTAssertEqual(TaxEstimator.estimatedTakeHome(for: 1_000, estimate: insurance), 1_000 * (0.9 - insurance.estimatedWithholdingRate), accuracy: 0.001)
        XCTAssertEqual(insurance.currentShiftNetEstimate - retirement.currentShiftNetEstimate, 100 * 0.0765, accuracy: 0.001)
    }

    func testNegativePaycheckAdjustmentStillReducesWithholding() {
        let profile = TaxProfile(extraFederalWithholdingPerPeriod: -20)
        let base = TaxEstimator.estimate(currentGross: 1_000, annualizedGrossIncome: 52_000, annualExtraWithholding: 0, taxProfile: TaxProfile(), payFrequency: .weekly)
        let adjusted = TaxEstimator.estimate(currentGross: 1_000, annualizedGrossIncome: 52_000, annualExtraWithholding: TaxEstimator.annualExtraWithholding(payFrequency: .weekly, taxProfile: profile), taxProfile: profile, payFrequency: .weekly)
        XCTAssertEqual(adjusted.currentShiftNetEstimate - base.currentShiftNetEstimate, 20, accuracy: 0.001)
    }

    func testProjectionIncludesRemainingScheduledHoursAndDeduplicatesTemplates() {
        let job = JobProfile(name: "Main")
        let open = OpenShiftState(job: job, startDate: date(4, 6, 8))
        open.scheduledEndDate = date(4, 6, 18)
        let rate = PayRateSchedule(job: job, effectiveDate: date(1, 1), hourlyRate: 20)
        let template = ScheduleTemplate(job: job, name: "Monday", weekday: .monday, startHour: 8, endHour: 18)
        let schedule = PaySchedule(job: job, frequency: .weekly, anchorDate: date(4, 6))
        let rule = OvertimeRuleSet(job: job, isEnabled: true, dailyThresholdHours: 8, weeklyThresholdHours: nil)
        let config = JobService.configuration(for: job, payRates: [rate], nightRules: [], overtimeRules: [rule], paySchedules: [schedule], templates: [template])
        let result = ProjectionEngine.projectedPaycheck(
            asOf: date(4, 6, 12), shifts: [], openShiftBreakdown: nil,
            paySchedule: schedule, payRates: [rate], templates: [template], takeHomeRate: 0,
            configuration: config, openShifts: [open],
            scheduledShifts: [ScheduledShift(job: job, startDate: date(4, 6, 8), endDate: date(4, 6, 18))], calendar: calendar
        )
        XCTAssertEqual(result.payPeriodGross, 80, accuracy: 0.001)
        XCTAssertEqual(result.projectedGross, 220, accuracy: 0.001)
    }

    func testProjectionUsesFutureRatesAndClipsOvernightTemplateAtPeriodEnd() {
        let schedule = PaySchedule(frequency: .weekly, anchorDate: date(4, 6))
        let result = ProjectionEngine.projectedPaycheck(
            asOf: date(4, 12, 12), shifts: [], openShiftBreakdown: nil, paySchedule: schedule,
            payRates: [PayRateSchedule(effectiveDate: date(1, 1), hourlyRate: 20), PayRateSchedule(effectiveDate: date(4, 12, 22), hourlyRate: 30)],
            templates: [ScheduleTemplate(name: "Sunday night", weekday: .sunday, startHour: 20, endHour: 4)],
            takeHomeRate: 0, calendar: calendar
        )
        XCTAssertEqual(result.projectedGross, 100, accuracy: 0.001)
    }

    func testDSTShiftUsesElapsedHours() {
        var denver = calendar
        denver.timeZone = TimeZone(identifier: "America/Denver")!
        let start = denver.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 0))!
        let end = denver.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 8))!
        let result = EarningsEngine.calculate(start: start, end: end, payRates: [PayRateSchedule(effectiveDate: date(1, 1), hourlyRate: 20)], nightRule: NightDifferentialRule(), overtimeRule: nil, historicalShifts: [], calendar: denver)
        XCTAssertEqual(result.totalHours, 7, accuracy: 0.001)
        XCTAssertEqual(result.grossEarnings, 140, accuracy: 0.001)
    }

    func testEveryPayFrequencyProducesContiguousContainingIntervals() {
        for frequency in PayFrequency.allCases {
            for anchorDay in [1, 15, 28, 29, 30, 31] {
                let schedule = PaySchedule(frequency: frequency, anchorDate: date(1, anchorDay))
                for offset in 0..<366 {
                    let probe = calendar.date(byAdding: .day, value: offset, to: date(1, 1, 12))!
                    let interval = ProjectionEngine.payPeriodInterval(for: probe, schedule: schedule, calendar: calendar)
                    XCTAssertLessThanOrEqual(interval.start, probe)
                    XCTAssertGreaterThan(interval.end, probe)
                    let next = ProjectionEngine.payPeriodInterval(for: interval.end, schedule: schedule, calendar: calendar)
                    XCTAssertEqual(interval.end, next.start, "\(frequency) anchor \(anchorDay)")
                }
            }
        }
    }

    func testOnlyOnePayPeriodIsCurrentAtExactBoundary() {
        let job = JobProfile(name: "Main")
        let archive = PayPeriodService.archiveSnapshot(
            asOf: date(4, 6), jobs: [job], completedShifts: [record(job: job, start: date(4, 5, 8), end: date(4, 5, 16))],
            paySchedules: [PaySchedule(job: job, frequency: .weekly, anchorDate: date(4, 6))],
            payRates: [], nightRules: [], overtimeRules: [], templates: [], taxProfile: TaxProfile(), calendar: calendar
        )
        XCTAssertEqual(archive.sections[0].summaries.filter { $0.status == .current }.count, 1)
    }

    func testWeeklyOvertimeHonorsConfiguredWorkweekStart() {
        let rule = OvertimeRuleSet(isEnabled: true, dailyThresholdHours: nil, weeklyThresholdHours: 8)
        rule.workweekStartRawValue = ScheduleWeekday.tuesday.rawValue
        let result = EarningsEngine.calculate(
            start: date(4, 7, 8), end: date(4, 7, 16),
            payRates: [PayRateSchedule(effectiveDate: date(1, 1), hourlyRate: 20)], nightRule: NightDifferentialRule(), overtimeRule: rule,
            historicalShifts: [record(start: date(4, 6, 8), end: date(4, 6, 16))], calendar: calendar
        )
        XCTAssertEqual(result.overtimeHours, 0, accuracy: 0.001)
        XCTAssertEqual(result.grossEarnings, 160, accuracy: 0.001)
    }

    @MainActor
    func testOverlappingHistoryRejectedForSameJobButAllowedAcrossJobs() throws {
        let container = AppModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        try DataBootstrapper.seedIfNeeded(in: context)
        let job = try XCTUnwrap(JobService.jobs(in: context).first)
        let other = try JobService.createJob(in: context, name: "Other")
        for job in [job, other] { context.insert(PayRateSchedule(job: job, effectiveDate: date(1, 1), hourlyRate: 20)) }
        try ShiftController.saveManualShift(in: context, editing: nil, job: job, startDate: date(4, 6, 8), endDate: date(4, 6, 16))
        XCTAssertThrowsError(try ShiftController.saveManualShift(in: context, editing: nil, job: job, startDate: date(4, 6, 12), endDate: date(4, 6, 18)))
        try ShiftController.saveManualShift(in: context, editing: nil, job: other, startDate: date(4, 6, 8), endDate: date(4, 6, 16))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShiftRecord>()), 2)
    }

    @MainActor
    func testScheduledReconciliationDoesNotDuplicateAlreadyWorkedTime() throws {
        let container = AppModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        try DataBootstrapper.seedIfNeeded(in: context)
        let job = try XCTUnwrap(JobService.jobs(in: context).first)
        context.insert(PayRateSchedule(job: job, effectiveDate: date(1, 1), hourlyRate: 20))
        context.insert(record(job: job, start: date(4, 6, 8), end: date(4, 6, 16)))
        context.insert(ScheduledShift(job: job, startDate: date(4, 6, 8), endDate: date(4, 6, 16)))
        try context.save()
        XCTAssertThrowsError(try ShiftController.reconcileScheduledShifts(in: context, at: date(4, 7)))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShiftRecord>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduledShift>()), 1)
    }

    @MainActor
    func testScheduledBatchPreflightsMissingRatesWithoutPartialWrites() throws {
        let container = AppModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        try DataBootstrapper.seedIfNeeded(in: context)
        let job = try XCTUnwrap(JobService.jobs(in: context).first)
        let other = try JobService.createJob(in: context, name: "Other")
        context.insert(PayRateSchedule(job: job, effectiveDate: date(1, 1), hourlyRate: 20))
        context.insert(ScheduledShift(job: job, startDate: date(4, 6, 8), endDate: date(4, 6, 16)))
        context.insert(ScheduledShift(job: other, startDate: date(4, 6, 9), endDate: date(4, 6, 17)))
        try context.save()
        XCTAssertThrowsError(try ShiftController.reconcileScheduledShifts(in: context, at: date(4, 7)))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShiftRecord>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduledShift>()), 2)
    }

    @MainActor
    func testEditingOpenShiftCannotMoveItsStartIntoFuture() throws {
        let container = AppModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let open = OpenShiftState(startDate: .now.addingTimeInterval(-3600))
        context.insert(open)
        try context.save()
        let original = open.startDate
        XCTAssertThrowsError(try ShiftController.updateOpenShift(in: context, editing: open, startDate: .now.addingTimeInterval(3600), scheduledEndDate: nil, reminderOffsets: []))
        XCTAssertEqual(open.startDate, original)
    }

    @MainActor
    func testArchivedJobKeepsHistoricalSupplementsInAllTimeTotals() throws {
        let container = AppModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        try DataBootstrapper.seedIfNeeded(in: context)
        let archived = try JobService.createJob(in: context, name: "Old")
        archived.isArchived = true
        archived.updatedAt = date(4, 13)
        context.insert(JobSupplement(job: archived, amountPerInterval: 70, frequency: .weekly, anchorDate: date(4, 6), startDate: date(4, 6), taxTreatment: .nonTaxable))
        try context.save()
        let summary = try ShiftController.summarySnapshot(in: context, at: date(4, 20), calendar: calendar)
        XCTAssertEqual(summary.combined.allTimeEffective.supplementalTotal, 70, accuracy: 0.001)
        XCTAssertFalse(summary.jobs.contains { $0.id == archived.id })
    }

    func testArchiveIncludesElapsedPartOfOpenShiftInPreviousPeriod() throws {
        let job = JobProfile(name: "Night")
        let open = OpenShiftState(job: job, startDate: date(4, 5, 20))
        let archive = PayPeriodService.archiveSnapshot(
            asOf: date(4, 6, 4), jobs: [job], completedShifts: [], openShifts: [open],
            paySchedules: [PaySchedule(job: job, frequency: .weekly, anchorDate: date(4, 6))],
            payRates: [PayRateSchedule(job: job, effectiveDate: date(1, 1), hourlyRate: 20)],
            nightRules: [], overtimeRules: [], templates: [], taxProfile: TaxProfile(), calendar: calendar
        )
        XCTAssertEqual(archive.sections.flatMap(\.summaries).reduce(0) { $0 + $1.grossEarnings }, 160, accuracy: 0.001)
    }

    func testAllocationsPreserveSavedGrossAfterRateSettingsChange() {
        let job = JobProfile(name: "Night")
        let shift = record(job: job, start: date(4, 5, 20), end: date(4, 6, 4))
        let archive = PayPeriodService.archiveSnapshot(
            asOf: date(4, 7), jobs: [job], completedShifts: [shift],
            paySchedules: [PaySchedule(job: job, frequency: .weekly, anchorDate: date(4, 6))],
            payRates: [PayRateSchedule(job: job, effectiveDate: date(1, 1), hourlyRate: 30)],
            nightRules: [], overtimeRules: [], templates: [], taxProfile: TaxProfile(), calendar: calendar
        )
        XCTAssertEqual(archive.sections.flatMap(\.summaries).reduce(0) { $0 + $1.grossEarnings }, shift.grossEarnings, accuracy: 0.001)
    }

    func testSavedSegmentsKeepOriginalPremiumTimingAfterNightRuleChanges() throws {
        let job = JobProfile(name: "Night")
        let rate = PayRateSchedule(job: job, effectiveDate: date(1, 1), hourlyRate: 20)
        let rule = NightDifferentialRule(job: job, startHour: 18, endHour: 6, percentIncrease: 0.1, isEnabled: true)
        let start = date(4, 5, 20)
        let end = date(4, 6, 4)
        let shift = ShiftRecord(job: job, startDate: start, endDate: end, breakdown: EarningsEngine.calculate(
            start: start, end: end, payRates: [rate], nightRule: rule, overtimeRule: nil, historicalShifts: [], calendar: calendar
        ))
        rule.startHour = 20
        rule.endHour = 22
        rule.percentIncrease = 0.5
        let schedule = PaySchedule(job: job, frequency: .weekly, anchorDate: date(4, 6))
        let config = JobService.configuration(for: job, payRates: [rate], nightRules: [rule], overtimeRules: [], paySchedules: [schedule], templates: [])
        let before = ShiftEarningsAllocation.completed(shift, within: DateInterval(start: date(4, 5), end: date(4, 6)), configuration: config, historicalShifts: [shift], calendar: calendar)
        let after = ShiftEarningsAllocation.completed(shift, within: DateInterval(start: date(4, 6), end: date(4, 7)), configuration: config, historicalShifts: [shift], calendar: calendar)
        XCTAssertEqual(before.grossEarnings, 88, accuracy: 0.001)
        XCTAssertEqual(after.grossEarnings, 88, accuracy: 0.001)
        XCTAssertEqual(before.nightPremiumEarnings, 8, accuracy: 0.001)
        XCTAssertEqual(after.nightPremiumEarnings, 8, accuracy: 0.001)
    }

    @MainActor
    func testSharedStoreMigrationIncludesCommittedWALAndKeepsOriginal() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "MoneyTracker-Migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appending(path: "Original.sqlite")
        let destination = directory.appending(path: "Shared.sqlite")
        let configuration = ModelConfiguration("Legacy", schema: AppModelContainerFactory.schema, url: original, cloudKitDatabase: .none)
        let container = try ModelContainer(for: AppModelContainerFactory.schema, configurations: [configuration])
        let context = container.mainContext
        context.insert(JobProfile(name: "Existing pay history"))
        try context.save()
        try AppModelContainerFactory.copyLegacyStore(from: original, to: destination)
        let sharedConfiguration = ModelConfiguration("Shared", schema: AppModelContainerFactory.schema, url: destination, cloudKitDatabase: .none)
        let shared = try ModelContainer(for: AppModelContainerFactory.schema, configurations: [sharedConfiguration])
        XCTAssertEqual(try shared.mainContext.fetch(FetchDescriptor<JobProfile>()).first?.name, "Existing pay history")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<JobProfile>()), 1)
        // Repeating startup must not overwrite a newer shared store.
        context.insert(JobProfile(name: "Only in original"))
        try context.save()
        try AppModelContainerFactory.copyLegacyStore(from: original, to: destination)
        XCTAssertEqual(try shared.mainContext.fetchCount(FetchDescriptor<JobProfile>()), 1)
    }

    @MainActor
    func testFailedReadOnlySavePreservesOpenShiftAndDoesNotLeavePhantomHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "MoneyTracker-ReadOnly-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Store.sqlite")
        let configuration = ModelConfiguration("Writable", schema: AppModelContainerFactory.schema, url: url, cloudKitDatabase: .none)
        let original = try ModelContainer(for: AppModelContainerFactory.schema, configurations: [configuration])
        try DataBootstrapper.seedIfNeeded(in: original.mainContext)
        let job = try XCTUnwrap(JobService.jobs(in: original.mainContext).first)
        original.mainContext.insert(PayRateSchedule(job: job, effectiveDate: date(1, 1), hourlyRate: 20))
        try ShiftController.startShift(in: original.mainContext, at: date(4, 6, 8))

        let readOnlyConfiguration = ModelConfiguration("ReadOnly", schema: AppModelContainerFactory.schema, url: url, allowsSave: false, cloudKitDatabase: .none)
        let readOnly = try ModelContainer(for: AppModelContainerFactory.schema, configurations: [readOnlyConfiguration])
        let context = readOnly.mainContext
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<OpenShiftState>()), 1, "Fixture must contain the saved open shift")
        XCTAssertThrowsError(try ShiftController.endAllShifts(in: context, at: date(4, 6, 16)))
        // A read-only context must be rejected before mutating its graph or
        // invoking a save that can invalidate its query cache on some OS builds.
        XCTAssertEqual(try context.fetch(FetchDescriptor<OpenShiftState>()).count, 1, "Fetch must retain the saved shift")
        let recovered = ModelContext(readOnly)
        XCTAssertEqual(try recovered.fetch(FetchDescriptor<OpenShiftState>()).count, 1, "The store must keep the saved shift")
        XCTAssertEqual(try recovered.fetch(FetchDescriptor<ShiftRecord>()).count, 0, "Failed saves must not create persisted history")
        XCTAssertEqual(try context.fetch(FetchDescriptor<ShiftRecord>()).count, 0)
        XCTAssertFalse(context.hasChanges)
    }

    @MainActor
    func testEndingBeforeStartDoesNotDestroyOpenShift() throws {
        let container = AppModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        try DataBootstrapper.seedIfNeeded(in: context)
        let job = try XCTUnwrap(JobService.jobs(in: context).first)
        context.insert(PayRateSchedule(job: job, effectiveDate: date(1, 1), hourlyRate: 20))
        let open = try ShiftController.startShift(in: context, at: date(4, 6, 8))
        XCTAssertThrowsError(try ShiftController.endShift(in: context, openShift: open, at: date(4, 6, 7)))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<OpenShiftState>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShiftRecord>()), 0)
    }

    @MainActor
    func testEmptyEndSelectionDoesNotEndEveryJob() throws {
        let container = AppModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        try DataBootstrapper.seedIfNeeded(in: context)
        let job = try XCTUnwrap(JobService.jobs(in: context).first)
        context.insert(PayRateSchedule(job: job, effectiveDate: date(1, 1), hourlyRate: 20))
        try ShiftController.startShift(in: context, at: date(4, 6, 8))
        XCTAssertThrowsError(try ShiftController.endShifts(in: context, openShiftIdentifiers: [], at: date(4, 6, 16)))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<OpenShiftState>()), 1)
    }

    @MainActor
    func testEndAllValidatesEveryJobBeforeMutating() throws {
        let container = AppModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        try DataBootstrapper.seedIfNeeded(in: context)
        let first = try XCTUnwrap(JobService.jobs(in: context).first)
        let second = try JobService.createJob(in: context, name: "Second")
        context.insert(PayRateSchedule(job: first, effectiveDate: date(1, 1), hourlyRate: 20))
        context.insert(OpenShiftState(job: first, startDate: date(4, 6, 8)))
        context.insert(OpenShiftState(job: second, startDate: date(4, 6, 9)))
        try context.save()
        XCTAssertThrowsError(try ShiftController.endAllShifts(in: context, at: date(4, 6, 16)))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<OpenShiftState>()), 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShiftRecord>()), 0)
    }

    @MainActor
    func testBackdatedInsertAndDeletionRecalculateLaterDailyOvertime() throws {
        let container = AppModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        try DataBootstrapper.seedIfNeeded(in: context)
        let job = try XCTUnwrap(JobService.jobs(in: context).first)
        context.insert(PayRateSchedule(job: job, effectiveDate: date(1, 1), hourlyRate: 20))
        let rule = try XCTUnwrap(context.fetch(FetchDescriptor<OvertimeRuleSet>()).first)
        rule.isEnabled = true
        rule.dailyThresholdHours = 8
        rule.weeklyThresholdHours = nil
        try context.save()
        try ShiftController.saveManualShift(in: context, editing: nil, job: job, startDate: date(4, 6, 13), endDate: date(4, 6, 19))
        try ShiftController.saveManualShift(in: context, editing: nil, job: job, startDate: date(4, 6, 7), endDate: date(4, 6, 11))
        let records = try context.fetch(FetchDescriptor<ShiftRecord>(sortBy: [SortDescriptor(\ShiftRecord.startDate)]))
        XCTAssertEqual(records[0].grossEarnings, 80, accuracy: 0.001)
        XCTAssertEqual(records[1].grossEarnings, 140, accuracy: 0.001)
        try ShiftController.deleteShift(records[0], in: context)
        XCTAssertEqual(records[1].grossEarnings, 120, accuracy: 0.001)
    }

    @MainActor
    func testOvertimeRecalculationKeepsSavedBasePricesAfterRateChanges() throws {
        let container = AppModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        try DataBootstrapper.seedIfNeeded(in: context)
        let job = try XCTUnwrap(JobService.jobs(in: context).first)
        let rate = PayRateSchedule(job: job, effectiveDate: date(1, 1), hourlyRate: 20)
        context.insert(rate)
        let rule = try XCTUnwrap(context.fetch(FetchDescriptor<OvertimeRuleSet>()).first)
        rule.isEnabled = true
        rule.dailyThresholdHours = 8
        rule.weeklyThresholdHours = nil
        try PersistenceService.save(context)
        try ShiftController.saveManualShift(in: context, editing: nil, job: job, startDate: date(4, 6, 13), endDate: date(4, 6, 19))
        rate.hourlyRate = 30
        try PersistenceService.save(context)
        try ShiftController.saveManualShift(in: context, editing: nil, job: job, startDate: date(4, 6, 7), endDate: date(4, 6, 11))
        let records = try context.fetch(FetchDescriptor<ShiftRecord>(sortBy: [SortDescriptor(\ShiftRecord.startDate)]))
        XCTAssertEqual(records[0].grossEarnings, 120, accuracy: 0.001)
        XCTAssertEqual(records[1].baseEarnings, 120, accuracy: 0.001)
        XCTAssertEqual(records[1].grossEarnings, 140, accuracy: 0.001)
    }

    @MainActor
    func testOpenShiftStopsAccruingAtScheduledEndInReadOnlySnapshot() throws {
        let container = AppModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        try DataBootstrapper.seedIfNeeded(in: context)
        let job = try XCTUnwrap(JobService.jobs(in: context).first)
        context.insert(PayRateSchedule(job: job, effectiveDate: date(1, 1), hourlyRate: 20))
        try ShiftController.startShift(in: context, at: date(4, 6, 8), scheduledEndDate: date(4, 6, 16))
        let snapshot = try ShiftController.dashboardSnapshot(in: context, at: date(4, 6, 20))
        XCTAssertEqual(snapshot.currentGross, 160, accuracy: 0.001)
    }
}
