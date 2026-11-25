import XCTest

@MainActor
final class BottomNavigationTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ scenario: String, largeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["MONEY_TRACKER_UI_SCENARIO"] = scenario
        app.launchEnvironment["MONEY_TRACKER_UI_LARGE_TEXT"] = largeText ? "1" : "0"
        app.launch()
        XCTAssertTrue(app.buttons["main.tab.home"].waitForExistence(timeout: 15))
        return app
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertShiftActionAboveNavigation(_ app: XCUIApplication, label: String) {
        let action = app.buttons["home.shiftAction"]
        let correctLabel = NSPredicate(format: "label == %@ AND hittable == YES", label)
        let appeared = XCTNSPredicateExpectation(predicate: correctLabel, object: action)
        XCTAssertEqual(XCTWaiter.wait(for: [appeared], timeout: 8), .completed,
                       "The primary shift action must be visible and tappable")
        XCTAssertLessThanOrEqual(action.frame.maxY, app.buttons["main.tab.home"].frame.minY,
                                 "The action must sit above the bottom navigation")
    }

    func testSelectedHourlyJobCanStartAndEndAboveMenu() {
        let app = launch("hourlyJobs")
        capture(app, name: "Hourly Home before starting")
        assertShiftActionAboveNavigation(app, label: "Start Shift")
        app.buttons["home.shiftAction"].tap()
        assertShiftActionAboveNavigation(app, label: "End shift")
        capture(app, name: "Active shift above navigation")
        app.buttons["home.shiftAction"].tap()
        assertShiftActionAboveNavigation(app, label: "Start Shift")
    }

    func testLastJobSettingsRowCanBeReachedAboveMenu() {
        let app = launch("hourlyJobs")
        app.buttons["main.tab.settings"].tap()
        let job = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Business System Support Analyst")).firstMatch
        for _ in 0..<8 {
            if job.exists && job.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(job.waitForExistence(timeout: 8))
        job.tap()
        let archive = app.buttons["settings.archiveJob"]
        for _ in 0..<12 {
            if archive.exists && archive.isHittable && archive.frame.maxY < app.buttons["main.tab.settings"].frame.minY { break }
            app.swipeUp()
        }
        capture(app, name: "Last job settings row")
        XCTAssertTrue(archive.isHittable, "The last form action must remain tappable")
        XCTAssertLessThanOrEqual(archive.frame.maxY, app.buttons["main.tab.settings"].frame.minY)
        archive.tap()
        let confirm = app.buttons["Archive Business System Support Analyst"]
        let opened = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == YES"), object: confirm)
        XCTAssertEqual(XCTWaiter.wait(for: [opened], timeout: 5), .completed, "Archive confirmation must open")
        capture(app, name: "Archive confirmation")
        if app.buttons["Cancel"].exists {
            app.buttons["Cancel"].tap()
        } else {
            app.otherElements["PopoverDismissRegion"].tap()
        }
        XCTAssertTrue(archive.isHittable)
    }

    func testEarningsScreensAndPayStatementNavigation() {
        let app = launch("earningsHistory")
        assertShiftActionAboveNavigation(app, label: "Start Shift")
        XCTAssertTrue(app.staticTexts["Last 7 days"].exists)
        capture(app, name: "Timecard Home")
        app.buttons["main.tab.history"].tap()
        XCTAssertTrue(app.staticTexts["Work history"].waitForExistence(timeout: 5))
        capture(app, name: "Timecard History")
        app.buttons["main.tab.summary"].tap()
        XCTAssertTrue(app.staticTexts["Weekly earnings"].waitForExistence(timeout: 5))
        capture(app, name: "Timecard Summary")
        let statements = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Pay statements'")).firstMatch
        for _ in 0..<4 {
            if statements.isHittable { break }
            app.swipeUp()
        }
        statements.tap()
        XCTAssertTrue(app.navigationBars["Pay Periods"].waitForExistence(timeout: 5))
        app.buttons["main.tab.settings"].tap()
        let job = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Studio'")).firstMatch
        XCTAssertTrue(job.waitForExistence(timeout: 5))
        capture(app, name: "Timecard Settings")
    }

    func testWorkweekCanBeReadAtAccessibilitySize() {
        let app = launch("earningsHistory", largeText: true)
        let today = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", Date.now.formatted(date: .complete, time: .omitted))).firstMatch
        for _ in 0..<7 {
            if today.isHittable && today.frame.maxY <= app.buttons["home.shiftAction"].frame.minY { break }
            app.swipeUp()
        }
        XCTAssertTrue(today.isHittable)
        XCTAssertTrue((today.value as? String)?.contains("hours worked") == true)
        assertShiftActionAboveNavigation(app, label: "Start Shift")
        capture(app, name: "Workweek at accessibility size")
    }

    func testPaycheckCanBeSetFromTwoAmountsAndReopened() {
        let app = launch("hourlyJobs")
        app.buttons["main.tab.settings"].tap()
        let jobRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Business System Support Analyst")).firstMatch
        XCTAssertTrue(jobRow.waitForExistence(timeout: 8))
        capture(app, name: "Simplified settings")
        jobRow.tap()
        let paycheck = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Take-home pay")).firstMatch
        XCTAssertTrue(paycheck.waitForExistence(timeout: 5))
        paycheck.tap()
        let save = app.buttons["Save paycheck settings"]
        XCTAssertFalse(save.isEnabled)
        let gross = app.textFields["paycheck.gross"]
        gross.tap()
        gross.typeText("500")
        let net = app.textFields["paycheck.net"]
        net.tap()
        net.typeText("405")
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(paycheck.waitForExistence(timeout: 5))
        XCTAssertTrue(paycheck.label.contains("81"))
        paycheck.tap()
        XCTAssertEqual(gross.value as? String, "500")
        XCTAssertEqual(net.value as? String, "405")
        capture(app, name: "Paycheck reference")
        app.buttons["Use automatic estimate"].tap()
        XCTAssertTrue(paycheck.waitForExistence(timeout: 5))
        XCTAssertTrue(paycheck.label.contains("Add paycheck"))
    }

    func testCustomOnboardingPayTypeAndFrequency() {
        let app = XCUIApplication()
        app.launchEnvironment["MONEY_TRACKER_UI_SCENARIO"] = "onboarding"
        app.launch()
        let salary = app.buttons["Salary"]
        XCTAssertTrue(salary.waitForExistence(timeout: 8))
        salary.tap()
        XCTAssertTrue(salary.isSelected)
        app.buttons["Pay frequency"].tap()
        app.buttons["Monthly"].tap()
        XCTAssertEqual(app.buttons["Pay frequency"].value as? String, "Monthly")
        app.buttons["Hourly"].tap()
        XCTAssertTrue(app.buttons["Hourly"].isSelected)
        XCTAssertTrue(app.textFields["Hourly rate in dollars"].exists)
    }

    func testCustomPayCyclePickerAndMonthNavigation() {
        let app = launch("earningsHistory")
        app.buttons["main.tab.settings"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Studio'")).firstMatch.tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Pay cycle'")).firstMatch.tap()
        let field = app.buttons["Pay frequency"]
        field.tap()
        let weekly = app.buttons["Weekly"]
        XCTAssertTrue(weekly.waitForExistence(timeout: 5))
        capture(app, name: "Pay frequency choices")
        weekly.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "Weekly")
        let anchor = app.buttons["A pay period began"]
        let originalAnchor = anchor.value as? String
        anchor.tap()
        XCTAssertTrue(app.buttons["Next month"].waitForExistence(timeout: 5))
        app.buttons["Next month"].tap()
        let month = app.buttons.matching(NSPredicate(format: "identifier == 'timecard.calendar.heading'")).firstMatch
        month.tap()
        month.tap()
        XCTAssertTrue(app.buttons["Previous ten years"].exists)
        app.buttons["Close"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "Weekly")
        XCTAssertEqual(anchor.value as? String, originalAnchor)
    }

    func testCustomHistoryMenuAndMinutePrecision() {
        let app = launch("hourlyJobs")
        app.buttons["main.tab.history"].tap()
        app.buttons["Add a completed or scheduled shift"].tap()
        app.buttons["Schedule future shift"].tap()
        let job = app.buttons["Job"]
        XCTAssertTrue(job.waitForExistence(timeout: 5))
        job.tap()
        app.buttons["Lululemon"].tap()
        let start = app.buttons["Start time"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        let minute = app.buttons["Minute"]
        XCTAssertTrue(minute.waitForExistence(timeout: 5))
        capture(app, name: "Shift time entry")
        minute.tap()
        app.buttons["0"].tap()
        app.buttons["7"].tap()
        XCTAssertEqual(minute.value as? String, "07")
        app.buttons["Use time"].tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        let savedTime = start.value as? String
        XCTAssertTrue(savedTime?.contains(":07") == true)
        start.tap()
        app.buttons["Minute"].tap()
        app.buttons["5"].tap()
        app.buttons["Close"].tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        XCTAssertEqual(start.value as? String, savedTime)
        XCTAssertEqual(job.value as? String, "Lululemon")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
        let filters = app.buttons["Filter history"]
        filters.tap()
        app.buttons["Lululemon"].tap()
        XCTAssertTrue(filters.waitForExistence(timeout: 5))
        XCTAssertEqual(filters.value as? String, "Lululemon, All")
    }

    func testCustomHomePickerAtLargeText() {
        let app = launch("hourlyJobs", largeText: true)
        app.buttons["Gross pay"].tap()
        let net = app.buttons["Estimated take-home"]
        XCTAssertTrue(net.waitForExistence(timeout: 5))
        net.tap()
        XCTAssertTrue(app.buttons["Est. take-home"].waitForExistence(timeout: 5))
    }

    func testShiftActionsKeepTapAndLongPressDistinct() {
        let app = launch("earningsHistory")
        app.buttons["main.tab.history"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Studio'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.navigationBars["Edit Shift"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        row.press(forDuration: 0.8)
        let duplicate = app.buttons["Duplicate shift"]
        XCTAssertTrue(duplicate.waitForExistence(timeout: 5))
        duplicate.tap()
        XCTAssertTrue(app.navigationBars["Log Shift"].waitForExistence(timeout: 5))
    }

    func testCustomCalendarRespectsPaydayBoundsAtLargeText() throws {
        let app = launch("salaryOnly", largeText: true)
        let payday = app.buttons["salary.nextPayday"]
        for _ in 0..<6 {
            if payday.isHittable { break }
            app.swipeUp()
        }
        payday.tap()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let due = try XCTUnwrap(calendar.date(byAdding: .day, value: 7, to: today))
        if !calendar.isDate(today, equalTo: due, toGranularity: .month) {
            app.buttons["Previous month"].tap()
        }
        let previous = app.buttons["Previous month"]
        XCTAssertFalse(previous.isEnabled)
        if calendar.component(.day, from: today) > 1 {
            let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
            let text = yesterday.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
            let disabledDay = app.buttons[text]
            XCTAssertTrue(disabledDay.exists)
            XCTAssertFalse(disabledDay.isEnabled)
        }
        XCTAssertFalse(app.buttons["Save"].isEnabled)
    }

    func testNextPaydayCanBeCorrectedDirectlyFromHome() throws {
        let app = launch("salaryOnly")
        let link = app.buttons["salary.nextPayday"]
        XCTAssertTrue(link.waitForExistence(timeout: 8))
        let previous = try XCTUnwrap(link.value as? String)
        link.tap()
        XCTAssertTrue(app.navigationBars["Official payday"].waitForExistence(timeout: 5))
        capture(app, name: "Official payday calendar")
        let save = app.buttons["Save"]
        XCTAssertFalse(save.isEnabled)

        // The fixture starts seven days ago in a biweekly cycle. Stay within the
        // displayed month so this interaction also works on month boundaries.
        let calendar = Calendar.current
        let original = try XCTUnwrap(calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: .now)))
        let month = try XCTUnwrap(calendar.range(of: .day, in: .month, for: original))
        let delta = calendar.component(.day, from: original) == month.lowerBound ? 1 : -1
        let corrected = try XCTUnwrap(calendar.date(byAdding: .day, value: delta, to: original))
        let dateLabel = corrected.formatted(.dateTime.weekday(.wide).month(.wide).day())
        let day = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", dateLabel)).firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 5), app.debugDescription)
        day.tap()
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        XCTAssertNotEqual(link.value as? String, previous)
        XCTAssertEqual(link.value as? String, corrected.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
    }

    func testSalaryHomeNeedsNoClockButtonAndKeepsNavigationReachable() {
        let app = launch("salaryOnly")
        XCTAssertTrue(app.staticTexts["Automatic salary tracking"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["home.shiftAction"].exists)
        for tab in ["home", "history", "summary", "settings"] {
            XCTAssertTrue(app.buttons["main.tab.\(tab)"].isHittable)
        }
        capture(app, name: "Salary Home bottom navigation")
    }

    func testHourlyActionStaysReachableWithAccessibilityText() {
        let app = launch("hourlyJobs", largeText: true)
        capture(app, name: "Hourly Home accessibility text")
        assertShiftActionAboveNavigation(app, label: "Start Shift")
    }

    func testNavigationReturnsAfterDismissingSearchKeyboard() {
        let app = launch("hourlyJobs")
        app.buttons["main.tab.history"].tap()
        app.swipeDown()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("example")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == NO"),
                                               object: app.buttons["main.tab.home"])
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed)
        let close = app.buttons["Close"]
        (close.exists ? close : app.buttons["Cancel"]).tap()
        XCTAssertTrue(app.buttons["main.tab.home"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["main.tab.home"].isHittable)
    }
}
