import XCTest
@testable import CoamingCore

final class LimitAlertsTests: XCTestCase {
    private let both = Set([LimitAlerts.orange, LimitAlerts.red])
    private let fiveHour: Set<WindowKind> = [.fiveHour]

    func testJumpPastBothLinesNotifiesEachOnce() {
        let over = snapshot(claude: 0.95, status: .ok)
        let first = LimitAlerts.evaluate(
            snapshot: over, enabled: [.claude], alreadyNotified: [], notifyLevels: both, notifyKinds: fiveHour
        )
        XCTAssertEqual(first.crossings.map(\.key), ["claude.fiveHour.75", "claude.fiveHour.90"])
        XCTAssertEqual(first.crossings.map(\.thresholdText), ["75%", "90%"])
        XCTAssertEqual(first.active, ["claude.fiveHour.75", "claude.fiveHour.90"])

        let again = LimitAlerts.evaluate(
            snapshot: over, enabled: [.claude], alreadyNotified: first.active, notifyLevels: both, notifyKinds: fiveHour
        )
        XCTAssertTrue(again.crossings.isEmpty)
    }

    func testCrossing90FromBetweenTheLinesNotifiesOnly90() {
        let over = snapshot(claude: 0.91, status: .ok)
        let next = LimitAlerts.evaluate(
            snapshot: over,
            enabled: [.claude],
            alreadyNotified: ["claude.fiveHour.75"],
            notifyLevels: both,
            notifyKinds: fiveHour
        )
        XCTAssertEqual(next.crossings.map(\.key), ["claude.fiveHour.90"])
        XCTAssertEqual(next.active, ["claude.fiveHour.75", "claude.fiveHour.90"])
    }

    func testFallingBetweenTheLinesRearmsOnly90() {
        let between = snapshot(claude: 0.80, status: .ok)
        let dropped = LimitAlerts.evaluate(
            snapshot: between,
            enabled: [.claude],
            alreadyNotified: ["claude.fiveHour.75", "claude.fiveHour.90"],
            notifyLevels: both,
            notifyKinds: fiveHour
        )
        XCTAssertEqual(dropped.crossings.map(\.key), [])
        XCTAssertEqual(dropped.active, ["claude.fiveHour.75"])

        let again = LimitAlerts.evaluate(
            snapshot: snapshot(claude: 0.95, status: .ok),
            enabled: [.claude],
            alreadyNotified: dropped.active,
            notifyLevels: both,
            notifyKinds: fiveHour
        )
        XCTAssertEqual(again.crossings.map(\.key), ["claude.fiveHour.90"])
    }

    func testFallingBelow75RearmsThatLine() {
        let under = snapshot(claude: 0.10, status: .ok)
        let cleared = LimitAlerts.evaluate(
            snapshot: under,
            enabled: [.claude],
            alreadyNotified: ["claude.fiveHour.75", "claude.fiveHour.90"],
            notifyLevels: both,
            notifyKinds: fiveHour
        )
        XCTAssertTrue(cleared.active.isEmpty)

        let next = LimitAlerts.evaluate(
            snapshot: snapshot(claude: 0.80, status: .ok),
            enabled: [.claude],
            alreadyNotified: cleared.active,
            notifyLevels: both,
            notifyKinds: fiveHour
        )
        XCTAssertEqual(next.crossings.map(\.key), ["claude.fiveHour.75"])
    }

    func testATurnedOffLineStaysTrackedWithoutNotifying() {
        let over = snapshot(claude: 0.95, status: .ok)
        let quiet = LimitAlerts.evaluate(
            snapshot: over, enabled: [.claude], alreadyNotified: [], notifyLevels: [LimitAlerts.red], notifyKinds: fiveHour
        )
        XCTAssertEqual(quiet.crossings.map(\.key), ["claude.fiveHour.90"])
        XCTAssertEqual(quiet.active, ["claude.fiveHour.75", "claude.fiveHour.90"])

        let enabled = LimitAlerts.evaluate(
            snapshot: over, enabled: [.claude], alreadyNotified: quiet.active, notifyLevels: both, notifyKinds: fiveHour
        )
        XCTAssertTrue(enabled.crossings.isEmpty)
    }

    func testATurnedOffWindowStaysTrackedWithoutNotifying() {
        let over = snapshot(claude: 0.95, status: .ok)
        let quiet = LimitAlerts.evaluate(
            snapshot: over, enabled: [.claude], alreadyNotified: [], notifyLevels: both, notifyKinds: []
        )
        XCTAssertTrue(quiet.crossings.isEmpty)
        XCTAssertEqual(quiet.active, ["claude.fiveHour.75", "claude.fiveHour.90"])
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
        let hidden = LimitAlerts.evaluate(
            snapshot: snapshot, enabled: [.claude], alreadyNotified: [], notifyLevels: both, notifyKinds: fiveHour
        )
        XCTAssertTrue(hidden.crossings.isEmpty)

        let codex = LimitAlerts.evaluate(
            snapshot: snapshot, enabled: [.codex], alreadyNotified: [], notifyLevels: both, notifyKinds: fiveHour
        )
        XCTAssertEqual(codex.crossings.map(\.key), ["codex.fiveHour.75", "codex.fiveHour.90"])
    }

    func testDoesNotRepeatAfterAStaleReadingWhileStillOver() {
        let latched: Set<String> = ["claude.fiveHour.75", "claude.fiveHour.90"]
        let stale = LimitAlerts.evaluate(
            snapshot: snapshot(claude: 0.95, status: .stale),
            enabled: [.claude],
            alreadyNotified: latched,
            notifyLevels: both,
            notifyKinds: fiveHour
        )
        XCTAssertEqual(stale.active, latched)

        let back = LimitAlerts.evaluate(
            snapshot: snapshot(claude: 0.95, status: .ok),
            enabled: [.claude],
            alreadyNotified: stale.active,
            notifyLevels: both,
            notifyKinds: fiveHour
        )
        XCTAssertTrue(back.crossings.isEmpty)
    }

    func testLegacy90KeyAlsoLatches75() {
        XCTAssertEqual(
            LimitAlerts.migrate(["claude.fiveHour"]),
            ["claude.fiveHour.75", "claude.fiveHour.90"]
        )
        XCTAssertEqual(
            LimitAlerts.migrate(["claude.fiveHour.90"]),
            ["claude.fiveHour.90"]
        )
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
