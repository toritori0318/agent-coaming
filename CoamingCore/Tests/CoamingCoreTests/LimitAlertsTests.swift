import XCTest
@testable import CoamingCore

final class LimitAlertsTests: XCTestCase {
    func testNotifiesWhenUsageReachesTheRedThreshold() {
        let over = snapshot(claude: 0.90, status: .ok)
        let first = LimitAlerts.evaluate(snapshot: over, enabled: [.claude], alreadyNotified: [])
        XCTAssertEqual(first.crossings.map(\.key), ["claude.fiveHour"])
        XCTAssertEqual(first.crossings.first?.windowName, "5h")
        XCTAssertEqual(first.crossings.first?.percentText, "90%")
        XCTAssertEqual(first.active, ["claude.fiveHour"])

        let again = LimitAlerts.evaluate(snapshot: over, enabled: [.claude], alreadyNotified: first.active)
        XCTAssertTrue(again.crossings.isEmpty)
        XCTAssertEqual(again.active, ["claude.fiveHour"])
    }

    func testNotifiesAgainAfterUsageFallsBelowTheThreshold() {
        let under = snapshot(claude: 0.50, status: .ok)
        let cleared = LimitAlerts.evaluate(snapshot: under, enabled: [.claude], alreadyNotified: ["claude.fiveHour"])
        XCTAssertTrue(cleared.active.isEmpty)

        let over = snapshot(claude: 0.91, status: .ok)
        let next = LimitAlerts.evaluate(snapshot: over, enabled: [.claude], alreadyNotified: cleared.active)
        XCTAssertEqual(next.crossings.map(\.percentText), ["91%"])
    }

    func testSkipsStaleDisabledAndNonQuotaWindows() {
        let snapshot = Snapshot(
            schemaVersion: Snapshot.currentSchemaVersion,
            generatedAt: Date(),
            providers: [
                provider(.claude, status: .stale, windows: [window(.fiveHour, 0.95)]),
                provider(.codex, status: .ok, windows: [
                    window(.fiveHour, 0.99),
                    window(.weeklyModel, 0.99),
                ]),
            ]
        )
        let result = LimitAlerts.evaluate(snapshot: snapshot, enabled: [.claude], alreadyNotified: [])
        XCTAssertTrue(result.crossings.isEmpty)

        let codex = LimitAlerts.evaluate(snapshot: snapshot, enabled: [.codex], alreadyNotified: [])
        XCTAssertEqual(codex.crossings.map(\.key), ["codex.fiveHour"])
    }

    func testDoesNotRepeatAfterAStaleReadingWhileStillOver() {
        let stale = LimitAlerts.evaluate(snapshot: snapshot(claude: 0.95, status: .stale), enabled: [.claude], alreadyNotified: ["claude.fiveHour"])
        XCTAssertEqual(stale.active, ["claude.fiveHour"])

        let back = LimitAlerts.evaluate(snapshot: snapshot(claude: 0.95, status: .ok), enabled: [.claude], alreadyNotified: stale.active)
        XCTAssertTrue(back.crossings.isEmpty)
    }

    func testDoesNotRepeatAfterTheServiceIsReenabledWhileStillOver() {
        let over = snapshot(claude: 0.95, status: .ok)
        let disabled = LimitAlerts.evaluate(snapshot: over, enabled: [], alreadyNotified: ["claude.fiveHour"])
        XCTAssertEqual(disabled.active, ["claude.fiveHour"])

        let enabled = LimitAlerts.evaluate(snapshot: over, enabled: [.claude], alreadyNotified: disabled.active)
        XCTAssertTrue(enabled.crossings.isEmpty)
    }

    private func snapshot(claude fraction: Double, status: ProviderStatus) -> Snapshot {
        Snapshot(
            schemaVersion: Snapshot.currentSchemaVersion,
            generatedAt: Date(),
            providers: [provider(.claude, status: status, windows: [window(.fiveHour, fraction)])]
        )
    }

    private func provider(_ id: ProviderID, status: ProviderStatus, windows: [UsageWindow]) -> ProviderSnapshot {
        .make(id, status: status, windows: windows, fetchedAt: Date())
    }

    private func window(_ kind: WindowKind, _ fraction: Double, label: String? = nil) -> UsageWindow {
        let text = label ?? (kind == .weekly ? "Weekly" : "5h")
        return UsageWindow(kind: kind, label: text, usedFraction: fraction, resetsAt: nil)
    }
}
