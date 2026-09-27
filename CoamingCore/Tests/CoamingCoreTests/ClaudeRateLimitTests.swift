import XCTest
@testable import CoamingCore

final class ClaudeRateLimitTests: XCTestCase {
    func testParseBothWindows() throws {
        let json = #"""
        {"written_at": 1738425000,
         "rate_limits": {
           "five_hour": {"used_percentage": 23.5, "resets_at": 1738425600},
           "seven_day": {"used_percentage": 41, "resets_at": 1738857600}}}
        """#
        let limits = try ClaudeRateLimitReader.parse(Data(json.utf8))
        XCTAssertEqual(limits.writtenAt, Date(timeIntervalSince1970: 1_738_425_000))
        XCTAssertEqual(limits.windows.map(\.kind), [.fiveHour, .weekly])
        XCTAssertEqual(limits.windows.map(\.label), ["5h", "Weekly"])
        XCTAssertEqual(limits.windows[0].usedFraction, 0.235, accuracy: 0.0001)
        XCTAssertEqual(limits.windows[0].resetsAt, Date(timeIntervalSince1970: 1_738_425_600))
        XCTAssertEqual(limits.windows[1].usedFraction, 0.41, accuracy: 0.0001)
        XCTAssertEqual(limits.windows[1].resetsAt, Date(timeIntervalSince1970: 1_738_857_600))
    }

    func testParseWeeklyOnly() throws {
        let json = #"{"written_at": 1, "rate_limits": {"seven_day": {"used_percentage": 5}}}"#
        let limits = try ClaudeRateLimitReader.parse(Data(json.utf8))
        XCTAssertEqual(limits.windows.map(\.kind), [.weekly])
        XCTAssertNil(limits.windows[0].resetsAt)
    }

    func testMissingFileIsNotConfiguredOrNotInstalled() throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("claude-rate-limits.json")
        let claudeDir = directory.appendingPathComponent(".claude")
        let absent = ClaudeRateLimitReader(
            fileURL: file,
            desktopFileURL: directory.appendingPathComponent("plan-usage-history.json"),
            directoryURL: claudeDir,
            desktopDirectoryURL: directory.appendingPathComponent("Claude"),
            binaryExists: false
        )
        guard case .notInstalled = absent.read() else { return XCTFail("expected notInstalled") }
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        guard case .notConfigured = absent.read() else { return XCTFail("expected notConfigured") }
        try Data(#"{"written_at": 1, "rate_limits": {}}"#.utf8).write(to: file)
        guard case .notConfigured = absent.read() else { return XCTFail("empty rate_limits is not a value") }
        try Data(#"{"written_at": 1, "rate_limits": {"five_hour": {"used_percentage": 5}}}"#.utf8).write(to: file)
        guard case .found(let limits) = absent.read() else { return XCTFail("expected found") }
        XCTAssertEqual(limits.windows.map(\.kind), [.fiveHour])
    }

    func testProviderDropsExpiredWindowsAndUsesWrittenAt() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let written = now.addingTimeInterval(-120)
        let live = UsageWindow(kind: .fiveHour, label: "5h", usedFraction: 0.2, resetsAt: now.addingTimeInterval(60))
        let expired = UsageWindow(kind: .weekly, label: "Weekly", usedFraction: 0.4, resetsAt: now.addingTimeInterval(-1))
        let provider = ClaudeProvider(read: { .found(ClaudeRateLimits(windows: [live, expired], writtenAt: written)) })
        let attempt = await provider.fetch(now: now)
        XCTAssertEqual(attempt.snapshot.status, .ok)
        XCTAssertEqual(attempt.snapshot.windows, [live])
        XCTAssertEqual(attempt.snapshot.fetchedAt, written)
        XCTAssertNil(attempt.snapshot.planLabel)

        let unconfigured = ClaudeProvider(read: { .notConfigured })
        let status = await unconfigured.fetch(now: now).snapshot.status
        XCTAssertEqual(status, .notConfigured)
    }
}

final class ClaudeDesktopUsageTests: XCTestCase {
    func testLastSampleBecomesWindows() throws {
        let json = #"""
        {"version": 2, "samples": [
          {"t": 1790449601272, "org": "o", "u": {"fh": 44, "sd": 22}},
          {"t": 1790450501236, "org": "o", "u": {"fh": 48, "sd": 22}}]}
        """#
        let limits = try XCTUnwrap(ClaudeDesktopUsageReader.parse(Data(json.utf8)))
        XCTAssertEqual(limits.writtenAt.timeIntervalSince1970, 1_790_450_501.236, accuracy: 0.001)
        XCTAssertEqual(limits.windows.map(\.kind), [.fiveHour, .weekly])
        XCTAssertEqual(limits.windows[0].usedFraction, 0.48, accuracy: 0.0001)
        XCTAssertEqual(limits.windows[1].usedFraction, 0.22, accuracy: 0.0001)
        XCTAssertNil(limits.windows[0].resetsAt)
    }

    func testEmptyOrBrokenIsNil() {
        XCTAssertNil(ClaudeDesktopUsageReader.parse(Data(#"{"version": 2, "samples": []}"#.utf8)))
        XCTAssertNil(ClaudeDesktopUsageReader.parse(Data("not json".utf8)))
    }

    func testNewerSourceWinsAndBorrowsFutureResets() throws {
        let directory = try temporaryDirectory()
        let statusline = directory.appendingPathComponent("claude-rate-limits.json")
        let desktop = directory.appendingPathComponent("plan-usage-history.json")
        let reader = ClaudeRateLimitReader(
            fileURL: statusline,
            desktopFileURL: desktop,
            directoryURL: directory.appendingPathComponent(".claude"),
            desktopDirectoryURL: directory.appendingPathComponent("Claude"),
            binaryExists: false
        )
        // status line at t=1000: 5h resets at 2000, weekly resets at 500 (already past)
        try Data(#"{"written_at": 1000, "rate_limits": {"five_hour": {"used_percentage": 10, "resets_at": 2000}, "seven_day": {"used_percentage": 20, "resets_at": 500}}}"#.utf8).write(to: statusline)
        // desktop at t=1500 (newer)
        try Data(#"{"version": 2, "samples": [{"t": 1500000, "org": "o", "u": {"fh": 30, "sd": 40}}]}"#.utf8).write(to: desktop)
        guard case .found(let newer) = reader.read() else { return XCTFail("expected found") }
        XCTAssertEqual(newer.writtenAt, Date(timeIntervalSince1970: 1500))
        XCTAssertEqual(newer.windows[0].usedFraction, 0.30, accuracy: 0.0001)
        XCTAssertEqual(newer.windows[0].resetsAt, Date(timeIntervalSince1970: 2000))
        XCTAssertEqual(newer.windows[1].usedFraction, 0.40, accuracy: 0.0001)
        XCTAssertNil(newer.windows[1].resetsAt)

        // The status line wins when it is newer.
        try Data(#"{"written_at": 1600, "rate_limits": {"five_hour": {"used_percentage": 11, "resets_at": 2000}}}"#.utf8).write(to: statusline)
        guard case .found(let older) = reader.read() else { return XCTFail("expected found") }
        XCTAssertEqual(older.writtenAt, Date(timeIntervalSince1970: 1600))
        XCTAssertEqual(older.windows.map(\.kind), [.fiveHour])
    }

    func testEmptySourceDoesNotHideTheOther() {
        let valid = ClaudeRateLimits(
            windows: [UsageWindow(kind: .fiveHour, label: "5h", usedFraction: 0.48, resetsAt: nil)],
            writtenAt: Date(timeIntervalSince1970: 1000)
        )
        let empty = ClaudeRateLimits(windows: [], writtenAt: Date(timeIntervalSince1970: 2000))
        XCTAssertEqual(ClaudeRateLimitReader.newest(valid, empty), valid)
        XCTAssertEqual(ClaudeRateLimitReader.newest(empty, valid), valid)
        XCTAssertNil(ClaudeDesktopUsageReader.parse(Data(#"{"version": 2, "samples": [{"t": 1, "org": "o", "u": {}}]}"#.utf8)))
    }

    func testDesktopHistoryOverOneMegabyteIsRead() throws {
        let directory = try temporaryDirectory()
        let desktop = directory.appendingPathComponent("plan-usage-history.json")
        let sample = #"{"t": 1000000, "org": "o", "u": {"fh": 1, "sd": 1}}"#
        let body = Array(repeating: sample, count: 30_000).joined(separator: ",")
        let json = #"{"version": 2, "samples": ["# + body + #", {"t": 2000000, "org": "o", "u": {"fh": 53, "sd": 23}}]}"#
        try Data(json.utf8).write(to: desktop)
        XCTAssertGreaterThan(try FileManager.default.attributesOfItem(atPath: desktop.path)[.size] as! Int, 1_048_576)
        let reader = ClaudeRateLimitReader(
            fileURL: directory.appendingPathComponent("claude-rate-limits.json"),
            desktopFileURL: desktop,
            directoryURL: directory,
            desktopDirectoryURL: directory,
            binaryExists: false
        )
        guard case .found(let limits) = reader.read() else { return XCTFail("expected found") }
        XCTAssertEqual(limits.windows[0].usedFraction, 0.53, accuracy: 0.0001)
    }

    func testDesktopFolderAloneIsNotConfigured() throws {
        let directory = try temporaryDirectory()
        let desktopDir = directory.appendingPathComponent("Claude")
        let reader = ClaudeRateLimitReader(
            fileURL: directory.appendingPathComponent("claude-rate-limits.json"),
            desktopFileURL: desktopDir.appendingPathComponent("plan-usage-history.json"),
            directoryURL: directory.appendingPathComponent(".claude"),
            desktopDirectoryURL: desktopDir,
            binaryExists: false
        )
        guard case .notInstalled = reader.read() else { return XCTFail("expected notInstalled") }
        try FileManager.default.createDirectory(at: desktopDir, withIntermediateDirectories: true)
        guard case .notConfigured = reader.read() else { return XCTFail("expected notConfigured") }
    }
}
