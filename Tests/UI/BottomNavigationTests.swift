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
