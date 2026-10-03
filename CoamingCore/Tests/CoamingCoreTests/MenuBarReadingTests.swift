import XCTest
@testable import CoamingCore

final class MenuBarReadingTests: XCTestCase {
    func testHighestFiveHourAndWeekly() {
        let snapshot = Snapshot(
            schemaVersion: Snapshot.currentSchemaVersion,
            generatedAt: Date(),
            providers: [
                provider(.claude, status: .ok, windows: [window(.fiveHour, 0.10), window(.weekly, 0.35)]),
                provider(.codex, status: .ok, windows: [window(.fiveHour, 0.40), window(.weekly, 0.20)]),
            ]
        )
        XCTAssertEqual(MenuBarReading.title(snapshot: snapshot, enabled: [.claude, .codex]), "5h 40% 1w 35%")
    }

    func testOmitsAMissingWindow() {
        let fiveOnly = Snapshot(
            schemaVersion: Snapshot.currentSchemaVersion,
            generatedAt: Date(),
            providers: [provider(.claude, status: .ok, windows: [window(.fiveHour, 0.10)])]
        )
        XCTAssertEqual(MenuBarReading.title(snapshot: fiveOnly, enabled: [.claude]), "5h 10%")

        let weekOnly = Snapshot(
            schemaVersion: Snapshot.currentSchemaVersion,
            generatedAt: Date(),
            providers: [provider(.claude, status: .ok, windows: [window(.weekly, 0.35)])]
        )
        XCTAssertEqual(MenuBarReading.title(snapshot: weekOnly, enabled: [.claude]), "1w 35%")
    }

    func testEmptyAndIgnoredProviders() {
        let snapshot = Snapshot(
            schemaVersion: Snapshot.currentSchemaVersion,
            generatedAt: Date(),
            providers: [
                provider(.claude, status: .notInstalled, windows: [window(.fiveHour, 0.9)]),
                provider(.codex, status: .ok, windows: [window(.fiveHour, 0.2), window(.weekly, 0.5, label: "∞")]),
            ]
        )
        XCTAssertEqual(MenuBarReading.title(snapshot: snapshot, enabled: [.claude, .codex]), "5h 20%")
        XCTAssertEqual(MenuBarReading.title(snapshot: snapshot, enabled: [.claude]), "—")
        XCTAssertEqual(MenuBarReading.title(snapshot: snapshot, enabled: []), "—")
    }

    func testDimsWhenAReadingIsAPreviousValue() {
        let snapshot = Snapshot(
            schemaVersion: Snapshot.currentSchemaVersion,
            generatedAt: Date(),
            providers: [
                provider(.claude, status: .stale, windows: [window(.fiveHour, 0.10)]),
                provider(.codex, status: .ok, windows: [window(.fiveHour, 0.40)]),
            ]
        )
        XCTAssertTrue(MenuBarReading.isDimmed(snapshot: snapshot, enabled: [.claude, .codex], now: Date()))
    }

    func testDimsAnOldOkReading() {
        let old = Date().addingTimeInterval(-Constants.staleAfter - 60)
        let snapshot = Snapshot(
            schemaVersion: Snapshot.currentSchemaVersion,
            generatedAt: Date(),
            providers: [provider(.claude, status: .ok, windows: [window(.weekly, 0.35)], fetchedAt: old)]
        )
        XCTAssertTrue(MenuBarReading.isDimmed(snapshot: snapshot, enabled: [.claude], now: Date()))
    }

    func testDoesNotDimForFreshOrIgnoredProviders() {
        let snapshot = Snapshot(
            schemaVersion: Snapshot.currentSchemaVersion,
            generatedAt: Date(),
            providers: [
                provider(.claude, status: .stale, windows: [window(.fiveHour, 0.10)]),
                provider(.codex, status: .ok, windows: [window(.fiveHour, 0.40)]),
            ]
        )
        XCTAssertFalse(MenuBarReading.isDimmed(snapshot: snapshot, enabled: [.codex], now: Date()))
        XCTAssertFalse(MenuBarReading.isDimmed(snapshot: snapshot, enabled: [], now: Date()))
    }

    private func provider(_ id: ProviderID, status: ProviderStatus, windows: [UsageWindow], fetchedAt: Date = Date()) -> ProviderSnapshot {
        .make(id, status: status, windows: windows, fetchedAt: fetchedAt)
    }

    private func window(_ kind: WindowKind, _ fraction: Double, label: String? = nil) -> UsageWindow {
        let text = label ?? (kind == .weekly ? "Weekly" : "5h")
        return UsageWindow(kind: kind, label: text, usedFraction: fraction, resetsAt: nil)
    }
}
