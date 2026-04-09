import XCTest
import SwiftData
@testable import BigBeautifulMoneyTracker

final class MoneyTrackerEngineTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    func testSameDayGrossCalculation() {
        let start = makeDate(year: 2026, month: 4, day: 7, hour: 9)
        let end = makeDate(year: 2026, month: 4, day: 7, hour: 17)

        let result = EarningsEngine.calculate(
            start: start,
            end: end,
            payRates: [PayRateSchedule(effectiveDate: start, hourlyRate: 50)],
            nightRule: NightDifferentialRule(isEnabled: false),
            overtimeRule: nil,
            historicalShifts: [],
            calendar: calendar
        )

        XCTAssertEqual(result.totalHours, 8, accuracy: 0.0001)
        XCTAssertEqual(result.grossEarnings, 400, accuracy: 0.001)
        XCTAssertEqual(result.regularHours, 8, accuracy: 0.001)
        XCTAssertEqual(result.nightHours, 0, accuracy: 0.001)
    }

    func testNightDifferentialSplit() {
        let start = makeDate(year: 2026, month: 4, day: 7, hour: 18)
        let end = makeDate(year: 2026, month: 4, day: 7, hour: 20)

        let result = EarningsEngine.calculate(
            start: start,
            end: end,
            payRates: [PayRateSchedule(effectiveDate: start, hourlyRate: 50)],
            nightRule: NightDifferentialRule(startHour: 18, endHour: 6, percentIncrease: 0.07, isEnabled: true),
            overtimeRule: nil,
            historicalShifts: [],
            calendar: calendar
        )

        XCTAssertEqual(result.regularHours, 0, accuracy: 0.001)
        XCTAssertEqual(result.nightHours, 2, accuracy: 0.001)
        XCTAssertEqual(result.nightPremiumEarnings, 7, accuracy: 0.001)
        XCTAssertEqual(result.grossEarnings, 107, accuracy: 0.001)
    }

    func testRateChangeBoundary() {
        let start = makeDate(year: 2026, month: 4, day: 7, hour: 8)
        let rateChange = makeDate(year: 2026, month: 4, day: 7, hour: 10)
        let end = makeDate(year: 2026, month: 4, day: 7, hour: 12)

        let result = EarningsEngine.calculate(
            start: start,
            end: end,
            payRates: [
                PayRateSchedule(effectiveDate: start, hourlyRate: 50),
                PayRateSchedule(effectiveDate: rateChange, hourlyRate: 60),
            ],
            nightRule: NightDifferentialRule(isEnabled: false),
            overtimeRule: nil,
            historicalShifts: [],
            calendar: calendar
        )

        XCTAssertEqual(result.grossEarnings, 220, accuracy: 0.001)
    }

    func testDailyOvertimeThreshold() {
        let start = makeDate(year: 2026, month: 4, day: 7, hour: 8)
        let end = makeDate(year: 2026, month: 4, day: 7, hour: 18)

        let result = EarningsEngine.calculate(
            start: start,
            end: end,
            payRates: [PayRateSchedule(effectiveDate: start, hourlyRate: 50)],
            nightRule: NightDifferentialRule(isEnabled: false),
            overtimeRule: OvertimeRuleSet(isEnabled: true, dailyThresholdHours: 8, weeklyThresholdHours: nil, dailyMultiplier: 1.5, weeklyMultiplier: 1.5),
            historicalShifts: [],
            calendar: calendar
        )

        XCTAssertEqual(result.overtimeHours, 2, accuracy: 0.001)
        XCTAssertEqual(result.overtimePremiumEarnings, 50, accuracy: 0.001)
        XCTAssertEqual(result.grossEarnings, 550, accuracy: 0.001)
    }

    func testTaxEstimatorProducesWithholdingRate() {
        let taxProfile = TaxProfile(
            filingStatus: .single,
            usesStandardDeduction: true,
            annualPretaxInsurance: 1_200,
            annualRetirementContribution: 2_400,
            extraFederalWithholdingPerPeriod: 25,
            extraStateWithholdingPerPeriod: 10,
            expectedWeeklyHours: 36
        )

        let estimate = TaxEstimator.estimate(
            currentGross: 200,
            yearToDateGrossExcludingCurrentShift: 18_000,
            payFrequency: .biweekly,
            taxProfile: taxProfile,
            currentHourlyRate: 48,
            templates: []
        )

        XCTAssertGreaterThan(estimate.annualizedGrossIncome, 0)
        XCTAssertGreaterThan(estimate.estimatedWithholdingRate, 0.1)
        XCTAssertLessThan(estimate.estimatedWithholdingRate, 0.5)
        XCTAssertLessThan(estimate.currentShiftNetEstimate, 200)
    }

    func testProjectionFallsBackToEarnedSoFarWithoutTemplates() {
        let schedule = PaySchedule(frequency: .weekly, anchorDate: makeDate(year: 2026, month: 4, day: 6, hour: 0))
        let shift = ShiftRecord(
            startDate: makeDate(year: 2026, month: 4, day: 7, hour: 7),
            endDate: makeDate(year: 2026, month: 4, day: 7, hour: 19),
            breakdown: EarningsBreakdown(
                totalHours: 12,
                grossEarnings: 600,
                baseEarnings: 600,
                nightPremiumEarnings: 0,
                overtimePremiumEarnings: 0,
                regularHours: 12,
                nightHours: 0,
                overtimeHours: 0,
                effectiveRate: 50
            )
        )

        let projection = ProjectionEngine.projectedPaycheck(
            asOf: makeDate(year: 2026, month: 4, day: 8, hour: 9),
            shifts: [shift],
            openShiftBreakdown: nil,
            paySchedule: schedule,
            payRates: [PayRateSchedule(effectiveDate: shift.startDate, hourlyRate: 50)],
            templates: [],
            takeHomeRate: 0.25,
            calendar: calendar
        )

        XCTAssertEqual(projection.payPeriodGross, 600, accuracy: 0.001)
        XCTAssertEqual(projection.projectedGross, 600, accuracy: 0.001)
        XCTAssertEqual(projection.confidenceLabel, "Earned so far")
    }

    @MainActor
    func testScheduledShiftStartsOpenShiftWhenDue() throws {
        let container = AppModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        try DataBootstrapper.seedIfNeeded(in: context)

        let payRateStart = makeDate(year: 2026, month: 4, day: 1, hour: 0)
        context.insert(PayRateSchedule(effectiveDate: payRateStart, hourlyRate: 50))

        let start = makeDate(year: 2026, month: 4, day: 8, hour: 7)
        let end = makeDate(year: 2026, month: 4, day: 8, hour: 19)
        context.insert(ScheduledShift(startDate: start, endDate: end, note: "ICU"))
        try context.save()

        let result = try ShiftController.reconcileScheduledShifts(
            in: context,
            at: makeDate(year: 2026, month: 4, day: 8, hour: 9)
        )

        XCTAssertNotNil(result.startedShift)
        XCTAssertTrue(result.autoCompletedShifts.isEmpty)
        XCTAssertEqual(result.startedShift?.startDate, start)
        XCTAssertEqual(result.startedShift?.scheduledEndDate, end)
        XCTAssertEqual(result.startedShift?.note, "ICU")
        XCTAssertEqual(try context.fetch(FetchDescriptor<ScheduledShift>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<OpenShiftState>()).count, 1)
    }

    @MainActor
    func testOverdueScheduledShiftIsLoggedToHistoryWhenReconciled() throws {
        let container = AppModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        try DataBootstrapper.seedIfNeeded(in: context)

        let payRateStart = makeDate(year: 2026, month: 4, day: 1, hour: 0)
        context.insert(PayRateSchedule(effectiveDate: payRateStart, hourlyRate: 50))

        let start = makeDate(year: 2026, month: 4, day: 7, hour: 18)
        let end = makeDate(year: 2026, month: 4, day: 7, hour: 20)
        context.insert(ScheduledShift(startDate: start, endDate: end, note: "Auto logged"))
        try context.save()

        let result = try ShiftController.reconcileScheduledShifts(
            in: context,
            at: makeDate(year: 2026, month: 4, day: 7, hour: 22)
        )

        let loggedShift = try XCTUnwrap(result.autoCompletedShifts.first)
        XCTAssertNil(result.startedShift)
        XCTAssertEqual(result.autoCompletedShifts.count, 1)
        XCTAssertEqual(loggedShift.note, "Auto logged")
        XCTAssertEqual(loggedShift.totalHours, 2, accuracy: 0.001)
        XCTAssertEqual(loggedShift.grossEarnings, 100, accuracy: 0.001)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ShiftRecord>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ScheduledShift>()).count, 0)
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
