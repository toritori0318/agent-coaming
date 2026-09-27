import XCTest
@testable import CoamingCore

final class CodexDecodingTests: XCTestCase {
    func testPrimaryWindowCanBeWeekly() throws {
        let fetched = Date(timeIntervalSince1970: 1_700_000_000)
        let parsed = try CodexUsageClient.parse(Fixtures.data("codex_usage_primary_weekly"), fetchedAt: fetched)
        XCTAssertEqual(parsed.planLabel, "Codex plus")
        XCTAssertEqual(parsed.windows.map(\.kind), [.fiveHour, .weekly])
        XCTAssertEqual(parsed.windows[0].usedFraction, 0.04, accuracy: 0.0001)
        XCTAssertEqual(parsed.windows[1].usedFraction, 0.19, accuracy: 0.0001)
        XCTAssertEqual(parsed.windows[0].resetsAt, fetched.addingTimeInterval(4140))
        XCTAssertEqual(parsed.windows[1].resetsAt, fetched.addingTimeInterval(546240))
    }

    func testSingleWindow() throws {
        let fetched = Date(timeIntervalSince1970: 1_700_000_000)
        let parsed = try CodexUsageClient.parse(Fixtures.data("codex_usage_single_window"), fetchedAt: fetched)
        XCTAssertEqual(parsed.windows.count, 1)
        XCTAssertEqual(parsed.windows[0].kind, .fiveHour)
        XCTAssertEqual(parsed.windows[0].usedFraction, 0.04, accuracy: 0.0001)
        XCTAssertEqual(parsed.planLabel, "Codex pro")
    }

    func testResetAtFallback() throws {
        let json = #"{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":8,"limit_window_seconds":18000,"reset_at":1759000000}}}"#
        let parsed = try CodexUsageClient.parse(Data(json.utf8), fetchedAt: Date(timeIntervalSince1970: 10))
        XCTAssertEqual(parsed.windows[0].resetsAt, Date(timeIntervalSince1970: 1_759_000_000))
    }
}
