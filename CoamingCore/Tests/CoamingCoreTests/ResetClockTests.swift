import XCTest
@testable import CoamingCore

final class ResetClockTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
        return calendar
    }

    func testSameDayIsTimeOnly() {
        let now = date(year: 2026, month: 9, day: 27, hour: 15, minute: 24)
        let reset = date(year: 2026, month: 9, day: 27, hour: 21, minute: 30)
        XCTAssertEqual(formatResetClock(reset, now: now, locale: Locale(identifier: "ja_JP"), calendar: calendar), "21:30")
        XCTAssertEqual(formatResetClock(reset, now: now, locale: Locale(identifier: "en_US"), calendar: calendar), "9:30 PM")
    }

    func testLaterDayIncludesMonthAndDay() {
        let now = date(year: 2026, month: 9, day: 27, hour: 15, minute: 24)
        let reset = date(year: 2026, month: 10, day: 3, hour: 9, minute: 5)
        XCTAssertEqual(formatResetClock(reset, now: now, locale: Locale(identifier: "ja_JP"), calendar: calendar), "10/3 9:05")
        XCTAssertEqual(formatResetClock(reset, now: now, locale: Locale(identifier: "en_US"), calendar: calendar), "10/3 9:05 AM")
    }

    private func date(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
