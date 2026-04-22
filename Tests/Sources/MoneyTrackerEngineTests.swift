import XCTest
import SwiftData
import CoreGraphics
import UIKit
import PDFKit
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
    func testLiveActivityPayloadUsesSingleJobTitleAndGrossValues() throws {
        let startDate = makeDate(year: 2026, month: 4, day: 8, hour: 9)
        let syncDate = makeDate(year: 2026, month: 4, day: 8, hour: 10)
        let activeJob = makeActiveJob(
            name: "Hospital",
            startDate: startDate,
            gross: 50,
            takeHome: 37.50,
            rate: 50
        )
        let snapshot = makeDashboardSnapshot(
            activeJobs: [activeJob],
            currentGross: 50,
            currentTakeHome: 37.50,
            effectiveRate: 50
        )

        let action = LiveActivityManager.makeSyncAction(
            for: snapshot,
            mode: .gross,
            compensationMode: .actual,
            now: syncDate
        )
        guard case .update(let payload) = action else {
            XCTFail("Expected an update payload for an active shift.")
            return
        }

        XCTAssertEqual(payload.title, "Hospital")
        XCTAssertEqual(payload.contentState.mode, .gross)
        XCTAssertEqual(payload.contentState.compensationMode, .actual)
        XCTAssertEqual(payload.contentState.syncedAmount, 50, accuracy: 0.001)
        XCTAssertEqual(payload.contentState.currentRate, 50, accuracy: 0.001)
        XCTAssertEqual(payload.contentState.startDate, startDate)
        XCTAssertEqual(payload.contentState.lastSyncedDate, syncDate)
        XCTAssertEqual(payload.staleDate, syncDate.addingTimeInterval(LiveActivityManager.staleInterval))
    }

    @MainActor
    func testLiveActivityPayloadUsesMultipleJobTitle() throws {
        let firstStartDate = makeDate(year: 2026, month: 4, day: 8, hour: 9)
        let secondStartDate = makeDate(year: 2026, month: 4, day: 8, hour: 9, minute: 30)
        let syncDate = makeDate(year: 2026, month: 4, day: 8, hour: 10)
        let snapshot = makeDashboardSnapshot(
            activeJobs: [
                makeActiveJob(name: "Hospital", startDate: firstStartDate, gross: 50, takeHome: 37.50, rate: 50),
                makeActiveJob(name: "Clinic", startDate: secondStartDate, gross: 30, takeHome: 22.50, rate: 30)
            ],
            currentGross: 80,
            currentTakeHome: 60,
            effectiveRate: 40
        )

        let action = LiveActivityManager.makeSyncAction(
            for: snapshot,
            mode: .gross,
            compensationMode: .actual,
            now: syncDate
        )
        guard case .update(let payload) = action else {
            XCTFail("Expected an update payload for active shifts.")
            return
        }

        XCTAssertEqual(payload.title, "2 Jobs Active")
        XCTAssertEqual(payload.contentState.syncedAmount, 80, accuracy: 0.001)
        XCTAssertEqual(payload.contentState.currentRate, 40, accuracy: 0.001)
        XCTAssertEqual(payload.contentState.startDate, firstStartDate)
    }

    @MainActor
    func testLiveActivityPayloadUsesNetAmountAndRateInTakeHomeMode() throws {
        let startDate = makeDate(year: 2026, month: 4, day: 8, hour: 9)
        let syncDate = makeDate(year: 2026, month: 4, day: 8, hour: 10)
        let snapshot = makeDashboardSnapshot(
            activeJobs: [
                makeActiveJob(name: "Hospital", startDate: startDate, gross: 200, takeHome: 150, rate: 50)
            ],
            currentGross: 200,
            currentTakeHome: 150,
            effectiveRate: 50
        )

        let action = LiveActivityManager.makeSyncAction(
            for: snapshot,
            mode: .takeHome,
            compensationMode: .actual,
            now: syncDate
        )
        guard case .update(let payload) = action else {
            XCTFail("Expected an update payload for an active shift.")
            return
        }

        XCTAssertEqual(payload.contentState.mode, .takeHome)
        XCTAssertEqual(payload.contentState.compensationMode, .actual)
        XCTAssertEqual(payload.contentState.syncedAmount, 150, accuracy: 0.001)
        XCTAssertEqual(payload.contentState.currentRate, 37.50, accuracy: 0.001)
    }

    @MainActor
    func testLiveActivityPayloadUsesEffectiveAmountAndRateWhenSelected() throws {
        let startDate = makeDate(year: 2026, month: 4, day: 8, hour: 9)
        let syncDate = makeDate(year: 2026, month: 4, day: 8, hour: 10)
        let snapshot = makeDashboardSnapshot(
            activeJobs: [
                makeActiveJob(
                    name: "Hospital",
                    startDate: startDate,
                    gross: 200,
                    takeHome: 150,
                    effectiveGross: 240,
                    effectiveTakeHome: 176,
                    rate: 50
                )
            ],
            currentGross: 200,
            currentTakeHome: 150,
            currentEffectiveGross: 240,
            currentEffectiveTakeHome: 176,
            effectiveRate: 50
        )

        let action = LiveActivityManager.makeSyncAction(
            for: snapshot,
            mode: .takeHome,
            compensationMode: .effective,
            now: syncDate
        )
        guard case .update(let payload) = action else {
            XCTFail("Expected an update payload for an active shift.")
            return
        }

        XCTAssertEqual(payload.contentState.mode, .takeHome)
        XCTAssertEqual(payload.contentState.compensationMode, .effective)
        XCTAssertEqual(payload.contentState.syncedAmount, 176, accuracy: 0.001)
        XCTAssertEqual(payload.contentState.currentRate, 44, accuracy: 0.001)
    }

    @MainActor
    func testLiveActivityPayloadFallsBackToGrossRateWhenNetRatioIsUnavailable() throws {
        let startDate = makeDate(year: 2026, month: 4, day: 8, hour: 9)
        let syncDate = makeDate(year: 2026, month: 4, day: 8, hour: 10)
        let snapshot = makeDashboardSnapshot(
            activeJobs: [
                makeActiveJob(name: "Hospital", startDate: startDate, gross: 0, takeHome: 0, rate: 50)
            ],
            currentGross: 0,
            currentTakeHome: 0,
            effectiveRate: 50
        )

        let action = LiveActivityManager.makeSyncAction(
            for: snapshot,
            mode: .takeHome,
            compensationMode: .actual,
            now: syncDate
        )
        guard case .update(let payload) = action else {
            XCTFail("Expected an update payload for an active shift.")
            return
        }

        XCTAssertEqual(payload.contentState.syncedAmount, 0, accuracy: 0.001)
        XCTAssertEqual(payload.contentState.currentRate, 50, accuracy: 0.001)
    }

    @MainActor
    func testLiveActivityPayloadEndsWhenNoJobsAreActive() throws {
        let syncDate = makeDate(year: 2026, month: 4, day: 8, hour: 10)
        let snapshot = makeDashboardSnapshot(
            activeJobs: [],
            currentGross: 80,
            currentTakeHome: 60,
            effectiveRate: 0
        )

        let action = LiveActivityManager.makeSyncAction(
            for: snapshot,
            mode: .takeHome,
            compensationMode: .actual,
            now: syncDate
        )
        guard case .end(let contentState) = action else {
            XCTFail("Expected an end payload when no jobs are active.")
            return
        }

        XCTAssertEqual(contentState.mode, .takeHome)
        XCTAssertEqual(contentState.syncedAmount, 60, accuracy: 0.001)
        XCTAssertEqual(contentState.currentRate, 0, accuracy: 0.001)
        XCTAssertEqual(contentState.startDate, syncDate)
        XCTAssertEqual(contentState.lastSyncedDate, syncDate)
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
    func testArchiveJobKeepsHistoryAndRemovesFutureAutomation() throws {
        let container = AppModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        try DataBootstrapper.seedIfNeeded(in: context)

        let defaultJob = try XCTUnwrap(try JobService.jobs(in: context).first)
        let oldJob = try JobService.createJob(
            in: context,
            name: "Old Job",
            accent: .coral,
            anchorDate: makeDate(year: 2026, month: 4, day: 1, hour: 0)
        )
        let preferences = try XCTUnwrap(try DataBootstrapper.first(AppPreferences.self, in: context))
        preferences.selectedHomeJobIdentifier = oldJob.id

        context.insert(
            ShiftRecord(
                job: oldJob,
                startDate: makeDate(year: 2026, month: 4, day: 3, hour: 9),
                endDate: makeDate(year: 2026, month: 4, day: 3, hour: 17),
                breakdown: makeBreakdown(hours: 8, gross: 240)
            )
        )
        context.insert(
            ScheduleTemplate(
                job: oldJob,
                name: "Old Standard",
                weekday: .monday,
                startHour: 9,
                endHour: 17
            )
        )
        context.insert(
            ScheduledShift(
                job: oldJob,
                startDate: makeDate(year: 2026, month: 4, day: 10, hour: 9),
                endDate: makeDate(year: 2026, month: 4, day: 10, hour: 17)
            )
        )
        try context.save()

        try JobService.archiveJob(oldJob, in: context)

        XCTAssertFalse(try JobService.jobs(in: context).contains { $0.id == oldJob.id })
        XCTAssertTrue(try XCTUnwrap(try JobService.jobs(in: context, includeArchived: true).first { $0.id == oldJob.id }).isArchived)
        XCTAssertEqual(preferences.selectedHomeJobIdentifier, defaultJob.id)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ShiftRecord>()).filter { $0.job?.id == oldJob.id }.count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ScheduleTemplate>()).filter { $0.job?.id == oldJob.id }.count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ScheduledShift>()).filter { $0.job?.id == oldJob.id }.count, 0)
    }

    @MainActor
    func testArchiveJobRefusesOnlyActiveJob() throws {
        let container = AppModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        try DataBootstrapper.seedIfNeeded(in: context)

        let defaultJob = try XCTUnwrap(try JobService.jobs(in: context).first)

        XCTAssertThrowsError(try JobService.archiveJob(defaultJob, in: context)) { error in
            XCTAssertEqual(error.localizedDescription, "Add another job before deleting this one.")
        }
        XCTAssertFalse(defaultJob.isArchived)
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

    func testPayPeriodIntervalArchiveSupportsAllFrequencies() {
        let asOfDate = makeDate(year: 2026, month: 4, day: 20, hour: 12)
        let rangeStart = makeDate(year: 2026, month: 4, day: 1, hour: 0)

        let weekly = PayPeriodService.payPeriodIntervals(
            asOf: asOfDate,
            schedule: PaySchedule(frequency: .weekly, anchorDate: makeDate(year: 2026, month: 4, day: 6, hour: 0)),
            rangeStart: rangeStart,
            calendar: calendar
        )
        XCTAssertEqual(weekly.first?.start, makeDate(year: 2026, month: 4, day: 20, hour: 0))
        XCTAssertTrue(weekly.contains { $0.start == makeDate(year: 2026, month: 4, day: 6, hour: 0) })

        let biweekly = PayPeriodService.payPeriodIntervals(
            asOf: asOfDate,
            schedule: PaySchedule(frequency: .biweekly, anchorDate: makeDate(year: 2026, month: 4, day: 6, hour: 0)),
            rangeStart: rangeStart,
            calendar: calendar
        )
        XCTAssertEqual(biweekly.first?.start, makeDate(year: 2026, month: 4, day: 20, hour: 0))
        XCTAssertTrue(biweekly.contains { $0.start == makeDate(year: 2026, month: 4, day: 6, hour: 0) })

        let semiMonthly = PayPeriodService.payPeriodIntervals(
            asOf: asOfDate,
            schedule: PaySchedule(frequency: .semiMonthly, anchorDate: makeDate(year: 2026, month: 4, day: 1, hour: 0)),
            rangeStart: rangeStart,
            calendar: calendar
        )
        XCTAssertEqual(semiMonthly.first?.start, makeDate(year: 2026, month: 4, day: 16, hour: 0))
        XCTAssertTrue(semiMonthly.contains { $0.start == makeDate(year: 2026, month: 4, day: 1, hour: 0) })

        let monthly = PayPeriodService.payPeriodIntervals(
            asOf: asOfDate,
            schedule: PaySchedule(frequency: .monthly, anchorDate: makeDate(year: 2026, month: 4, day: 5, hour: 0)),
            rangeStart: rangeStart,
            calendar: calendar
        )
        XCTAssertEqual(monthly.first?.start, makeDate(year: 2026, month: 4, day: 5, hour: 0))
    }

    func testPayPeriodArchiveDefaultsToLastTwelveMonthsAndIncludesCurrentPeriod() {
        let job = JobProfile(name: "Main Job")
        let schedule = PaySchedule(job: job, frequency: .weekly, anchorDate: makeDate(year: 2026, month: 4, day: 6, hour: 0))
        let payRate = PayRateSchedule(job: job, effectiveDate: makeDate(year: 2025, month: 1, day: 1, hour: 0), hourlyRate: 50)
        let oldShift = ShiftRecord(
            job: job,
            startDate: makeDate(year: 2025, month: 4, day: 10, hour: 8),
            endDate: makeDate(year: 2025, month: 4, day: 10, hour: 16),
            breakdown: makeBreakdown(hours: 8, gross: 400)
        )
        let recentShift = ShiftRecord(
            job: job,
            startDate: makeDate(year: 2025, month: 4, day: 21, hour: 8),
            endDate: makeDate(year: 2025, month: 4, day: 21, hour: 16),
            breakdown: makeBreakdown(hours: 8, gross: 400)
        )

        let snapshot = PayPeriodService.archiveSnapshot(
            asOf: makeDate(year: 2026, month: 4, day: 20, hour: 12),
            jobs: [job],
            completedShifts: [oldShift, recentShift],
            paySchedules: [schedule],
            payRates: [payRate],
            nightRules: [],
            overtimeRules: [],
            templates: [],
            taxProfile: TaxProfile(),
            calendar: calendar
        )

        let summaries = snapshot.sections.first?.summaries ?? []
        XCTAssertEqual(summaries.first?.status, .current)
        XCTAssertTrue(summaries.contains { $0.shifts.contains { $0.shiftIdentifier == recentShift.id } })
        XCTAssertFalse(summaries.contains { $0.shifts.contains { $0.shiftIdentifier == oldShift.id } })
    }

    func testPayPeriodArchiveOnlyAddsCombinedWhenSchedulesAlign() {
        let firstJob = JobProfile(name: "Hospital", accent: .emerald, sortOrder: 0)
        let secondJob = JobProfile(name: "Clinic", accent: .sky, sortOrder: 1)
        let firstRate = PayRateSchedule(job: firstJob, effectiveDate: makeDate(year: 2026, month: 1, day: 1, hour: 0), hourlyRate: 50)
        let secondRate = PayRateSchedule(job: secondJob, effectiveDate: makeDate(year: 2026, month: 1, day: 1, hour: 0), hourlyRate: 30)
        let firstShift = ShiftRecord(
            job: firstJob,
            startDate: makeDate(year: 2026, month: 4, day: 7, hour: 8),
            endDate: makeDate(year: 2026, month: 4, day: 7, hour: 16),
            breakdown: makeBreakdown(hours: 8, gross: 400)
        )
        let secondShift = ShiftRecord(
            job: secondJob,
            startDate: makeDate(year: 2026, month: 4, day: 8, hour: 8),
            endDate: makeDate(year: 2026, month: 4, day: 8, hour: 14),
            breakdown: makeBreakdown(hours: 6, gross: 180)
        )
        let asOfDate = makeDate(year: 2026, month: 4, day: 9, hour: 12)

        let alignedSnapshot = PayPeriodService.archiveSnapshot(
            asOf: asOfDate,
            jobs: [firstJob, secondJob],
            completedShifts: [firstShift, secondShift],
            paySchedules: [
                PaySchedule(job: firstJob, frequency: .weekly, anchorDate: makeDate(year: 2026, month: 4, day: 6, hour: 0)),
                PaySchedule(job: secondJob, frequency: .weekly, anchorDate: makeDate(year: 2026, month: 4, day: 6, hour: 0))
            ],
            payRates: [firstRate, secondRate],
            nightRules: [],
            overtimeRules: [],
            templates: [],
            taxProfile: TaxProfile(),
            calendar: calendar
        )
        XCTAssertTrue(alignedSnapshot.sections.contains { $0.isCombined })

        let mismatchedSnapshot = PayPeriodService.archiveSnapshot(
            asOf: asOfDate,
            jobs: [firstJob, secondJob],
            completedShifts: [firstShift, secondShift],
            paySchedules: [
                PaySchedule(job: firstJob, frequency: .weekly, anchorDate: makeDate(year: 2026, month: 4, day: 6, hour: 0)),
                PaySchedule(job: secondJob, frequency: .biweekly, anchorDate: makeDate(year: 2026, month: 4, day: 1, hour: 0))
            ],
            payRates: [firstRate, secondRate],
            nightRules: [],
            overtimeRules: [],
            templates: [],
            taxProfile: TaxProfile(),
            calendar: calendar
        )
        XCTAssertFalse(mismatchedSnapshot.sections.contains { $0.isCombined })
    }

    func testPayPeriodBoundaryShiftIsAllocatedWithoutDoubleCounting() throws {
        let job = JobProfile(name: "Main Job")
        let schedule = PaySchedule(job: job, frequency: .weekly, anchorDate: makeDate(year: 2026, month: 4, day: 6, hour: 0))
        let payRate = PayRateSchedule(job: job, effectiveDate: makeDate(year: 2026, month: 1, day: 1, hour: 0), hourlyRate: 50)
        let boundaryShift = ShiftRecord(
            job: job,
            startDate: makeDate(year: 2026, month: 4, day: 12, hour: 18),
            endDate: makeDate(year: 2026, month: 4, day: 13, hour: 6),
            breakdown: makeBreakdown(hours: 12, gross: 600)
        )

        let snapshot = PayPeriodService.archiveSnapshot(
            asOf: makeDate(year: 2026, month: 4, day: 14, hour: 12),
            jobs: [job],
            completedShifts: [boundaryShift],
            paySchedules: [schedule],
            payRates: [payRate],
            nightRules: [],
            overtimeRules: [],
            templates: [],
            taxProfile: TaxProfile(),
            calendar: calendar
        )

        let summaries = try XCTUnwrap(snapshot.sections.first?.summaries)
        let current = try XCTUnwrap(summaries.first { $0.interval.start == makeDate(year: 2026, month: 4, day: 13, hour: 0) })
        let previous = try XCTUnwrap(summaries.first { $0.interval.start == makeDate(year: 2026, month: 4, day: 6, hour: 0) })

        XCTAssertEqual(current.totalHours, 6, accuracy: 0.001)
        XCTAssertEqual(previous.totalHours, 6, accuracy: 0.001)
        XCTAssertEqual(current.grossEarnings + previous.grossEarnings, 600, accuracy: 0.001)
    }

    func testPayPeriodBoundaryShiftUsesActualEarningSegments() throws {
        let job = JobProfile(name: "Main Job")
        let schedule = PaySchedule(job: job, frequency: .weekly, anchorDate: makeDate(year: 2026, month: 4, day: 6, hour: 0))
        let firstRate = PayRateSchedule(job: job, effectiveDate: makeDate(year: 2026, month: 4, day: 12, hour: 0), hourlyRate: 50)
        let secondRate = PayRateSchedule(job: job, effectiveDate: makeDate(year: 2026, month: 4, day: 13, hour: 0), hourlyRate: 100)
        let start = makeDate(year: 2026, month: 4, day: 12, hour: 22)
        let end = makeDate(year: 2026, month: 4, day: 13, hour: 2)
        let breakdown = EarningsEngine.calculate(
            start: start,
            end: end,
            payRates: [firstRate, secondRate],
            nightRule: NightDifferentialRule(job: job, isEnabled: false),
            overtimeRule: nil,
            historicalShifts: [],
            calendar: calendar
        )
        let boundaryShift = ShiftRecord(
            job: job,
            startDate: start,
            endDate: end,
            breakdown: breakdown
        )

        let snapshot = PayPeriodService.archiveSnapshot(
            asOf: makeDate(year: 2026, month: 4, day: 14, hour: 12),
            jobs: [job],
            completedShifts: [boundaryShift],
            paySchedules: [schedule],
            payRates: [firstRate, secondRate],
            nightRules: [],
            overtimeRules: [],
            templates: [],
            taxProfile: TaxProfile(),
            calendar: calendar
        )

        let summaries = try XCTUnwrap(snapshot.sections.first?.summaries)
        let current = try XCTUnwrap(summaries.first { $0.interval.start == makeDate(year: 2026, month: 4, day: 13, hour: 0) })
        let previous = try XCTUnwrap(summaries.first { $0.interval.start == makeDate(year: 2026, month: 4, day: 6, hour: 0) })

        XCTAssertEqual(previous.totalHours, 2, accuracy: 0.001)
        XCTAssertEqual(previous.grossEarnings, 100, accuracy: 0.001)
        XCTAssertEqual(current.totalHours, 2, accuracy: 0.001)
        XCTAssertEqual(current.grossEarnings, 200, accuracy: 0.001)
        XCTAssertEqual(current.grossEarnings + previous.grossEarnings, breakdown.grossEarnings, accuracy: 0.001)
    }

    func testPayPeriodSummaryTotalsPremiumsAndRates() throws {
        let job = JobProfile(name: "Main Job")
        let schedule = PaySchedule(job: job, frequency: .weekly, anchorDate: makeDate(year: 2026, month: 4, day: 6, hour: 0))
        let payRate = PayRateSchedule(job: job, effectiveDate: makeDate(year: 2026, month: 1, day: 1, hour: 0), hourlyRate: 50)
        let shift = ShiftRecord(
            job: job,
            startDate: makeDate(year: 2026, month: 4, day: 7, hour: 8),
            endDate: makeDate(year: 2026, month: 4, day: 7, hour: 16),
            breakdown: EarningsBreakdown(
                totalHours: 8,
                grossEarnings: 500,
                baseEarnings: 400,
                nightPremiumEarnings: 30,
                overtimePremiumEarnings: 70,
                regularHours: 5,
                nightHours: 2,
                overtimeHours: 1,
                effectiveRate: 62.5
            )
        )

        let snapshot = PayPeriodService.archiveSnapshot(
            asOf: makeDate(year: 2026, month: 4, day: 8, hour: 12),
            jobs: [job],
            completedShifts: [shift],
            paySchedules: [schedule],
            payRates: [payRate],
            nightRules: [],
            overtimeRules: [],
            templates: [],
            taxProfile: TaxProfile(),
            calendar: calendar
        )

        let summary = try XCTUnwrap(
            snapshot.sections.first?.summaries.first {
                $0.interval.start == makeDate(year: 2026, month: 4, day: 6, hour: 0)
            }
        )
        XCTAssertEqual(summary.shiftCount, 1)
        XCTAssertEqual(summary.grossEarnings, 500, accuracy: 0.001)
        XCTAssertEqual(summary.totalHours, 8, accuracy: 0.001)
        XCTAssertEqual(summary.baseEarnings, 400, accuracy: 0.001)
        XCTAssertEqual(summary.nightPremiumEarnings, 30, accuracy: 0.001)
        XCTAssertEqual(summary.overtimePremiumEarnings, 70, accuracy: 0.001)
        XCTAssertEqual(summary.effectiveHourlyRate, 62.5, accuracy: 0.001)
        XCTAssertLessThan(summary.estimatedTakeHome, summary.grossEarnings)
    }

    func testSupplementAllocationSupportsAllFrequencies() {
        let job = JobProfile(name: "Main Job")

        let weekly = JobSupplement(
            job: job,
            label: "Weekly stipend",
            kind: .housingStipend,
            amountPerInterval: 100,
            frequency: .weekly,
            anchorDate: makeDate(year: 2026, month: 4, day: 6, hour: 0),
            startDate: makeDate(year: 2026, month: 4, day: 6, hour: 0)
        )
        let biweekly = JobSupplement(
            job: job,
            label: "Biweekly stipend",
            kind: .housingStipend,
            amountPerInterval: 200,
            frequency: .biweekly,
            anchorDate: makeDate(year: 2026, month: 4, day: 6, hour: 0),
            startDate: makeDate(year: 2026, month: 4, day: 6, hour: 0)
        )
        let semiMonthly = JobSupplement(
            job: job,
            label: "Semi-monthly reimbursement",
            kind: .reimbursement,
            amountPerInterval: 300,
            frequency: .semiMonthly,
            anchorDate: makeDate(year: 2026, month: 4, day: 1, hour: 0),
            startDate: makeDate(year: 2026, month: 4, day: 1, hour: 0),
            taxTreatment: .nonTaxable
        )
        let monthly = JobSupplement(
            job: job,
            label: "Monthly stipend",
            kind: .housingStipend,
            amountPerInterval: 400,
            frequency: .monthly,
            anchorDate: makeDate(year: 2026, month: 4, day: 5, hour: 0),
            startDate: makeDate(year: 2026, month: 4, day: 5, hour: 0)
        )

        let weeklyAmount = SupplementAllocationService.allocations(
            for: [weekly],
            within: DateInterval(start: makeDate(year: 2026, month: 4, day: 6, hour: 0), end: makeDate(year: 2026, month: 4, day: 13, hour: 0)),
            calendar: calendar
        ).first?.amount
        let biweeklyAmount = SupplementAllocationService.allocations(
            for: [biweekly],
            within: DateInterval(start: makeDate(year: 2026, month: 4, day: 6, hour: 0), end: makeDate(year: 2026, month: 4, day: 20, hour: 0)),
            calendar: calendar
        ).first?.amount
        let semiMonthlyAmount = SupplementAllocationService.allocations(
            for: [semiMonthly],
            within: DateInterval(start: makeDate(year: 2026, month: 4, day: 1, hour: 0), end: makeDate(year: 2026, month: 4, day: 16, hour: 0)),
            calendar: calendar
        ).first?.amount
        let monthlyAmount = SupplementAllocationService.allocations(
            for: [monthly],
            within: DateInterval(start: makeDate(year: 2026, month: 4, day: 5, hour: 0), end: makeDate(year: 2026, month: 5, day: 5, hour: 0)),
            calendar: calendar
        ).first?.amount

        XCTAssertEqual(weeklyAmount ?? 0, 100, accuracy: 0.001)
        XCTAssertEqual(biweeklyAmount ?? 0, 200, accuracy: 0.001)
        XCTAssertEqual(semiMonthlyAmount ?? 0, 300, accuracy: 0.001)
        XCTAssertEqual(monthlyAmount ?? 0, 400, accuracy: 0.001)
    }

    func testSupplementAllocationProratesCurrentWindowAgainstClosedWindow() {
        let job = JobProfile(name: "Main Job")
        let supplement = JobSupplement(
            job: job,
            label: "Monthly stipend",
            kind: .housingStipend,
            amountPerInterval: 300,
            frequency: .monthly,
            anchorDate: makeDate(year: 2026, month: 4, day: 1, hour: 0),
            startDate: makeDate(year: 2026, month: 4, day: 1, hour: 0)
        )

        let partialAmount = SupplementAllocationService.allocations(
            for: [supplement],
            within: DateInterval(start: makeDate(year: 2026, month: 4, day: 1, hour: 0), end: makeDate(year: 2026, month: 4, day: 11, hour: 0)),
            calendar: calendar
        ).first?.amount ?? 0
        let closedAmount = SupplementAllocationService.allocations(
            for: [supplement],
            within: DateInterval(start: makeDate(year: 2026, month: 4, day: 1, hour: 0), end: makeDate(year: 2026, month: 5, day: 1, hour: 0)),
            calendar: calendar
        ).first?.amount ?? 0

        XCTAssertEqual(partialAmount, 100, accuracy: 0.001)
        XCTAssertEqual(closedAmount, 300, accuracy: 0.001)
        XCTAssertLessThan(partialAmount, closedAmount)
    }

    func testPayPeriodSummaryIncludesTaxableAndNonTaxableSupplementsInEffectiveTakeHome() throws {
        let job = JobProfile(name: "Main Job")
        let schedule = PaySchedule(job: job, frequency: .weekly, anchorDate: makeDate(year: 2026, month: 4, day: 6, hour: 0))
        let payRate = PayRateSchedule(job: job, effectiveDate: makeDate(year: 2026, month: 1, day: 1, hour: 0), hourlyRate: 50)
        let shift = ShiftRecord(
            job: job,
            startDate: makeDate(year: 2026, month: 4, day: 7, hour: 8),
            endDate: makeDate(year: 2026, month: 4, day: 7, hour: 16),
            breakdown: makeBreakdown(hours: 8, gross: 400)
        )
        let taxableSupplement = JobSupplement(
            job: job,
            label: "Housing stipend",
            kind: .housingStipend,
            amountPerInterval: 100,
            frequency: .weekly,
            anchorDate: makeDate(year: 2026, month: 4, day: 6, hour: 0),
            startDate: makeDate(year: 2026, month: 4, day: 6, hour: 0),
            taxTreatment: .taxable
        )
        let reimbursement = JobSupplement(
            job: job,
            label: "Mileage reimbursement",
            kind: .reimbursement,
            amountPerInterval: 50,
            frequency: .weekly,
            anchorDate: makeDate(year: 2026, month: 4, day: 6, hour: 0),
            startDate: makeDate(year: 2026, month: 4, day: 6, hour: 0),
            taxTreatment: .nonTaxable
        )
        let extraTaxable = JobSupplement(
            job: job,
            label: "Other stipend",
            kind: .other,
            amountPerInterval: 25,
            frequency: .weekly,
            anchorDate: makeDate(year: 2026, month: 4, day: 6, hour: 0),
            startDate: makeDate(year: 2026, month: 4, day: 6, hour: 0),
            taxTreatment: .taxable
        )

        let snapshot = PayPeriodService.archiveSnapshot(
            asOf: makeDate(year: 2026, month: 4, day: 14, hour: 12),
            jobs: [job],
            completedShifts: [shift],
            paySchedules: [schedule],
            payRates: [payRate],
            nightRules: [],
            overtimeRules: [],
            supplements: [taxableSupplement, reimbursement, extraTaxable],
            templates: [],
            taxProfile: TaxProfile(),
            calendar: calendar
        )

        let summary = try XCTUnwrap(
            snapshot.sections.first?.summaries.first {
                $0.interval.start == makeDate(year: 2026, month: 4, day: 6, hour: 0)
            }
        )
        let effectiveEstimate = TaxEstimator.estimate(
            currentGross: 0,
            annualizedGrossIncome: summary.annualizedGrossIncome,
            annualizedTaxableSupplementalIncome: summary.annualizedTaxableSupplementIncome,
            annualExtraWithholding: TaxEstimator.annualExtraWithholding(
                payFrequency: .weekly,
                taxProfile: TaxProfile()
            ),
            taxProfile: TaxProfile()
        )

        XCTAssertEqual(summary.supplementAllocations.count, 3)
        XCTAssertEqual(summary.supplementalTaxableTotal, 125, accuracy: 0.001)
        XCTAssertEqual(summary.supplementalNonTaxableTotal, 50, accuracy: 0.001)
        XCTAssertEqual(summary.supplementalTotal, 175, accuracy: 0.001)
        XCTAssertEqual(summary.effectiveGross, 575, accuracy: 0.001)
        XCTAssertEqual(
            summary.effectiveTakeHome,
            TaxEstimator.effectiveTakeHome(
                for: 400,
                taxableSupplemental: 125,
                nonTaxableSupplemental: 50,
                estimate: effectiveEstimate
            ),
            accuracy: 0.01
        )
    }

    func testSupplementOnlySummaryPromotesEffectiveHeadlinePresentation() throws {
        let job = JobProfile(name: "Main Job")
        let schedule = PaySchedule(job: job, frequency: .weekly, anchorDate: makeDate(year: 2026, month: 4, day: 6, hour: 0))
        let payRate = PayRateSchedule(job: job, effectiveDate: makeDate(year: 2026, month: 1, day: 1, hour: 0), hourlyRate: 50)
        let supplement = JobSupplement(
            job: job,
            label: "Housing stipend",
            kind: .housingStipend,
            amountPerInterval: 120,
            frequency: .weekly,
            anchorDate: makeDate(year: 2026, month: 4, day: 6, hour: 0),
            startDate: makeDate(year: 2026, month: 4, day: 6, hour: 0),
            taxTreatment: .taxable
        )

        let snapshot = PayPeriodService.archiveSnapshot(
            asOf: makeDate(year: 2026, month: 4, day: 14, hour: 12),
            jobs: [job],
            completedShifts: [],
            paySchedules: [schedule],
            payRates: [payRate],
            nightRules: [],
            overtimeRules: [],
            supplements: [supplement],
            templates: [],
            taxProfile: TaxProfile(),
            calendar: calendar
        )

        let summary = try XCTUnwrap(
            snapshot.sections.first?.summaries.first {
                $0.interval.start == makeDate(year: 2026, month: 4, day: 6, hour: 0)
            }
        )

        XCTAssertTrue(summary.isSupplementOnly)
        XCTAssertEqual(summary.displayAmount(for: .gross), summary.effectiveGross, accuracy: 0.001)
        XCTAssertEqual(summary.displayAmount(for: .takeHome), summary.effectiveTakeHome, accuracy: 0.001)
        XCTAssertNil(summary.displayHourlyRate)
        XCTAssertEqual(summary.displaySummaryContext, "1 supplement • no shifts")
        XCTAssertEqual(summary.displayMetricTitle(for: .gross), "Effective Gross")
        XCTAssertEqual(summary.displayMetricTitle(for: .takeHome), "Effective Take-Home")
    }

    @MainActor
    func testCombinedSummarySuppressesPayPeriodEffectiveWhenSchedulesDifferButKeepsAllTimeEffective() throws {
        let container = AppModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        try DataBootstrapper.seedIfNeeded(in: context)

        let primaryJob = try XCTUnwrap(try JobService.jobs(in: context).first)
        let secondaryJob = try JobService.createJob(in: context, name: "Side Gig", accent: .sky, anchorDate: makeDate(year: 2026, month: 4, day: 1, hour: 0))

        let paySchedules = try context.fetch(FetchDescriptor<PaySchedule>())
        let primarySchedule = try XCTUnwrap(paySchedules.first(where: { $0.job?.id == primaryJob.id }))
        let secondarySchedule = try XCTUnwrap(paySchedules.first(where: { $0.job?.id == secondaryJob.id }))
        primarySchedule.frequency = .weekly
        primarySchedule.anchorDate = makeDate(year: 2026, month: 4, day: 6, hour: 0)
        secondarySchedule.frequency = .biweekly
        secondarySchedule.anchorDate = makeDate(year: 2026, month: 4, day: 1, hour: 0)

        context.insert(PayRateSchedule(job: primaryJob, effectiveDate: makeDate(year: 2026, month: 1, day: 1, hour: 0), hourlyRate: 50))
        context.insert(PayRateSchedule(job: secondaryJob, effectiveDate: makeDate(year: 2026, month: 1, day: 1, hour: 0), hourlyRate: 30))
        context.insert(
            ShiftRecord(
                job: primaryJob,
                startDate: makeDate(year: 2026, month: 4, day: 7, hour: 7),
                endDate: makeDate(year: 2026, month: 4, day: 7, hour: 15),
                breakdown: makeBreakdown(hours: 8, gross: 400)
            )
        )
        context.insert(
            ShiftRecord(
                job: secondaryJob,
                startDate: makeDate(year: 2026, month: 4, day: 7, hour: 16),
                endDate: makeDate(year: 2026, month: 4, day: 7, hour: 22),
                breakdown: makeBreakdown(hours: 6, gross: 240)
            )
        )
        context.insert(
            JobSupplement(
                job: primaryJob,
                label: "Housing stipend",
                kind: .housingStipend,
                amountPerInterval: 100,
                frequency: .weekly,
                anchorDate: makeDate(year: 2026, month: 4, day: 6, hour: 0),
                startDate: makeDate(year: 2026, month: 4, day: 6, hour: 0)
            )
        )
        context.insert(
            JobSupplement(
                job: secondaryJob,
                label: "Phone reimbursement",
                kind: .reimbursement,
                amountPerInterval: 60,
                frequency: .biweekly,
                anchorDate: makeDate(year: 2026, month: 4, day: 1, hour: 0),
                startDate: makeDate(year: 2026, month: 4, day: 1, hour: 0),
                taxTreatment: .nonTaxable
            )
        )
        try context.save()

        let summary = try ShiftController.summarySnapshot(in: context, at: makeDate(year: 2026, month: 4, day: 9, hour: 11))

        XCTAssertEqual(summary.combined.payPeriodAggregation, .variesByJob)
        XCTAssertEqual(summary.combined.payPeriodEffective.supplementalTotal, 0, accuracy: 0.001)
        XCTAssertEqual(summary.combined.payPeriodEffective.effectiveGross, 0, accuracy: 0.001)
        XCTAssertGreaterThan(summary.combined.allTimeEffective.supplementalTotal, 0)
        XCTAssertGreaterThan(summary.combined.allTimeEffective.effectiveGross, summary.combined.allTimeGross)
    }

    func testArchivedJobWithHistoryAppearsInPayPeriodArchive() throws {
        let archivedJob = JobProfile(name: "Old Job", accent: .coral)
        archivedJob.isArchived = true
        let schedule = PaySchedule(job: archivedJob, frequency: .weekly, anchorDate: makeDate(year: 2026, month: 4, day: 6, hour: 0))
        let payRate = PayRateSchedule(job: archivedJob, effectiveDate: makeDate(year: 2026, month: 1, day: 1, hour: 0), hourlyRate: 30)
        let shift = ShiftRecord(
            job: archivedJob,
            startDate: makeDate(year: 2026, month: 4, day: 7, hour: 8),
            endDate: makeDate(year: 2026, month: 4, day: 7, hour: 16),
            breakdown: makeBreakdown(hours: 8, gross: 240)
        )

        let snapshot = PayPeriodService.archiveSnapshot(
            asOf: makeDate(year: 2026, month: 4, day: 20, hour: 12),
            jobs: [archivedJob],
            completedShifts: [shift],
            paySchedules: [schedule],
            payRates: [payRate],
            nightRules: [],
            overtimeRules: [],
            templates: [],
            taxProfile: TaxProfile(),
            calendar: calendar
        )

        let section = try XCTUnwrap(snapshot.sections.first)
        XCTAssertEqual(section.title, "Old Job")
        XCTAssertFalse(section.summaries.contains { $0.status == .current && $0.shiftCount == 0 })
        XCTAssertTrue(section.summaries.contains { $0.grossEarnings == 240 })
    }

    func testArchivedHistoryDoesNotSuppressCurrentCombinedPayPeriod() throws {
        let firstJob = JobProfile(name: "Hospital", accent: .emerald, sortOrder: 0)
        let secondJob = JobProfile(name: "Clinic", accent: .sky, sortOrder: 1)
        let archivedJob = JobProfile(name: "Old Job", accent: .coral, sortOrder: 2, isArchived: true)
        let firstRate = PayRateSchedule(job: firstJob, effectiveDate: makeDate(year: 2026, month: 1, day: 1, hour: 0), hourlyRate: 50)
        let secondRate = PayRateSchedule(job: secondJob, effectiveDate: makeDate(year: 2026, month: 1, day: 1, hour: 0), hourlyRate: 30)
        let archivedRate = PayRateSchedule(job: archivedJob, effectiveDate: makeDate(year: 2026, month: 1, day: 1, hour: 0), hourlyRate: 25)
        let firstShift = ShiftRecord(
            job: firstJob,
            startDate: makeDate(year: 2026, month: 4, day: 7, hour: 8),
            endDate: makeDate(year: 2026, month: 4, day: 7, hour: 16),
            breakdown: makeBreakdown(hours: 8, gross: 400)
        )
        let secondShift = ShiftRecord(
            job: secondJob,
            startDate: makeDate(year: 2026, month: 4, day: 8, hour: 8),
            endDate: makeDate(year: 2026, month: 4, day: 8, hour: 14),
            breakdown: makeBreakdown(hours: 6, gross: 180)
        )
        let archivedShift = ShiftRecord(
            job: archivedJob,
            startDate: makeDate(year: 2026, month: 4, day: 1, hour: 8),
            endDate: makeDate(year: 2026, month: 4, day: 1, hour: 16),
            breakdown: makeBreakdown(hours: 8, gross: 200)
        )

        let snapshot = PayPeriodService.archiveSnapshot(
            asOf: makeDate(year: 2026, month: 4, day: 9, hour: 12),
            jobs: [firstJob, secondJob, archivedJob],
            completedShifts: [firstShift, secondShift, archivedShift],
            paySchedules: [
                PaySchedule(job: firstJob, frequency: .weekly, anchorDate: makeDate(year: 2026, month: 4, day: 6, hour: 0)),
                PaySchedule(job: secondJob, frequency: .weekly, anchorDate: makeDate(year: 2026, month: 4, day: 6, hour: 0)),
                PaySchedule(job: archivedJob, frequency: .weekly, anchorDate: makeDate(year: 2026, month: 4, day: 6, hour: 0))
            ],
            payRates: [firstRate, secondRate, archivedRate],
            nightRules: [],
            overtimeRules: [],
            templates: [],
            taxProfile: TaxProfile(),
            calendar: calendar
        )

        let combinedSection = try XCTUnwrap(snapshot.sections.first { $0.isCombined })
        let currentCombined = try XCTUnwrap(combinedSection.summaries.first { $0.interval.start == makeDate(year: 2026, month: 4, day: 6, hour: 0) })

        XCTAssertEqual(currentCombined.grossEarnings, 580, accuracy: 0.001)
        XCTAssertFalse(currentCombined.shifts.contains { $0.shiftIdentifier == archivedShift.id })
    }

    func testPayPeriodPDFExporterCreatesNonEmptyPDF() throws {
        let job = JobProfile(name: "Main Job")
        let schedule = PaySchedule(job: job, frequency: .weekly, anchorDate: makeDate(year: 2026, month: 4, day: 6, hour: 0))
        let payRate = PayRateSchedule(job: job, effectiveDate: makeDate(year: 2026, month: 1, day: 1, hour: 0), hourlyRate: 50)
        let shift = ShiftRecord(
            job: job,
            startDate: makeDate(year: 2026, month: 4, day: 7, hour: 8),
            endDate: makeDate(year: 2026, month: 4, day: 7, hour: 16),
            breakdown: makeBreakdown(hours: 8, gross: 400)
        )
        let snapshot = PayPeriodService.archiveSnapshot(
            asOf: makeDate(year: 2026, month: 4, day: 8, hour: 12),
            jobs: [job],
            completedShifts: [shift],
            paySchedules: [schedule],
            payRates: [payRate],
            nightRules: [],
            overtimeRules: [],
            templates: [],
            taxProfile: TaxProfile(),
            calendar: calendar
        )
        let summary = try XCTUnwrap(snapshot.sections.first?.summaries.first)

        let url = try PayPeriodPDFExporter.export(summary: summary, generatedAt: makeDate(year: 2026, month: 4, day: 8, hour: 13))
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = try XCTUnwrap(attributes[.size] as? NSNumber)
        XCTAssertGreaterThan(fileSize.intValue, 0)
    }

    func testPayPeriodPDFExporterRendersReadableContrast() throws {
        let job = JobProfile(name: "Main Job", accent: .emerald)
        let schedule = PaySchedule(job: job, frequency: .weekly, anchorDate: makeDate(year: 2026, month: 4, day: 6, hour: 0))
        let payRate = PayRateSchedule(job: job, effectiveDate: makeDate(year: 2026, month: 1, day: 1, hour: 0), hourlyRate: 50)
        let shifts = [
            ShiftRecord(
                job: job,
                startDate: makeDate(year: 2026, month: 4, day: 7, hour: 8),
                endDate: makeDate(year: 2026, month: 4, day: 7, hour: 16),
                note: "Day shift",
                breakdown: makeBreakdown(hours: 8, gross: 400)
            ),
            ShiftRecord(
                job: job,
                startDate: makeDate(year: 2026, month: 4, day: 8, hour: 19),
                endDate: makeDate(year: 2026, month: 4, day: 9, hour: 7),
                note: "Night shift",
                breakdown: makeBreakdown(hours: 12, gross: 675)
            )
        ]
        let snapshot = PayPeriodService.archiveSnapshot(
            asOf: makeDate(year: 2026, month: 4, day: 9, hour: 12),
            jobs: [job],
            completedShifts: shifts,
            paySchedules: [schedule],
            payRates: [payRate],
            nightRules: [],
            overtimeRules: [],
            templates: [],
            taxProfile: TaxProfile(),
            calendar: calendar
        )
        let summary = try XCTUnwrap(snapshot.sections.first?.summaries.first)

        let url = try PayPeriodPDFExporter.export(summary: summary, generatedAt: makeDate(year: 2026, month: 4, day: 9, hour: 13))
        let renderedPage = try renderFirstPage(of: url)
        let metrics = try imageLuminanceMetrics(renderedPage)

        XCTAssertLessThan(metrics.averageLuminance, 0.97)
        XCTAssertGreaterThan(metrics.darkPixelFraction, 0.03)
    }

    func testPayPeriodPDFExporterMovesBreakdownHeadingToNextPage() throws {
        let job = JobProfile(name: "Main Job", accent: .emerald)
        let schedule = PaySchedule(job: job, frequency: .weekly, anchorDate: makeDate(year: 2026, month: 4, day: 6, hour: 0))
        let payRate = PayRateSchedule(job: job, effectiveDate: makeDate(year: 2026, month: 1, day: 1, hour: 0), hourlyRate: 50)
        let shifts = [
            ShiftRecord(
                job: job,
                startDate: makeDate(year: 2026, month: 4, day: 7, hour: 8),
                endDate: makeDate(year: 2026, month: 4, day: 7, hour: 16),
                note: "Day shift",
                breakdown: makeBreakdown(hours: 8, gross: 400)
            ),
            ShiftRecord(
                job: job,
                startDate: makeDate(year: 2026, month: 4, day: 8, hour: 19),
                endDate: makeDate(year: 2026, month: 4, day: 9, hour: 7),
                note: "Night shift",
                breakdown: makeBreakdown(hours: 12, gross: 675)
            )
        ]
        let snapshot = PayPeriodService.archiveSnapshot(
            asOf: makeDate(year: 2026, month: 4, day: 9, hour: 12),
            jobs: [job],
            completedShifts: shifts,
            paySchedules: [schedule],
            payRates: [payRate],
            nightRules: [],
            overtimeRules: [],
            templates: [],
            taxProfile: TaxProfile(),
            calendar: calendar
        )
        let summary = try XCTUnwrap(snapshot.sections.first?.summaries.first)

        let url = try PayPeriodPDFExporter.export(summary: summary, generatedAt: makeDate(year: 2026, month: 4, day: 9, hour: 13))
        let document = try XCTUnwrap(PDFDocument(url: url))
        let firstPageText = try XCTUnwrap(document.page(at: 0)?.string)
        let secondPageText = try XCTUnwrap(document.page(at: 1)?.string)

        XCTAssertGreaterThanOrEqual(document.pageCount, 2)
        XCTAssertFalse(firstPageText.contains("Breakdown"))
        XCTAssertTrue(secondPageText.contains("Breakdown"))
    }

    func testPayPeriodPDFExporterUsesEffectiveHeadlineForSupplementOnlySummary() throws {
        let job = JobProfile(name: "Main Job", accent: .emerald)
        let schedule = PaySchedule(job: job, frequency: .weekly, anchorDate: makeDate(year: 2026, month: 4, day: 6, hour: 0))
        let payRate = PayRateSchedule(job: job, effectiveDate: makeDate(year: 2026, month: 1, day: 1, hour: 0), hourlyRate: 50)
        let supplement = JobSupplement(
            job: job,
            label: "Housing stipend",
            kind: .housingStipend,
            amountPerInterval: 120,
            frequency: .weekly,
            anchorDate: makeDate(year: 2026, month: 4, day: 6, hour: 0),
            startDate: makeDate(year: 2026, month: 4, day: 6, hour: 0),
            taxTreatment: .taxable
        )

        let snapshot = PayPeriodService.archiveSnapshot(
            asOf: makeDate(year: 2026, month: 4, day: 14, hour: 12),
            jobs: [job],
            completedShifts: [],
            paySchedules: [schedule],
            payRates: [payRate],
            nightRules: [],
            overtimeRules: [],
            supplements: [supplement],
            templates: [],
            taxProfile: TaxProfile(),
            calendar: calendar
        )
        let summary = try XCTUnwrap(
            snapshot.sections.first?.summaries.first {
                $0.interval.start == makeDate(year: 2026, month: 4, day: 6, hour: 0)
            }
        )

        let url = try PayPeriodPDFExporter.export(summary: summary, generatedAt: makeDate(year: 2026, month: 4, day: 14, hour: 13))
        let document = try XCTUnwrap(PDFDocument(url: url))
        let firstPageText = try XCTUnwrap(document.page(at: 0)?.string)
        let normalizedFirstPageText = firstPageText.replacingOccurrences(of: "\n", with: " ")

        XCTAssertTrue(firstPageText.contains(summary.displayMetricTitle(for: .gross)))
        XCTAssertTrue(firstPageText.contains(summary.displayMetricTitle(for: .takeHome)))
        XCTAssertTrue(normalizedFirstPageText.contains(summary.supplementContextLabel))
        XCTAssertTrue(normalizedFirstPageText.localizedCaseInsensitiveContains("no shifts"))
    }

    func testPayPeriodPDFExporterUsesSupplementInclusiveRateInSnapshot() throws {
        let job = JobProfile(name: "Main Job", accent: .emerald)
        let schedule = PaySchedule(job: job, frequency: .weekly, anchorDate: makeDate(year: 2026, month: 4, day: 6, hour: 0))
        let payRate = PayRateSchedule(job: job, effectiveDate: makeDate(year: 2026, month: 1, day: 1, hour: 0), hourlyRate: 50)
        let shift = ShiftRecord(
            job: job,
            startDate: makeDate(year: 2026, month: 4, day: 7, hour: 8),
            endDate: makeDate(year: 2026, month: 4, day: 7, hour: 16),
            breakdown: makeBreakdown(hours: 8, gross: 400)
        )
        let supplement = JobSupplement(
            job: job,
            label: "Housing stipend",
            kind: .housingStipend,
            amountPerInterval: 175,
            frequency: .weekly,
            anchorDate: makeDate(year: 2026, month: 4, day: 6, hour: 0),
            startDate: makeDate(year: 2026, month: 4, day: 6, hour: 0),
            taxTreatment: .taxable
        )

        let snapshot = PayPeriodService.archiveSnapshot(
            asOf: makeDate(year: 2026, month: 4, day: 14, hour: 12),
            jobs: [job],
            completedShifts: [shift],
            paySchedules: [schedule],
            payRates: [payRate],
            nightRules: [],
            overtimeRules: [],
            supplements: [supplement],
            templates: [],
            taxProfile: TaxProfile(),
            calendar: calendar
        )
        let summary = try XCTUnwrap(
            snapshot.sections.first?.summaries.first {
                $0.interval.start == makeDate(year: 2026, month: 4, day: 6, hour: 0)
            }
        )
        let displayRate = try XCTUnwrap(summary.displayHourlyRate)
        XCTAssertNotEqual(displayRate, summary.effectiveHourlyRate, accuracy: 0.001)

        let url = try PayPeriodPDFExporter.export(summary: summary, generatedAt: makeDate(year: 2026, month: 4, day: 14, hour: 13))
        let document = try XCTUnwrap(PDFDocument(url: url))
        let firstPageText = try XCTUnwrap(document.page(at: 0)?.string)

        XCTAssertTrue(firstPageText.contains(displayRate.formatted(.currency(code: "USD"))))
        XCTAssertFalse(firstPageText.contains(summary.effectiveHourlyRate.formatted(.currency(code: "USD")) + "/hr"))
    }

    func testPayPeriodPDFTextLayoutFitsLongHeaderNames() {
        let font = UIFont.systemFont(ofSize: 28, weight: .heavy)
        let fitted = PayPeriodPDFTextLayout.fittedSingleLine(
            "This is a very long job name that should be reduced and truncated before it reaches the rest of the header",
            font: font,
            maxWidth: 180,
            minimumPointSize: 22
        )

        XCTAssertLessThanOrEqual(
            PayPeriodPDFTextLayout.measuredWidth(for: fitted.text, font: fitted.font),
            180
        )
        XCTAssertLessThanOrEqual(fitted.font.pointSize, font.pointSize)
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func makeActiveJob(
        name: String,
        startDate: Date,
        gross: Double,
        takeHome: Double,
        effectiveGross: Double? = nil,
        effectiveTakeHome: Double? = nil,
        rate: Double
    ) -> ActiveJobSnapshot {
        ActiveJobSnapshot(
            id: UUID(),
            name: name,
            accent: .emerald,
            startDate: startDate,
            scheduledEndDate: nil,
            currentBreakdown: EarningsBreakdown(
                totalHours: rate > 0 ? gross / rate : 0,
                grossEarnings: gross,
                baseEarnings: gross,
                nightPremiumEarnings: 0,
                overtimePremiumEarnings: 0,
                regularHours: rate > 0 ? gross / rate : 0,
                nightHours: 0,
                overtimeHours: 0,
                effectiveRate: rate
            ),
            currentGross: gross,
            currentTakeHome: takeHome,
            currentEffectiveGross: effectiveGross ?? gross,
            currentEffectiveTakeHome: effectiveTakeHome ?? takeHome
        )
    }

    private func makeDashboardSnapshot(
        activeJobs: [ActiveJobSnapshot],
        currentGross: Double,
        currentTakeHome: Double,
        currentEffectiveGross: Double? = nil,
        currentEffectiveTakeHome: Double? = nil,
        effectiveRate: Double
    ) -> DashboardSnapshot {
        let resolvedEffectiveGross = currentEffectiveGross ?? currentGross
        let resolvedEffectiveTakeHome = currentEffectiveTakeHome ?? currentTakeHome
        let totalHours = effectiveRate > 0 ? currentGross / effectiveRate : 0
        return DashboardSnapshot(
            currentBreakdown: activeJobs.isEmpty
                ? nil
                : EarningsBreakdown(
                    totalHours: totalHours,
                    grossEarnings: currentGross,
                    baseEarnings: currentGross,
                    nightPremiumEarnings: 0,
                    overtimePremiumEarnings: 0,
                    regularHours: totalHours,
                    nightHours: 0,
                    overtimeHours: 0,
                    effectiveRate: effectiveRate
                ),
            activeJobs: activeJobs,
            hasSupplementConfiguration: abs(resolvedEffectiveGross - currentGross) > 0.000_001
                || abs(resolvedEffectiveTakeHome - currentTakeHome) > 0.000_001,
            currentGross: currentGross,
            currentTakeHome: currentTakeHome,
            currentEffectiveGross: resolvedEffectiveGross,
            currentEffectiveTakeHome: resolvedEffectiveTakeHome,
            payPeriodAggregation: .unified,
            payPeriodGross: currentGross,
            payPeriodTakeHome: currentTakeHome,
            payPeriodEffectiveGross: resolvedEffectiveGross,
            payPeriodEffectiveTakeHome: resolvedEffectiveTakeHome,
            payPeriodHours: 0,
            payPeriodNightPremium: 0,
            allTimeGross: currentGross,
            allTimeTakeHome: currentTakeHome,
            allTimeEffectiveGross: resolvedEffectiveGross,
            allTimeEffectiveTakeHome: resolvedEffectiveTakeHome,
            projectedPaycheckGross: currentGross,
            projectedPaycheckTakeHome: currentTakeHome,
            projectedPaycheckEffectiveGross: resolvedEffectiveGross,
            projectedPaycheckEffectiveTakeHome: resolvedEffectiveTakeHome,
            projectedConfidenceLabel: "Earned so far",
            allTimeHours: 0
        )
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

    private func renderFirstPage(of url: URL) throws -> UIImage {
        guard let provider = CGDataProvider(url: url as CFURL) else {
            XCTFail("Unable to create data provider for PDF")
            throw NSError(domain: "MoneyTrackerEngineTests", code: 1)
        }
        guard let document = CGPDFDocument(provider), let page = document.page(at: 1) else {
            XCTFail("Unable to load first PDF page")
            throw NSError(domain: "MoneyTrackerEngineTests", code: 2)
        }

        let pageRect = page.getBoxRect(.mediaBox)
        let size = CGSize(width: pageRect.width, height: pageRect.height)

        return UIGraphicsImageRenderer(size: size).image { rendererContext in
            UIColor.white.setFill()
            rendererContext.fill(CGRect(origin: .zero, size: size))

            let cgContext = rendererContext.cgContext
            cgContext.translateBy(x: 0, y: size.height)
            cgContext.scaleBy(x: 1, y: -1)
            cgContext.drawPDFPage(page)
        }
    }

    private func imageLuminanceMetrics(_ image: UIImage) throws -> (averageLuminance: Double, darkPixelFraction: Double) {
        guard let cgImage = image.cgImage else {
            XCTFail("Unable to access rendered PDF image")
            throw NSError(domain: "MoneyTrackerEngineTests", code: 3)
        }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width * 4
        var buffer = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let bitmapContext = CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            XCTFail("Unable to create bitmap context")
            throw NSError(domain: "MoneyTrackerEngineTests", code: 4)
        }

        bitmapContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var luminanceTotal = 0.0
        var darkPixelCount = 0
        let pixelCount = width * height

        for offset in stride(from: 0, to: buffer.count, by: 4) {
            let red = Double(buffer[offset]) / 255.0
            let green = Double(buffer[offset + 1]) / 255.0
            let blue = Double(buffer[offset + 2]) / 255.0
            let luminance = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
            luminanceTotal += luminance
            if luminance < 0.45 {
                darkPixelCount += 1
            }
        }

        return (
            averageLuminance: luminanceTotal / Double(pixelCount),
            darkPixelFraction: Double(darkPixelCount) / Double(pixelCount)
        )
    }
}
