import XCTest
@testable import CoamingCore

final class SnapshotRedactionTests: XCTestCase {
    func testSnapshotOmitsSentinel() async throws {
        let sentinel = "TOKEN_SENTINEL_9f3a"
        let accountSentinel = "ACCOUNT_SENTINEL_7c1d"
        let http = MockHTTP()
        http.bodies["chatgpt.com"] = Data(#"{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":4,"limit_window_seconds":18000,"reset_after_seconds":10}}}"#.utf8)
        http.bodies["cursor.com"] = Data(#"{"membershipType":"pro","isUnlimited":false,"individualUsage":{"plan":{"totalPercentUsed":30}}}"#.utf8)
        let cursorToken = try cursorToken(sentinel)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let claude = ClaudeProvider(read: {
            .found(ClaudeRateLimits(
                windows: [UsageWindow(kind: .fiveHour, label: "5h", usedFraction: 0.54, resetsAt: now.addingTimeInterval(3600))],
                writtenAt: now
            ))
        })
        let codex = CodexProvider(userAgent: "AgentCoaming/1 (macOS)", http: http, read: {
            .found(CodexCredential(accessToken: sentinel, accountID: accountSentinel, expiresAt: nil))
        })
        let cursor = CursorProvider(
            userAgent: "AgentCoaming/1 (macOS)",
            http: http,
            supportDirectoryURL: URL(fileURLWithPath: "/tmp"),
            read: {
                .found(CursorCredential(accessToken: cursorToken, expiresAt: nil, membershipType: "pro"))
            }
        )
        let refresher = Refresher(providers: [claude, codex, cursor], previous: nil, backoff: MemoryBackoffStore())
        let snapshot = await refresher.refresh(at: now, force: true)
        let directory = try temporaryDirectory()
        let store = SnapshotStore(fileURL: directory.appendingPathComponent("snapshot.json"))
        try store.write(snapshot)
        let bytes = try Data(contentsOf: try XCTUnwrap(store.fileURL))
        XCTAssertNil(bytes.range(of: Data(sentinel.utf8)))
        XCTAssertNil(bytes.range(of: Data(accountSentinel.utf8)))
        XCTAssertEqual(snapshot.providers.count, 3)
        XCTAssertEqual(snapshot.provider(.claude)?.status, .ok)
        XCTAssertEqual(snapshot.provider(.codex)?.status, .ok)
        XCTAssertEqual(snapshot.provider(.cursor)?.status, .ok)
    }

    func testCredentialDescriptionsAreRedacted() {
        let sentinel = "TOKEN_SENTINEL_9f3a"
        let codex = CodexCredential(accessToken: sentinel, accountID: sentinel, expiresAt: nil)
        let cursor = CursorCredential(accessToken: sentinel, expiresAt: nil, membershipType: nil)
        for value in [codex.description, codex.debugDescription, String(reflecting: codex), String(describing: codex)] {
            XCTAssertFalse(value.contains(sentinel))
            XCTAssertEqual(value, "<redacted>")
        }
        XCTAssertFalse(String(reflecting: cursor).contains(sentinel))
        XCTAssertEqual(cursor.debugDescription, "<redacted>")
    }

    func testDuplicateProviderIDsAreRejected() throws {
        let row = ProviderSnapshot.make(.claude, status: .ok)
        let duplicated = Snapshot(schemaVersion: Snapshot.currentSchemaVersion, generatedAt: Date(), providers: [row, row])
        XCTAssertNil(Snapshot.decode(try duplicated.encode()))
        let single = Snapshot(schemaVersion: Snapshot.currentSchemaVersion, generatedAt: Date(), providers: [row])
        XCTAssertNotNil(Snapshot.decode(try single.encode()))
    }

    private func cursorToken(_ sentinel: String) throws -> String {
        let payload: [String: Any] = ["sub": "auth0|user_abc", "exp": 2_000_000_000]
        let token = try makeJWT(payload: payload)
        return token.replacingOccurrences(of: ".sig", with: ".\(sentinel)")
    }
}

final class WidgetLayoutTests: XCTestCase {
    func testLowWeeklyModelDropsBeforeOnDemand() {
        let rows = WidgetLayout.medium(snapshot: sample(opus: 0.1), now: Date())
        XCTAssertEqual(rows.count, 6)
        XCTAssertTrue(rows.contains { $0.windowLabel == "On-demand" })
        XCTAssertFalse(rows.contains { $0.windowLabel == "Opus" })
    }

    func testHighWeeklyModelKeepsAndDropsOnDemand() {
        let rows = WidgetLayout.medium(snapshot: sample(opus: 0.8), now: Date())
        XCTAssertEqual(rows.count, 6)
        XCTAssertFalse(rows.contains { $0.windowLabel == "On-demand" })
        XCTAssertTrue(rows.contains { $0.windowLabel == "Opus" })
    }

    func testLowWeeklyModelStaysWhenRowsFit() {
        let rows = WidgetLayout.medium(snapshot: sample(opus: 0.1, cursorOnDemand: false), now: Date())
        XCTAssertEqual(rows.count, 6)
        XCTAssertTrue(rows.contains { $0.windowLabel == "Opus" })
    }

    func testOldOkValueIsDimmedWithAge() {
        let now = Date()
        var snapshot = sample(opus: 0.8)
        snapshot.providers[0].fetchedAt = now.addingTimeInterval(-5 * 3600)
        let small = WidgetLayout.small(snapshot: snapshot, now: now)
        XCTAssertTrue(small.rows[0].dimmed)
        XCTAssertEqual(small.rows[0].age, "5h ago")
        XCTAssertFalse(small.rows[1].dimmed)
        let medium = WidgetLayout.medium(snapshot: snapshot, now: now)
        XCTAssertTrue(medium.first { $0.name == "Claude" }!.dimmed)
        XCTAssertEqual(medium.first { $0.name == "Claude" }!.age, "5h ago")
    }

    func testDesktopCadenceIsNotDimmed() {
        let now = Date()
        var snapshot = sample(opus: 0.8)
        snapshot.providers[0].fetchedAt = now.addingTimeInterval(-16 * 60)
        XCTAssertFalse(WidgetLayout.small(snapshot: snapshot, now: now).rows[0].dimmed)
    }

    func testColorThresholdsFollowOfficialWeeklyWarning() {
        XCTAssertFalse(usageIsWarning(0.74))
        XCTAssertTrue(usageIsWarning(0.75))
        XCTAssertTrue(usageIsWarning(0.89))
        XCTAssertFalse(usageIsWarning(0.90))
        XCTAssertTrue(usageIsCritical(0.90))
    }

    func testAllMissingShowsEmptyCopy() {
        let snapshot = Snapshot(
            schemaVersion: 1,
            generatedAt: Date(),
            providers: ProviderID.allCases.map { .make($0, status: .notInstalled) }
        )
        let small = WidgetLayout.small(snapshot: snapshot, now: Date())
        XCTAssertEqual(small.emptyMessage, WidgetLayout.emptyMessage)
        XCTAssertTrue(WidgetLayout.medium(snapshot: snapshot, now: Date()).isEmpty)
    }

    private func sample(opus: Double, cursorOnDemand: Bool = true) -> Snapshot {
        func window(_ kind: WindowKind, _ label: String, _ fraction: Double) -> UsageWindow {
            UsageWindow(kind: kind, label: label, usedFraction: fraction, resetsAt: nil)
        }
        let now = Date()
        var cursorWindows = [window(.billingPlan, "Plan", 0.3)]
        if cursorOnDemand { cursorWindows.append(window(.billingOnDemand, "On-demand", 0.1)) }
        return Snapshot(
            schemaVersion: 1,
            generatedAt: now,
            providers: [
                .make(.claude, status: .ok, plan: "Max 5x", windows: [
                    window(.fiveHour, "5h", 0.5),
                    window(.weekly, "Weekly", 0.3),
                    window(.weeklyModel, "Opus", opus),
                ], fetchedAt: now),
                .make(.codex, status: .ok, plan: "Codex plus", windows: [
                    window(.fiveHour, "5h", 0.1),
                    window(.weekly, "Weekly", 0.2),
                ], fetchedAt: now),
                .make(.cursor, status: .ok, plan: "Pro", windows: cursorWindows, fetchedAt: now),
            ]
        )
    }
}
