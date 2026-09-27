import XCTest
@testable import CoamingCore

final class CursorDecodingTests: XCTestCase {
    func testProUsesTotalPercent() throws {
        let parsed = try CursorUsageClient.parse(Fixtures.data("cursor_summary_pro"))
        XCTAssertEqual(parsed.planLabel, "Pro")
        XCTAssertEqual(parsed.windows.count, 1)
        XCTAssertEqual(parsed.windows[0].label, "Plan")
        XCTAssertEqual(parsed.windows[0].usedFraction, 0.301, accuracy: 0.0001)
        XCTAssertEqual(parsed.windows[0].resetsAt, DateParsing.parseISO8601("2026-10-03T00:00:00.000Z"))
    }

    func testOnDemandWindow() throws {
        let parsed = try CursorUsageClient.parse(Fixtures.data("cursor_summary_ondemand"))
        XCTAssertEqual(parsed.windows.map(\.kind), [.billingPlan, .billingOnDemand])
        XCTAssertEqual(parsed.windows[1].usedFraction, 0.10, accuracy: 0.0001)
        XCTAssertEqual(parsed.windows[1].label, "On-demand")
    }

    func testOnDemandWithoutLimitIsOmitted() throws {
        let parsed = try CursorUsageClient.parse(Fixtures.data("cursor_summary_ondemand_nolimit"))
        XCTAssertEqual(parsed.windows.map(\.kind), [.billingPlan])
    }

    func testUnlimited() throws {
        let parsed = try CursorUsageClient.parse(Fixtures.data("cursor_summary_unlimited"))
        XCTAssertEqual(parsed.windows.count, 1)
        XCTAssertEqual(parsed.windows[0].label, "∞")
        XCTAssertEqual(parsed.windows[0].usedFraction, 0)
    }

    func testFractionPercentIsNotScaledTwice() throws {
        let parsed = try CursorUsageClient.parse(Fixtures.data("cursor_summary_fraction_percent"))
        XCTAssertEqual(parsed.windows[0].usedFraction, 0.0036, accuracy: 0.0000001)
        XCTAssertNotEqual(parsed.windows[0].usedFraction, 0.36, accuracy: 0.0001)
    }

    func testTeamOverall() throws {
        let parsed = try CursorUsageClient.parse(Fixtures.data("cursor_summary_team_overall"))
        XCTAssertEqual(parsed.windows[0].label, "Plan")
        XCTAssertEqual(parsed.windows[0].usedFraction, 0.7384, accuracy: 0.0001)
        XCTAssertEqual(parsed.planLabel, "Enterprise")
    }

    func testTeamPooled() throws {
        let parsed = try CursorUsageClient.parse(Fixtures.data("cursor_summary_team_pooled"))
        XCTAssertEqual(parsed.windows[0].label, "Team")
        XCTAssertEqual(parsed.windows[0].usedFraction, 0.1, accuracy: 0.0001)
    }

    func testEmptyUsage() throws {
        XCTAssertThrowsError(try CursorUsageClient.parse(Fixtures.data("cursor_summary_empty"))) { error in
            guard case UsageFetchError.semantic(let reason) = error else {
                return XCTFail("unexpected \(error)")
            }
            XCTAssertEqual(reason, "empty usage")
        }
    }

    func testLegacyPlan() throws {
        let json = #"{"limitType":"requests","individualUsage":{"plan":null}}"#
        XCTAssertThrowsError(try CursorUsageClient.parse(Data(json.utf8))) { error in
            guard case UsageFetchError.semantic(let reason) = error else {
                return XCTFail("unexpected \(error)")
            }
            XCTAssertEqual(reason, "legacy plan")
        }
    }

    func testBadSubjectIsRejected() throws {
        let object = try Fixtures.json("cursor_jwt_bad_sub")
        let token = try XCTUnwrap(object["token"] as? String)
        XCTAssertNil(CursorIdentity.userID(from: token))
    }

    func testCookieEncodesSeparator() throws {
        let token = try makeJWT(payload: ["sub": "auth0|user_abc", "exp": 2_000_000_000])
        let userID = try XCTUnwrap(CursorIdentity.userID(from: token))
        XCTAssertEqual(userID, "user_abc")
        let cookie = CursorIdentity.cookie(userID: userID, accessToken: token)
        XCTAssertEqual(cookie, "WorkosCursorSessionToken=user_abc%3A%3A\(token)")
        XCTAssertFalse(cookie.contains("::"))
    }
}
