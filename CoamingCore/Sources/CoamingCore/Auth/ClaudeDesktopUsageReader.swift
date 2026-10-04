import Foundation

/// Reads the last sample in `plan-usage-history.json`, which Claude Desktop writes about every 15 minutes while in use.
/// The file is unpublished. If the shape changes, return nil and leave it to the status line file.
/// `fh` is the 5-hour used percent, `sd` is the 7-day used percent. There is no reset time.
enum ClaudeDesktopUsageReader {
    static func parse(_ data: Data) -> ClaudeRateLimits? {
        guard let history = try? JSONDecoder().decode(History.self, from: data),
              let last = history.samples.last else { return nil }
        var windows: [UsageWindow] = []
        if let fiveHour = last.usage.fiveHour {
            windows.append(UsageWindow(kind: .fiveHour, label: "5h", usedFraction: fiveHour / 100, resetsAt: nil))
        }
        if let sevenDay = last.usage.sevenDay {
            windows.append(UsageWindow(kind: .weekly, label: "Weekly", usedFraction: sevenDay / 100, resetsAt: nil))
        }
        guard !windows.isEmpty else { return nil }
        return ClaudeRateLimits(windows: windows, writtenAt: Date(timeIntervalSince1970: last.timestampMillis / 1000))
    }
}

private struct History: Decodable {
    var samples: [Sample]
}

private struct Sample: Decodable {
    var timestampMillis: Double
    var usage: Usage

    enum CodingKeys: String, CodingKey {
        case timestampMillis = "t"
        case usage = "u"
    }
}

private struct Usage: Decodable {
    var fiveHour: Double?
    var sevenDay: Double?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "fh"
        case sevenDay = "sd"
    }
}
