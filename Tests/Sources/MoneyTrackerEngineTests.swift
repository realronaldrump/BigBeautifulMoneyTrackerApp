import XCTest
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
            nightRule: NightDifferentialRule(startHour: 19, endHour: 7, percentIncrease: 0.07, isEnabled: true),
            overtimeRule: nil,
            historicalShifts: [],
            calendar: calendar
        )

        XCTAssertEqual(result.regularHours, 1, accuracy: 0.001)
        XCTAssertEqual(result.nightHours, 1, accuracy: 0.001)
        XCTAssertEqual(result.nightPremiumEarnings, 3.5, accuracy: 0.001)
        XCTAssertEqual(result.grossEarnings, 103.5, accuracy: 0.001)
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

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
