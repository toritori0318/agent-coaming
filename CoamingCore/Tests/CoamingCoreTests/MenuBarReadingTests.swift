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
        XCTAssertEqual(MenuBarReading.title(snapshot: snapshot, enabled: [.claude, .codex]), "40% | W35%")
    }

    func testOmitsAMissingWindow() {
        let fiveOnly = Snapshot(
            schemaVersion: Snapshot.currentSchemaVersion,
            generatedAt: Date(),
            providers: [provider(.claude, status: .ok, windows: [window(.fiveHour, 0.10)])]
        )
        XCTAssertEqual(MenuBarReading.title(snapshot: fiveOnly, enabled: [.claude]), "10%")

        let weekOnly = Snapshot(
            schemaVersion: Snapshot.currentSchemaVersion,
            generatedAt: Date(),
            providers: [provider(.claude, status: .ok, windows: [window(.weekly, 0.35)])]
        )
        XCTAssertEqual(MenuBarReading.title(snapshot: weekOnly, enabled: [.claude]), "W35%")
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
        XCTAssertEqual(MenuBarReading.title(snapshot: snapshot, enabled: [.claude, .codex]), "20%")
        XCTAssertEqual(MenuBarReading.title(snapshot: snapshot, enabled: [.claude]), "—")
        XCTAssertEqual(MenuBarReading.title(snapshot: snapshot, enabled: []), "—")
    }

    private func provider(_ id: ProviderID, status: ProviderStatus, windows: [UsageWindow]) -> ProviderSnapshot {
        .make(id, status: status, windows: windows, fetchedAt: Date())
    }

    private func window(_ kind: WindowKind, _ fraction: Double, label: String? = nil) -> UsageWindow {
        let text = label ?? (kind == .weekly ? "Weekly" : "5h")
        return UsageWindow(kind: kind, label: text, usedFraction: fraction, resetsAt: nil)
    }
}
