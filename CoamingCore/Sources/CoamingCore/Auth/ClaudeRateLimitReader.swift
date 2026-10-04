import Foundation

/// rate_limits written by the Claude Code status line script (scripts/claude-statusline.sh).
/// Does not handle OAuth tokens. Anthropic reserves OAuth for Claude Code, so this app
/// does not call a usage API itself and reads the values Claude Code already received.
struct ClaudeRateLimits: Sendable, Equatable {
    var windows: [UsageWindow]
    var writtenAt: Date
}

enum ClaudeRead: Sendable {
    case found(ClaudeRateLimits)
    case notConfigured
    case notInstalled
}

struct ClaudeRateLimitReader: Sendable {
    /// File written by the status line script (includes reset times; updates only during a Claude Code session).
    var fileURL: URL
    /// plan-usage-history.json written by Claude Desktop (percent only, about every 15 minutes while the person works in Desktop; not while it idles in the background).
    var desktopFileURL: URL
    var directoryURL: URL
    var desktopDirectoryURL: URL
    var binaryExists: Bool

    func read() -> ClaudeRead {
        let statusline = readBounded(url: fileURL).flatMap { try? Self.parse($0) }
        let desktop = readBounded(url: desktopFileURL, limit: Constants.desktopHistoryReadByteLimit).flatMap(ClaudeDesktopUsageReader.parse)
        if let merged = Self.newest(statusline, desktop) {
            return .found(merged)
        }
        let claudeCodePresent = binaryExists || FileManager.default.fileExists(atPath: directoryURL.path)
        let desktopPresent = FileManager.default.fileExists(atPath: desktopDirectoryURL.path)
        return claudeCodePresent || desktopPresent ? .notConfigured : .notInstalled
    }

    /// Keep the newer record. If it has no reset time, borrow one from the same window on the older record.
    /// Only borrow a reset that is still in the future at the newer record's timestamp. A past reset would drop the window.
    static func newest(_ a: ClaudeRateLimits?, _ b: ClaudeRateLimits?) -> ClaudeRateLimits? {
        // A record with no windows counts as missing. A newer empty record must not erase a valid older one.
        let a = a.flatMap { $0.windows.isEmpty ? nil : $0 }
        let b = b.flatMap { $0.windows.isEmpty ? nil : $0 }
        guard let a else { return b }
        guard let b else { return a }
        var (newer, older) = a.writtenAt >= b.writtenAt ? (a, b) : (b, a)
        newer.windows = newer.windows.map { window in
            guard window.resetsAt == nil,
                  let borrowed = older.windows.first(where: { $0.kind == window.kind })?.resetsAt,
                  borrowed > newer.writtenAt else { return window }
            var copy = window
            copy.resetsAt = borrowed
            return copy
        }
        return newer
    }

    static func parse(_ data: Data) throws -> ClaudeRateLimits {
        let file = try JSONDecoder().decode(RateLimitFile.self, from: data)
        var windows: [UsageWindow] = []
        if let window = file.rateLimits?.fiveHour {
            windows.append(make(.fiveHour, label: "5h", window: window))
        }
        if let window = file.rateLimits?.sevenDay {
            windows.append(make(.weekly, label: "Weekly", window: window))
        }
        return ClaudeRateLimits(windows: windows, writtenAt: Date(timeIntervalSince1970: file.writtenAt))
    }

    private static func make(_ kind: WindowKind, label: String, window: RateLimitWindow) -> UsageWindow {
        UsageWindow(
            kind: kind,
            label: label,
            usedFraction: window.usedPercentage / 100,
            resetsAt: window.resetsAt.map { Date(timeIntervalSince1970: $0) }
        )
    }
}

private struct RateLimitFile: Decodable {
    var writtenAt: Double
    var rateLimits: RateLimits?

    enum CodingKeys: String, CodingKey {
        case writtenAt = "written_at"
        case rateLimits = "rate_limits"
    }
}

private struct RateLimits: Decodable {
    var fiveHour: RateLimitWindow?
    var sevenDay: RateLimitWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

private struct RateLimitWindow: Decodable {
    var usedPercentage: Double
    var resetsAt: Double?

    enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt = "resets_at"
    }
}
