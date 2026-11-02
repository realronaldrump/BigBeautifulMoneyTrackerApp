import Foundation
import SwiftData
import XCTest

#if canImport(UIKit)
    import PDFKit
#endif
#if SWIFT_PACKAGE
    @testable import MoneyTrackerCore
#else
    @testable import BigBeautifulMoneyTracker
#endif

final class SalaryTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private func date(_ month: Int, _ day: Int, _ hour: Int = 0, calendar: Calendar? = nil) -> Date {
        (calendar ?? self.calendar).date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }
    private func plan(
        job: JobProfile? = nil, amount: Double = 3_000,
        frequency: PayFrequency = .biweekly, mode: SalaryAccrualMode = .continuous,
        anchor: Date? = nil, effective: Date? = nil
    ) -> SalaryPlan {
        SalaryPlan(
            job: job, effectiveDate: effective ?? date(4, 6), amount: amount, amountBasis: .perPaycheck,
            frequency: frequency, anchorDate: anchor ?? date(4, 6), accrualMode: mode,
            timeZoneIdentifier: "GMT")
    }
    private func accrued(_ plan: SalaryPlan, through date: Date) -> Double {
        SalaryEngine.lifetimeGross(for: [plan], through: date)
    }
    private func storedJob(in context: ModelContext) throws -> JobProfile {
        try DataBootstrapper.seedIfNeeded(in: context)
        return try XCTUnwrap(JobService.jobs(in: context).first)
    }

    func testExistingJobsRemainHourly() {
        let job = JobProfile()
        XCTAssertEqual(job.compensationKind, .hourly)
        job.compensationKindRawValue = "unrecognized"
        XCTAssertEqual(job.compensationKind, .hourly)
    }

    func testContinuousCounterAtStartHalfAndFullPeriod() {
        let value = plan()
        XCTAssertEqual(accrued(value, through: date(4, 6)), 0, accuracy: 0.0001)
        XCTAssertEqual(accrued(value, through: date(4, 13)), 1_500, accuracy: 0.0001)
        XCTAssertEqual(accrued(value, through: date(4, 20)), 3_000, accuracy: 0.0001)
    }

    func testAnnualConversionUsesEachSupportedPayFrequency() {
        for frequency in PayFrequency.allCases {
            let value = plan(frequency: frequency)
            value.amount = 78_000
            value.amountBasisRawValue = SalaryAmountBasis.annual.rawValue
            XCTAssertEqual(value.paycheckGross, 78_000 / frequency.periodsPerYear, accuracy: 0.0001)
            XCTAssertEqual(value.annualGross, 78_000, accuracy: 0.0001)
        }
    }

    func testSelectedWorkdaysPauseOnWeekendAndConservePaycheck() {
        let value = plan(mode: .workdays)
        XCTAssertEqual(accrued(value, through: date(4, 11)), 1_500, accuracy: 0.0001)
        XCTAssertEqual(accrued(value, through: date(4, 13)), 1_500, accuracy: 0.0001)
        XCTAssertEqual(accrued(value, through: date(4, 20)), 3_000, accuracy: 0.0001)
    }

    func testOptionalWindowOnlyChangesVisualizationTiming() {
        let value = plan(mode: .workdays)
        value.usesWorkHours = true
        XCTAssertEqual(accrued(value, through: date(4, 6, 9)), 0, accuracy: 0.0001)
        XCTAssertEqual(accrued(value, through: date(4, 6, 13)), 150, accuracy: 0.0001)
        XCTAssertEqual(accrued(value, through: date(4, 6, 17)), 300, accuracy: 0.0001)
        XCTAssertEqual(accrued(value, through: date(4, 7, 8)), 300, accuracy: 0.0001)
        XCTAssertEqual(accrued(value, through: date(4, 20)), 3_000, accuracy: 0.0001)
    }

    func testPaidHolidayRemainsPartOfSelectedWeekdays() {
        let value = plan(frequency: .weekly, mode: .workdays, anchor: date(11, 23), effective: date(11, 23))
        let thanksgiving = DateInterval(start: date(11, 26), end: date(11, 27))
        XCTAssertEqual(
            SalaryEngine.gross(for: [value], within: thanksgiving, through: thanksgiving.end), 600, accuracy: 0.0001)
    }

    func testPartialFirstAndLastPeriodsAreProrated() {
        let value = plan(effective: date(4, 13))
        value.endDate = date(4, 17)
        XCTAssertEqual(accrued(value, through: date(4, 30)), 3_000 * 4 / 14, accuracy: 0.0001)
    }

    func testMonthlyAnchorSurvivesFebruaryAndLeapYearBoundaries() {
        let value = plan(frequency: .monthly, anchor: date(1, 31), effective: date(1, 31))
        XCTAssertEqual(
            SalaryEngine.period(for: value, at: date(3, 1)), DateInterval(start: date(2, 28), end: date(3, 31)))
        XCTAssertEqual(accrued(value, through: date(3, 31)), 6_000, accuracy: 0.0001)
    }

    func testSemiMonthlyUnequalPeriodLengthsKeepTheSamePaycheck() {
        let value = plan(frequency: .semiMonthly, anchor: date(1, 1), effective: date(1, 1))
        XCTAssertEqual(accrued(value, through: date(1, 16)), 3_000, accuracy: 0.0001)
        XCTAssertEqual(accrued(value, through: date(2, 1)), 6_000, accuracy: 0.0001)
    }

    func testDSTSpringAndFallWindowsConserveFullPaychecks() {
        var denver = calendar
        denver.timeZone = TimeZone(identifier: "America/Denver")!
        for (month, day) in [(3, 2), (10, 26)] {
            let start = date(month, day, calendar: denver)
            let end = denver.date(byAdding: .day, value: 14, to: start)!
            let value = plan(anchor: start, effective: start)
            value.timeZoneIdentifier = denver.timeZone.identifier
            var cursor = start
            var total = 0.0
            while cursor < end {
                let next = denver.date(byAdding: .day, value: 1, to: cursor)!
                total += SalaryEngine.gross(for: [value], within: DateInterval(start: cursor, end: next), through: next)
                cursor = next
            }
            XCTAssertEqual(total, 3_000, accuracy: 0.0001)
            XCTAssertEqual(accrued(value, through: end), 3_000, accuracy: 0.0001)
        }
    }

    func testNoEarningsBeforeEffectiveDateOrAfterEndDate() {
        let value = plan()
        value.endDate = date(4, 20)
        XCTAssertEqual(accrued(value, through: date(4, 1)), 0)
        XCTAssertEqual(accrued(value, through: date(8, 1)), 3_000, accuracy: 0.0001)
    }

    func testDatedRaisePreservesEarlierEarnings() {
        let first = plan()
        first.endDate = date(4, 20)
        let raised = plan(amount: 4_000, effective: date(4, 20))
        let before = DateInterval(start: date(4, 6), end: date(4, 20))
        let after = DateInterval(start: date(4, 20), end: date(5, 4))
        XCTAssertEqual(
            SalaryEngine.gross(for: [first, raised], within: before, through: date(6, 1)), 3_000, accuracy: 0.0001)
        XCTAssertEqual(
            SalaryEngine.gross(for: [first, raised], within: after, through: date(6, 1)), 4_000, accuracy: 0.0001)
    }

    func testChangingDisplayAtBoundaryPreservesFixedPaycheck() {
        let first = plan()
        first.endDate = date(4, 20)
        let workdays = plan(mode: .workdays, effective: date(4, 20))
        XCTAssertEqual(
            SalaryEngine.lifetimeGross(for: [first, workdays], through: date(5, 4)), 6_000, accuracy: 0.0001)
    }

    func testPaydayOffsetFindsPreviousPeriodsUpcomingDeposit() {
        let value = plan()
        value.paydayOffsetDays = 7
        XCTAssertEqual(SalaryEngine.nextPayday(for: [value], at: date(4, 22), plan: value), date(4, 27))
        XCTAssertEqual(SalaryEngine.nextPayday(for: [value], at: date(4, 27, 12), plan: value), date(4, 27))
        XCTAssertEqual(SalaryEngine.nextPayday(for: [value], at: date(4, 28), plan: value), date(5, 11))
    }

    func testPaydayCanFallOnLastIncludedDayOfPeriod() {
        let value = plan()
        value.paydayOffsetDays = -1
        XCTAssertNoThrow(try SalaryService.validate(value))
        XCTAssertEqual(SalaryEngine.nextPayday(for: [value], at: date(4, 13), plan: value), date(4, 19))
    }

    func testInvalidSalaryInputsAreRejected() {
        let value = plan()
        for amount in [0.0, -1, .nan, .infinity] {
            value.amount = amount
            XCTAssertThrowsError(try SalaryService.validate(value))
        }
        value.amount = 3_000
        value.accrualModeRawValue = SalaryAccrualMode.workdays.rawValue
        value.weekdaysRawValue = ""
        XCTAssertThrowsError(try SalaryService.validate(value))
        value.weekdaysRawValue = "2,3,4,5,6"
        value.usesWorkHours = true
        value.endMinute = value.startMinute
        XCTAssertThrowsError(try SalaryService.validate(value))
    }

    func testSalaryDashboardAndSummaryIncludeSalaryWithoutShifts() throws {
        let container = AppModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let job = try storedJob(in: context)
        try SalaryService.savePlan(plan(job: job), for: job, in: context, now: date(4, 6))
        let result = try ShiftController.dashboardSnapshot(in: context, at: date(4, 13), calendar: calendar)
        XCTAssertTrue(result.activeJobs.isEmpty)
        XCTAssertEqual(result.salaryJobs.count, 1)
        XCTAssertEqual(result.salaryJobs.first?.progress ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertEqual(result.payPeriodGross, 1_500, accuracy: 0.0001)
        XCTAssertEqual(result.projectedPaycheckGross, 3_000, accuracy: 0.0001)
        XCTAssertEqual(result.allTimeGross, 1_500, accuracy: 0.0001)
        XCTAssertEqual(result.payPeriodHours, 0)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ShiftRecord>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<OpenShiftState>()).isEmpty)
    }

    func testPaycheckAndOptionalHoursDoNotAddSalaryAgain() throws {
        let container = AppModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let job = try storedJob(in: context)
        try SalaryService.savePlan(plan(job: job), for: job, in: context, now: date(4, 6))
        let interval = DateInterval(start: date(4, 6), end: date(4, 20))
        try SalaryService.savePayment(
            job: job, interval: interval, paidDate: date(4, 20), gross: 3_000, takeHome: 2_200, note: "Actual deposit",
            in: context, now: date(4, 20))
        try SalaryService.saveWorkLog(job: job, date: date(4, 7), hours: 8, note: "", in: context, now: date(4, 20))
        let snapshot = try ShiftController.dashboardSnapshot(in: context, at: date(4, 19), calendar: calendar)
        XCTAssertEqual(snapshot.allTimeGross, 3_000 * 13 / 14, accuracy: 0.0001)
        XCTAssertEqual(snapshot.salaryJobs.first?.loggedHours, 8)
        XCTAssertEqual(snapshot.salaryJobs.first?.effectiveHourlyRate ?? 0, snapshot.allTimeGross / 8, accuracy: 0.0001)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SalaryPayment>()).count, 1)
    }

    func testDuplicatePaychecksAndFutureDepositsAreRejected() throws {
        let container = AppModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let job = try storedJob(in: context)
        try SalaryService.savePlan(plan(job: job), for: job, in: context, now: date(4, 6))
        let interval = DateInterval(start: date(4, 6), end: date(4, 20))
        try SalaryService.savePayment(
            job: job, interval: interval, paidDate: date(4, 20), gross: 3_000, takeHome: nil, note: "", in: context,
            now: date(4, 20))
        XCTAssertThrowsError(
            try SalaryService.savePayment(
                job: job, interval: interval, paidDate: date(4, 20), gross: 3_000, takeHome: nil, note: "", in: context,
                now: date(4, 20)))
        let next = DateInterval(start: date(4, 20), end: date(5, 4))
        XCTAssertThrowsError(
            try SalaryService.savePayment(
                job: job, interval: next, paidDate: date(5, 4), gross: 3_000, takeHome: nil, note: "", in: context,
                now: date(4, 20)))
    }

    func testWorkHoursValidationCountsOtherEntriesOnSameDay() throws {
        let container = AppModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let job = try storedJob(in: context)
        try SalaryService.savePlan(plan(job: job), for: job, in: context, now: date(4, 6))
        try SalaryService.saveWorkLog(job: job, date: date(4, 7), hours: 16, note: "", in: context, now: date(4, 20))
        XCTAssertThrowsError(
            try SalaryService.saveWorkLog(
                job: job, date: date(4, 7, 12), hours: 9, note: "", in: context, now: date(4, 20)))
        XCTAssertThrowsError(
            try SalaryService.saveWorkLog(
                job: job, date: date(4, 7), hours: .nan, note: "", in: context, now: date(4, 20)))
    }

    func testHourlyShiftActionsRejectSalaryJob() throws {
        let container = AppModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let job = try storedJob(in: context)
        try SalaryService.savePlan(plan(job: job), for: job, in: context, now: date(4, 6))
        XCTAssertThrowsError(try ShiftController.startShifts(in: context, jobIdentifiers: [job.id], at: date(4, 7)))
        XCTAssertThrowsError(
            try ShiftController.saveManualShift(
                in: context, editing: nil, job: job, startDate: date(4, 7, 9), endDate: date(4, 7, 17)))
        XCTAssertThrowsError(
            try ShiftController.saveScheduledShift(
                in: context, editing: nil, job: job, startDate: date(4, 7, 9), endDate: date(4, 7, 17)))
    }

    func testHourlyTimingEditsCannotReachBackIntoSalaryHistory() throws {
        let container = AppModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let job = try storedJob(in: context)
        try SalaryService.savePlan(plan(job: job), for: job, in: context, now: date(4, 6))
        try SalaryService.switchToHourly(job: job, in: context, at: date(4, 13))
        context.insert(PayRateSchedule(job: job, effectiveDate: date(4, 13), hourlyRate: 25))
        try context.save()
        XCTAssertThrowsError(try ShiftController.startShifts(in: context, jobIdentifiers: [job.id], at: date(4, 12)))
        XCTAssertThrowsError(
            try ShiftController.saveScheduledShift(
                in: context, editing: nil, job: job,
                startDate: date(4, 12, 9), endDate: date(4, 12, 17)))
        let open = try XCTUnwrap(
            ShiftController.startShifts(in: context, jobIdentifiers: [job.id], at: date(4, 14)).first)
        XCTAssertThrowsError(
            try ShiftController.updateOpenShift(
                in: context, editing: open,
                startDate: date(4, 12), scheduledEndDate: nil, reminderOffsets: []))
        XCTAssertEqual(open.startDate, date(4, 14))
    }

    func testRevisionCannotRewriteHistoryOrChangeTimingMidPeriod() throws {
        let container = AppModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let job = try storedJob(in: context)
        let original = plan(job: job)
        try SalaryService.savePlan(original, for: job, in: context, now: date(4, 6))
        XCTAssertThrowsError(
            try SalaryService.savePlan(plan(job: job, effective: date(4, 10)), for: job, in: context, now: date(4, 13)))
        XCTAssertThrowsError(
            try SalaryService.savePlan(plan(job: job, effective: date(4, 14)), for: job, in: context, now: date(4, 13)))
        XCTAssertNil(original.endDate)
        try SalaryService.savePlan(
            plan(job: job, amount: 4_000, effective: date(4, 20)), for: job, in: context, now: date(4, 13))
        XCTAssertEqual(original.endDate, date(4, 20))
    }

    func testCancelFutureRevisionRestoresCurrentAgreement() throws {
        let container = AppModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let job = try storedJob(in: context)
        let original = plan(job: job)
        try SalaryService.savePlan(original, for: job, in: context, now: date(4, 6))
        let future = plan(job: job, amount: 4_000, effective: date(4, 20))
        try SalaryService.savePlan(future, for: job, in: context, now: date(4, 13))
        try SalaryService.cancelUpcomingPlan(future, in: context, now: date(4, 14))
        XCTAssertNil(original.endDate)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SalaryPlan>()).count, 1)
    }

    func testSwitchToHourlyStopsAccrualAndKeepsHistory() throws {
        let container = AppModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let job = try storedJob(in: context)
        try SalaryService.savePlan(plan(job: job), for: job, in: context, now: date(4, 6))
        try SalaryService.switchToHourly(job: job, in: context, at: date(4, 13))
        XCTAssertEqual(job.compensationKind, .hourly)
        let result = try ShiftController.dashboardSnapshot(in: context, at: date(4, 30), calendar: calendar)
        XCTAssertTrue(result.salaryJobs.isEmpty)
        XCTAssertEqual(result.allTimeGross, 1_500, accuracy: 0.0001)
    }

    func testArchiveIncludesClosedAndCurrentSalaryPeriodsWithoutShifts() throws {
        let job = JobProfile()
        let value = plan(job: job)
        let archive = PayPeriodService.archiveSnapshot(
            asOf: date(4, 27), jobs: [job], completedShifts: [], paySchedules: [], payRates: [], nightRules: [],
            overtimeRules: [], templates: [], taxProfile: TaxProfile(), calendar: calendar, salaryPlans: [value])
        let periods = try XCTUnwrap(archive.sections.first).summaries
        XCTAssertEqual(periods.count, 2)
        XCTAssertEqual(periods[0].salaryGross, 1_500, accuracy: 0.0001)
        XCTAssertEqual(periods[1].salaryGross, 3_000, accuracy: 0.0001)
        XCTAssertEqual(periods[1].grossEarnings, 3_000, accuracy: 0.0001)
        XCTAssertEqual(periods[1].totalHours, 0)
        XCTAssertTrue(periods[1].displaySummaryContext.contains("Salary"))
    }

    func testMixedSalaryAndHourlyJobTotalsAgreeWithArchive() throws {
        let container = AppModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let salaryJob = try storedJob(in: context)
        try SalaryService.savePlan(plan(job: salaryJob), for: salaryJob, in: context, now: date(4, 6))
        let hourlyJob = try JobService.createJob(in: context, name: "Hourly", anchorDate: date(4, 6))
        try context.fetch(FetchDescriptor<PaySchedule>()).first { $0.job?.id == hourlyJob.id }?.anchorDate = date(4, 6)
        let rates = [PayRateSchedule(job: hourlyJob, effectiveDate: date(1, 1), hourlyRate: 20)]
        rates.forEach { context.insert($0) }
        try ShiftController.saveManualShift(
            in: context, editing: nil, job: hourlyJob, startDate: date(4, 7, 9), endDate: date(4, 7, 17))
        let summary = try ShiftController.summarySnapshot(in: context, at: date(4, 13), calendar: calendar)
        XCTAssertEqual(summary.combined.allTimeGross, 1_660, accuracy: 0.0001)
        XCTAssertEqual(summary.combined.payPeriodGross, 1_660, accuracy: 0.0001)
        let archive = PayPeriodService.archiveSnapshot(
            asOf: date(4, 13), jobs: [salaryJob, hourlyJob],
            completedShifts: try context.fetch(FetchDescriptor<ShiftRecord>()),
            paySchedules: try context.fetch(FetchDescriptor<PaySchedule>()), payRates: rates, nightRules: [],
            overtimeRules: [], templates: [], taxProfile: TaxProfile(), calendar: calendar,
            salaryPlans: try context.fetch(FetchDescriptor<SalaryPlan>()))
        let combined = try XCTUnwrap(archive.sections.first(where: { $0.isCombined })?.summaries.first)
        XCTAssertEqual(combined.grossEarnings, summary.combined.payPeriodGross, accuracy: 0.0001)
    }

    func testArchivedSalaryStopsAndRemainsInAllTimeTotal() throws {
        let container = AppModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let job = try storedJob(in: context)
        let value = plan(job: job)
        value.endDate = date(4, 13)
        context.insert(value)
        job.compensationKind = .salary
        job.isArchived = true
        job.archivedAt = date(4, 13)
        _ = try JobService.createJob(in: context, name: "Other")
        let result = try ShiftController.dashboardSnapshot(in: context, at: date(5, 1), calendar: calendar)
        XCTAssertTrue(result.salaryJobs.isEmpty)
        XCTAssertEqual(result.allTimeGross, 1_500, accuracy: 0.0001)
    }

    func testReleasedStoreMigratesWithoutLosingHourlyHistoryAndPersistsSalaryModels() throws {
        #if SWIFT_PACKAGE
            let bundle = Bundle.module
        #else
            let bundle = Bundle(for: SalaryTests.self)
        #endif
        let fixture = try XCTUnwrap(
            bundle.url(forResource: "PreSalary", withExtension: "sqlite", subdirectory: "Fixtures")
                ?? bundle.url(forResource: "PreSalary", withExtension: "sqlite"))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("MoneyTracker.sqlite")
        try FileManager.default.copyItem(at: fixture, to: url)
        do {
            let configuration = ModelConfiguration(
                "MoneyTracker", schema: AppModelContainerFactory.schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: AppModelContainerFactory.schema, configurations: [configuration])
            let context = ModelContext(container)
            let job = try XCTUnwrap(context.fetch(FetchDescriptor<JobProfile>()).first)
            XCTAssertEqual(job.compensationKind, .hourly)
            XCTAssertEqual(job.name, "Hourly job before salary support")
            let shift = try XCTUnwrap(context.fetch(FetchDescriptor<ShiftRecord>()).first)
            XCTAssertEqual(shift.grossEarnings, 200, accuracy: 0.0001)
            XCTAssertEqual(shift.job?.id, job.id)
            XCTAssertEqual(try context.fetch(FetchDescriptor<PayRateSchedule>()).first?.hourlyRate, 25)
            XCTAssertEqual(try context.fetch(FetchDescriptor<AppPreferences>()).first?.onboardingCompleted, true)
            try SalaryService.savePlan(
                plan(job: job, anchor: date(5, 1), effective: date(5, 1)), for: job, in: context, now: date(5, 1))
            try SalaryService.saveWorkLog(
                job: job, date: date(5, 2), hours: 8, note: "Synthetic work hours", in: context, now: date(5, 20))
            try SalaryService.savePayment(
                job: job, interval: DateInterval(start: date(5, 1), end: date(5, 15)), paidDate: date(5, 15),
                gross: 3_000, takeHome: 2_200, note: "Synthetic paycheck", in: context, now: date(5, 20))
        }
        let configuration = ModelConfiguration(
            "MoneyTracker", schema: AppModelContainerFactory.schema, url: url, cloudKitDatabase: .none)
        let reopened = try ModelContainer(for: AppModelContainerFactory.schema, configurations: [configuration])
        let context = ModelContext(reopened)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ShiftRecord>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SalaryPlan>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SalaryPayment>()).first?.takeHome, 2_200)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SalaryWorkLog>()).first?.hours, 8)
        XCTAssertEqual(try context.fetch(FetchDescriptor<JobProfile>()).first?.compensationKind, .salary)
    }

    func testPayCycleChangePreservesSalaryAndSupplementArchiveTotals() throws {
        let job = JobProfile()
        job.compensationKind = .salary
        let first = plan(job: job)
        first.endDate = date(4, 20)
        let changed = plan(job: job, amount: 1_500, frequency: .weekly, anchor: date(4, 20), effective: date(4, 20))
        let supplement = JobSupplement(
            job: job, label: "Stipend", amountPerInterval: 140,
            frequency: .biweekly, anchorDate: date(4, 6), startDate: date(4, 6))
        let archive = PayPeriodService.archiveSnapshot(
            asOf: date(5, 4), jobs: [job], completedShifts: [],
            paySchedules: [PaySchedule(job: job, frequency: .monthly, anchorDate: date(4, 1))], payRates: [],
            nightRules: [], overtimeRules: [], supplements: [supplement], templates: [], taxProfile: TaxProfile(),
            calendar: calendar,
            salaryPlans: [first, changed])
        let summaries = try XCTUnwrap(archive.sections.first).summaries
        XCTAssertEqual(summaries.reduce(0) { $0 + $1.salaryGross }, 6_000, accuracy: 0.0001)
        XCTAssertEqual(summaries.reduce(0) { $0 + $1.supplementalTotal }, 280, accuracy: 0.0001)
        for (index, summary) in summaries.enumerated() {
            for other in summaries.dropFirst(index + 1) {
                XCTAssertFalse(
                    summary.interval.start < other.interval.end && other.interval.start < summary.interval.end)
            }
        }
    }

    func testFutureSnapshotDoesNotCreateShiftsOrPayments() throws {
        let container = AppModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let job = try storedJob(in: context)
        try SalaryService.savePlan(plan(job: job), for: job, in: context, now: date(4, 6))
        for day in 1...16 {
            _ = try ShiftController.dashboardSnapshot(in: context, at: date(5, day), calendar: calendar)
        }
        XCTAssertEqual(try context.fetch(FetchDescriptor<SalaryPlan>()).count, 1)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ShiftRecord>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SalaryPayment>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SalaryWorkLog>()).isEmpty)
    }

    func testUpcomingSalaryHasZeroAccruedAndAVisibleFuturePaycheck() throws {
        let container = AppModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let job = try storedJob(in: context)
        try SalaryService.savePlan(
            plan(job: job, anchor: date(5, 1), effective: date(5, 1)), for: job, in: context, now: date(4, 1))
        let result = try ShiftController.dashboardSnapshot(in: context, at: date(4, 1), calendar: calendar)
        XCTAssertEqual(result.salaryJobs.first?.isUpcoming, true)
        XCTAssertEqual(result.payPeriodGross, 0)
        XCTAssertEqual(result.projectedPaycheckGross, 3_000, accuracy: 0.0001)
        XCTAssertEqual(result.allTimeGross, 0)
    }

    func testHistoricalSalaryTaxEstimateUsesTheAgreementForThatPeriod() throws {
        let job = JobProfile()
        job.compensationKind = .salary
        let first = plan(job: job)
        first.endDate = date(4, 20)
        let raised = plan(job: job, amount: 5_000, effective: date(4, 20))
        let archive = PayPeriodService.archiveSnapshot(
            asOf: date(5, 11), jobs: [job], completedShifts: [], paySchedules: [], payRates: [], nightRules: [],
            overtimeRules: [], templates: [], taxProfile: TaxProfile(), calendar: calendar,
            salaryPlans: [raised, first])
        let oldPeriod = try XCTUnwrap(archive.sections.first?.summaries.first { $0.interval.start == date(4, 6) })
        XCTAssertEqual(oldPeriod.annualizedGrossIncome, 78_000, accuracy: 0.0001)
        let newPeriod = try XCTUnwrap(archive.sections.first?.summaries.first { $0.interval.start == date(4, 20) })
        XCTAssertEqual(newPeriod.annualizedGrossIncome, 130_000, accuracy: 0.0001)
    }

    #if canImport(UIKit)
        func testSalaryPDFContainsSalaryAmountsAndNoInventedHourlyBreakdown() throws {
            let job = JobProfile(name: "Salary Example")
            job.compensationKind = .salary
            let value = plan(job: job)
            let archive = PayPeriodService.archiveSnapshot(
                asOf: date(4, 20), jobs: [job], completedShifts: [], paySchedules: [], payRates: [], nightRules: [],
                overtimeRules: [], templates: [], taxProfile: TaxProfile(), calendar: calendar, salaryPlans: [value])
            let summary = try XCTUnwrap(archive.sections.first?.summaries.first { $0.status == .closed })
            let url = try PayPeriodPDFExporter.export(summary: summary, generatedAt: date(4, 20))
            defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            let document = try XCTUnwrap(PDFDocument(url: url))
            let text = try XCTUnwrap(document.string)
            XCTAssertTrue(text.contains("Salary accrued"))
            XCTAssertTrue(text.contains("$3,000.00"))
            XCTAssertTrue(text.contains("Salary Visualization"))
            XCTAssertFalse(text.contains("Base Earnings"))
            XCTAssertTrue(text.contains("visualization estimate"))
        }
    #endif
}
