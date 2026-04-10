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

    func testLocalizedNumericInputAcceptsAlternateDecimalSeparators() throws {
        let frenchLocaleValue = try XCTUnwrap(
            LocalizedNumericInput.decimalValue(from: "33.29", locale: Locale(identifier: "fr_FR"))
        )
        XCTAssertEqual(frenchLocaleValue, 33.29, accuracy: 0.0001)

        let usLocaleValue = try XCTUnwrap(
            LocalizedNumericInput.decimalValue(from: "33,29", locale: Locale(identifier: "en_US"))
        )
        XCTAssertEqual(usLocaleValue, 33.29, accuracy: 0.0001)
    }

    func testShiftTakeHomeEstimateUsesJobSpecificTaxConfiguration() {
        let taxProfile = TaxProfile(
            filingStatus: .single,
            usesStandardDeduction: true,
            annualPretaxInsurance: 0,
            annualRetirementContribution: 0,
            extraFederalWithholdingPerPeriod: 20,
            extraStateWithholdingPerPeriod: 5,
            expectedWeeklyHours: 36
        )
        let job = JobProfile(name: "Main Job")
        let paySchedule = PaySchedule(job: job, frequency: .weekly, anchorDate: makeDate(year: 2026, month: 1, day: 1, hour: 0))
        let payRate = PayRateSchedule(job: job, effectiveDate: makeDate(year: 2026, month: 1, day: 1, hour: 0), hourlyRate: 50)
        let historicalShift = ShiftRecord(
            job: job,
            startDate: makeDate(year: 2026, month: 2, day: 1, hour: 7),
            endDate: makeDate(year: 2026, month: 2, day: 1, hour: 15),
            breakdown: makeBreakdown(hours: 8, gross: 400)
        )
        let targetShift = ShiftRecord(
            job: job,
            startDate: makeDate(year: 2026, month: 4, day: 8, hour: 7),
            endDate: makeDate(year: 2026, month: 4, day: 8, hour: 15),
            breakdown: makeBreakdown(hours: 8, gross: 400)
        )

        let takeHome = TaxEstimator.estimatedTakeHome(
            for: targetShift,
            allShifts: [historicalShift, targetShift],
            payRates: [payRate],
            paySchedules: [paySchedule],
            templates: [],
            taxProfile: taxProfile,
            calendar: calendar
        )
        let manualEstimate = TaxEstimator.estimate(
            currentGross: 0,
            yearToDateGrossExcludingCurrentShift: historicalShift.grossEarnings,
            payFrequency: .weekly,
            taxProfile: taxProfile,
            currentHourlyRate: 50,
            templates: [],
            today: targetShift.endDate,
            calendar: calendar
        )

        XCTAssertEqual(
            takeHome,
            TaxEstimator.estimatedTakeHome(for: targetShift.grossEarnings, estimate: manualEstimate),
            accuracy: 0.01
        )
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

        let startedShift = try XCTUnwrap(result.startedShifts.first)
        XCTAssertTrue(result.autoCompletedShifts.isEmpty)
        XCTAssertEqual(startedShift.startDate, start)
        XCTAssertEqual(startedShift.scheduledEndDate, end)
        XCTAssertEqual(startedShift.note, "ICU")
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
        XCTAssertTrue(result.startedShifts.isEmpty)
        XCTAssertEqual(result.autoCompletedShifts.count, 1)
        XCTAssertEqual(loggedShift.note, "Auto logged")
        XCTAssertEqual(loggedShift.totalHours, 2, accuracy: 0.001)
        XCTAssertEqual(loggedShift.grossEarnings, 100, accuracy: 0.001)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ShiftRecord>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ScheduledShift>()).count, 0)
    }

    @MainActor
    func testDashboardSnapshotCombinesConcurrentJobs() throws {
        let container = AppModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        try DataBootstrapper.seedIfNeeded(in: context)

        let defaultJob = try XCTUnwrap(try JobService.jobs(in: context).first)
        let secondJob = try JobService.createJob(in: context, name: "Side Gig", accent: .sky, anchorDate: makeDate(year: 2026, month: 4, day: 1, hour: 0))

        context.insert(PayRateSchedule(job: defaultJob, effectiveDate: makeDate(year: 2026, month: 4, day: 1, hour: 0), hourlyRate: 50))
        context.insert(PayRateSchedule(job: secondJob, effectiveDate: makeDate(year: 2026, month: 4, day: 1, hour: 0), hourlyRate: 30))

        let paySchedules = try context.fetch(FetchDescriptor<PaySchedule>())
        let defaultSchedule = try XCTUnwrap(paySchedules.first(where: { $0.job?.id == defaultJob.id }))
        let secondSchedule = try XCTUnwrap(paySchedules.first(where: { $0.job?.id == secondJob.id }))
        defaultSchedule.frequency = .weekly
        defaultSchedule.anchorDate = makeDate(year: 2026, month: 4, day: 6, hour: 0)
        secondSchedule.frequency = .weekly
        secondSchedule.anchorDate = makeDate(year: 2026, month: 4, day: 6, hour: 0)
        try context.save()

        _ = try ShiftController.startShifts(
            in: context,
            jobIdentifiers: [defaultJob.id, secondJob.id],
            at: makeDate(year: 2026, month: 4, day: 8, hour: 9)
        )

        let snapshot = try ShiftController.dashboardSnapshot(
            in: context,
            at: makeDate(year: 2026, month: 4, day: 8, hour: 11)
        )

        XCTAssertEqual(snapshot.activeJobs.count, 2)
        XCTAssertEqual(snapshot.currentGross, 160, accuracy: 0.001)
        XCTAssertEqual(snapshot.currentBreakdown?.effectiveRate ?? 0, 40, accuracy: 0.001)
        XCTAssertEqual(snapshot.payPeriodAggregation, .unified)
    }

    @MainActor
    func testLegacyConfigurationMigratesWithoutDuplicatingDefaults() throws {
        let container = AppModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext

        let legacyAnchor = makeDate(year: 2026, month: 4, day: 4, hour: 0)
        context.insert(PaySchedule(frequency: .weekly, anchorDate: legacyAnchor))
        context.insert(NightDifferentialRule(startHour: 19, endHour: 7, percentIncrease: 0.12, isEnabled: true))
        context.insert(
            OvertimeRuleSet(
                isEnabled: true,
                dailyThresholdHours: 8,
                weeklyThresholdHours: 36,
                dailyMultiplier: 1.5,
                weeklyMultiplier: 2,
                precedence: .dailyFirst
            )
        )
        try context.save()

        try DataBootstrapper.seedIfNeeded(in: context)

        let defaultJob = try XCTUnwrap(try JobService.jobs(in: context).first)
        let paySchedules = try context.fetch(FetchDescriptor<PaySchedule>()).filter { $0.job?.id == defaultJob.id }
        let nightRules = try context.fetch(FetchDescriptor<NightDifferentialRule>()).filter { $0.job?.id == defaultJob.id }
        let overtimeRules = try context.fetch(FetchDescriptor<OvertimeRuleSet>()).filter { $0.job?.id == defaultJob.id }

        XCTAssertEqual(paySchedules.count, 1)
        XCTAssertEqual(paySchedules.first?.frequency, .weekly)
        XCTAssertEqual(paySchedules.first?.anchorDate, legacyAnchor)

        let migratedNightRule = try XCTUnwrap(nightRules.first)
        XCTAssertEqual(nightRules.count, 1)
        XCTAssertEqual(migratedNightRule.startHour, 19)
        XCTAssertEqual(migratedNightRule.endHour, 7)
        XCTAssertEqual(migratedNightRule.percentIncrease, 0.12, accuracy: 0.001)
        XCTAssertEqual(migratedNightRule.isEnabled, true)

        let migratedOvertimeRule = try XCTUnwrap(overtimeRules.first)
        XCTAssertEqual(overtimeRules.count, 1)
        XCTAssertEqual(migratedOvertimeRule.isEnabled, true)
        XCTAssertEqual(migratedOvertimeRule.weeklyThresholdHours ?? 0, 36, accuracy: 0.001)
        XCTAssertEqual(migratedOvertimeRule.weeklyMultiplier, 2, accuracy: 0.001)
        XCTAssertEqual(migratedOvertimeRule.precedence, .dailyFirst)

        XCTAssertEqual(try context.fetch(FetchDescriptor<PaySchedule>()).filter { $0.job == nil }.count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<NightDifferentialRule>()).filter { $0.job == nil }.count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<OvertimeRuleSet>()).filter { $0.job == nil }.count, 0)
    }

    @MainActor
    func testCombinedTakeHomeUsesSharedAnnualizedIncome() throws {
        let container = AppModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        try DataBootstrapper.seedIfNeeded(in: context)

        let taxProfile = try XCTUnwrap(try DataBootstrapper.first(TaxProfile.self, in: context))
        taxProfile.filingStatus = .single
        taxProfile.usesStandardDeduction = true
        taxProfile.annualPretaxInsurance = 0
        taxProfile.annualRetirementContribution = 0
        taxProfile.extraFederalWithholdingPerPeriod = 0
        taxProfile.extraStateWithholdingPerPeriod = 0
        taxProfile.expectedWeeklyHours = 40

        let defaultJob = try XCTUnwrap(try JobService.jobs(in: context).first)
        let secondJob = try JobService.createJob(in: context, name: "Side Gig", accent: .sky, anchorDate: makeDate(year: 2026, month: 4, day: 1, hour: 0))

        context.insert(PayRateSchedule(job: defaultJob, effectiveDate: makeDate(year: 2026, month: 1, day: 1, hour: 0), hourlyRate: 50))
        context.insert(PayRateSchedule(job: secondJob, effectiveDate: makeDate(year: 2026, month: 1, day: 1, hour: 0), hourlyRate: 30))

        context.insert(
            ShiftRecord(
                job: defaultJob,
                startDate: makeDate(year: 2026, month: 2, day: 1, hour: 7),
                endDate: makeDate(year: 2026, month: 2, day: 2, hour: 7),
                breakdown: makeBreakdown(hours: 24, gross: 60_000)
            )
        )
        context.insert(
            ShiftRecord(
                job: secondJob,
                startDate: makeDate(year: 2026, month: 2, day: 3, hour: 7),
                endDate: makeDate(year: 2026, month: 2, day: 4, hour: 15),
                breakdown: makeBreakdown(hours: 32, gross: 40_000)
            )
        )
        try context.save()

        _ = try ShiftController.startShifts(
            in: context,
            jobIdentifiers: [defaultJob.id, secondJob.id],
            at: makeDate(year: 2026, month: 4, day: 8, hour: 9)
        )

        let asOfDate = makeDate(year: 2026, month: 4, day: 8, hour: 11)
        let summary = try ShiftController.summarySnapshot(in: context, at: asOfDate)

        let combinedAnnualizedGrossIncome =
            TaxEstimator.annualizedGrossIncome(
                currentGross: 100,
                yearToDateGrossExcludingCurrentShift: 60_000,
                currentHourlyRate: 50,
                templates: [],
                today: asOfDate,
                calendar: calendar,
                fallbackExpectedWeeklyHours: taxProfile.expectedWeeklyHours
            )
            + TaxEstimator.annualizedGrossIncome(
                currentGross: 60,
                yearToDateGrossExcludingCurrentShift: 40_000,
                currentHourlyRate: 30,
                templates: [],
                today: asOfDate,
                calendar: calendar,
                fallbackExpectedWeeklyHours: taxProfile.expectedWeeklyHours
            )
        let combinedEstimate = TaxEstimator.estimate(
            currentGross: 160,
            annualizedGrossIncome: combinedAnnualizedGrossIncome,
            annualExtraWithholding: TaxEstimator.annualExtraWithholding(payFrequency: .biweekly, taxProfile: taxProfile),
            taxProfile: taxProfile
        )

        XCTAssertEqual(summary.combined.activeTakeHome, combinedEstimate.currentShiftNetEstimate, accuracy: 0.01)
        XCTAssertEqual(
            summary.combined.allTimeTakeHome,
            TaxEstimator.estimatedTakeHome(for: summary.combined.allTimeGross, estimate: combinedEstimate),
            accuracy: 0.01
        )
        XCTAssertNotEqual(
            summary.combined.activeTakeHome,
            summary.jobs.reduce(0) { $0 + $1.rollup.activeTakeHome },
            accuracy: 0.01
        )
    }

    @MainActor
    func testCombinedPayPeriodFlagsMismatchedSchedules() throws {
        let container = AppModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        try DataBootstrapper.seedIfNeeded(in: context)

        let defaultJob = try XCTUnwrap(try JobService.jobs(in: context).first)
        let secondJob = try JobService.createJob(in: context, name: "Side Gig", accent: .sky, anchorDate: makeDate(year: 2026, month: 4, day: 1, hour: 0))

        let paySchedules = try context.fetch(FetchDescriptor<PaySchedule>())
        let defaultSchedule = try XCTUnwrap(paySchedules.first(where: { $0.job?.id == defaultJob.id }))
        let secondSchedule = try XCTUnwrap(paySchedules.first(where: { $0.job?.id == secondJob.id }))
        defaultSchedule.frequency = .weekly
        defaultSchedule.anchorDate = makeDate(year: 2026, month: 4, day: 6, hour: 0)
        secondSchedule.frequency = .biweekly
        secondSchedule.anchorDate = makeDate(year: 2026, month: 4, day: 1, hour: 0)

        context.insert(
            ShiftRecord(
                job: defaultJob,
                startDate: makeDate(year: 2026, month: 4, day: 7, hour: 7),
                endDate: makeDate(year: 2026, month: 4, day: 7, hour: 15),
                breakdown: makeBreakdown(hours: 8, gross: 400)
            )
        )
        context.insert(
            ShiftRecord(
                job: secondJob,
                startDate: makeDate(year: 2026, month: 4, day: 7, hour: 16),
                endDate: makeDate(year: 2026, month: 4, day: 7, hour: 22),
                breakdown: makeBreakdown(hours: 6, gross: 240)
            )
        )
        try context.save()

        let asOfDate = makeDate(year: 2026, month: 4, day: 8, hour: 11)
        let summary = try ShiftController.summarySnapshot(in: context, at: asOfDate)
        let dashboard = try ShiftController.dashboardSnapshot(in: context, at: asOfDate)

        XCTAssertEqual(summary.combined.payPeriodAggregation, .variesByJob)
        XCTAssertEqual(summary.projectedConfidenceLabel, "Varies by job")
        XCTAssertEqual(dashboard.payPeriodAggregation, .variesByJob)
        XCTAssertEqual(dashboard.payPeriodGross, 0, accuracy: 0.001)
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func makeBreakdown(hours: Double, gross: Double) -> EarningsBreakdown {
        EarningsBreakdown(
            totalHours: hours,
            grossEarnings: gross,
            baseEarnings: gross,
            nightPremiumEarnings: 0,
            overtimePremiumEarnings: 0,
            regularHours: hours,
            nightHours: 0,
            overtimeHours: 0,
            effectiveRate: gross / max(hours, 0.000_001)
        )
    }
}
