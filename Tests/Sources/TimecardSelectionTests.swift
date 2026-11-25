#if canImport(UIKit) && !SWIFT_PACKAGE
import Foundation
import XCTest
@testable import BigBeautifulMoneyTracker

final class TimecardSelectionTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Denver")!
        return calendar
    }

    private func date(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    func testExactMinutesNoonMidnightAndRangeLimits() {
        let original = date(11, 25, 9, 37)
        func time(_ h: String, _ m: String, pm: Bool, twelve: Bool = true, maximum: Date? = nil) -> Date? {
            TimecardMoment.time(hour: h, minute: m, twelveHour: twelve, afternoon: pm,
                                on: original, calendar: calendar, minimum: nil, maximum: maximum)
        }
        XCTAssertEqual(time("12", "07", pm: false), date(11, 25, 0, 7))
        XCTAssertEqual(time("12", "07", pm: true), date(11, 25, 12, 7))
        XCTAssertEqual(time("23", "59", pm: false, twelve: false), date(11, 25, 23, 59))
        XCTAssertNil(time("00", "07", pm: false))
        XCTAssertNil(time("24", "00", pm: false, twelve: false))
        XCTAssertNil(time("9", "60", pm: false))
        XCTAssertNil(time("", "00", pm: false))
        XCTAssertNil(time("10", "00", pm: false, maximum: original))
    }

    func testSkippedAndRepeatedLocalHours() throws {
        XCTAssertEqual(TimecardMoment.moving(date(3, 7, 2, 7), toDay: date(3, 8, 0, 0), calendar: calendar,
                                             minimum: nil, maximum: nil), date(3, 8, 3, 7))
        let spring = date(3, 8, 1, 30)
        XCTAssertNil(TimecardMoment.time(hour: "2", minute: "30", twelveHour: true, afternoon: false,
                                         on: spring, calendar: calendar, minimum: nil, maximum: nil))
        let autumn = date(11, 1, 12, 0)
        let second = try XCTUnwrap(calendar.date(bySettingHour: 1, minute: 30, second: 0, of: autumn,
                                                  matchingPolicy: .strict, repeatedTimePolicy: .last))
        let adjusted = TimecardMoment.time(hour: "1", minute: "31", twelveHour: true, afternoon: false,
                                           on: second, calendar: calendar, minimum: nil, maximum: nil)
        XCTAssertEqual(adjusted, second.addingTimeInterval(60))
    }

    func testMovingADayPreservesTimeAndClampsPartialBoundaryDays() {
        let original = date(11, 25, 16, 13)
        XCTAssertEqual(TimecardMoment.moving(original, toDay: date(11, 27, 0, 0), calendar: calendar, minimum: nil, maximum: nil),
                       date(11, 27, 16, 13))
        let end = date(11, 27, 12, 0)
        XCTAssertEqual(TimecardMoment.moving(original, toDay: end, calendar: calendar, minimum: nil, maximum: end), end)
    }
}
#endif
