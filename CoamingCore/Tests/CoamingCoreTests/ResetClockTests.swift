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

    func testRemainingIsHoursOrDays() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let ja = Locale(identifier: "ja_JP")
        let en = Locale(identifier: "en_US")
        XCTAssertEqual(formatResetRemaining(now.addingTimeInterval(30), now: now, locale: ja), "あと1分")
        XCTAssertEqual(formatResetRemaining(now.addingTimeInterval(30), now: now, locale: en), "1 min left")
        XCTAssertEqual(formatResetRemaining(now.addingTimeInterval(40 * 60), now: now, locale: ja), "あと40分")
        XCTAssertEqual(formatResetRemaining(now.addingTimeInterval(40 * 60), now: now, locale: en), "40 min left")
        XCTAssertEqual(formatResetRemaining(now.addingTimeInterval(3 * 3600 + 40 * 60), now: now, locale: ja), "あと3時間")
        XCTAssertEqual(formatResetRemaining(now.addingTimeInterval(3 * 3600 + 40 * 60), now: now, locale: en), "3 hours left")
        XCTAssertEqual(formatResetRemaining(now.addingTimeInterval(3600), now: now, locale: ja), "あと1時間")
        XCTAssertEqual(formatResetRemaining(now.addingTimeInterval(3600), now: now, locale: en), "1 hour left")
        XCTAssertEqual(formatResetRemaining(now.addingTimeInterval(5 * 86_400 + 3 * 3600), now: now, locale: ja), "あと5日")
        XCTAssertEqual(formatResetRemaining(now.addingTimeInterval(5 * 86_400 + 3 * 3600), now: now, locale: en), "5 days left")
        XCTAssertEqual(formatResetRemaining(now.addingTimeInterval(86_400), now: now, locale: ja), "あと1日")
        XCTAssertEqual(formatResetRemaining(now.addingTimeInterval(86_400), now: now, locale: en), "1 day left")
        XCTAssertEqual(formatResetRemaining(now.addingTimeInterval(-1), now: now, locale: ja), "")
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
