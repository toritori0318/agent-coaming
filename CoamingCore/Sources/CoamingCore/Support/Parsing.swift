import Foundation
import os

enum Log {
    static let usage = Logger(subsystem: "io.github.toritori0318.agentcoaming", category: "usage")
    static let auth = Logger(subsystem: "io.github.toritori0318.agentcoaming", category: "auth")
}

func clamp01(_ value: Double) -> Double {
    guard value.isFinite else { return 0 }
    return min(1, max(0, value))
}

public func formatUsedPercent(_ fraction: Double) -> String {
    let percent = (clamp01(fraction) * 100).rounded()
    return "\(Int(percent))%"
}

/// Clock time for when a limit window resets. Same calendar day is the time only.
/// A later day includes the month and day. Japanese is 24-hour. English is 12-hour.
public func formatResetClock(_ date: Date, now: Date, locale: Locale, calendar: Calendar = .current) -> String {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.locale = locale
    formatter.timeZone = calendar.timeZone
    formatter.amSymbol = "AM"
    formatter.pmSymbol = "PM"
    let sameDay = calendar.isDate(date, inSameDayAs: now)
    let japanese = locale.identifier.hasPrefix("ja")
    if japanese {
        formatter.dateFormat = sameDay ? "H:mm" : "M/d H:mm"
    } else {
        formatter.dateFormat = sameDay ? "h:mm a" : "M/d h:mm a"
    }
    return formatter.string(from: date)
}

/// Time left until a limit resets, in one unit: minutes under an hour, hours under a day, otherwise days.
public func formatResetRemaining(_ date: Date, now: Date, locale: Locale) -> String {
    let seconds = Int(date.timeIntervalSince(now))
    guard seconds > 0 else { return "" }
    let japanese = locale.identifier.hasPrefix("ja")
    let minutes = seconds / 60
    if minutes < 60 {
        let shown = max(minutes, 1)
        if japanese { return "あと\(shown)分" }
        return shown == 1 ? "1 min left" : "\(shown) min left"
    }
    let hours = minutes / 60
    if hours < 24 {
        if japanese { return "あと\(hours)時間" }
        return hours == 1 ? "1 hour left" : "\(hours) hours left"
    }
    let days = hours / 24
    if japanese { return "あと\(days)日" }
    return days == 1 ? "1 day left" : "\(days) days left"
}

/// How old a value is, in one unit, as words: 20時間前 / 20 hours ago.
public func formatAgeWords(since date: Date, now: Date, locale: Locale) -> String {
    let seconds = max(0, Int(now.timeIntervalSince(date)))
    let japanese = locale.identifier.hasPrefix("ja")
    let minutes = seconds / 60
    if minutes < 60 {
        let shown = max(minutes, 1)
        if japanese { return "\(shown)分前" }
        return shown == 1 ? "1 minute ago" : "\(shown) minutes ago"
    }
    let hours = minutes / 60
    if hours < 24 {
        if japanese { return "\(hours)時間前" }
        return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
    }
    let days = hours / 24
    if japanese { return "\(days)日前" }
    return days == 1 ? "1 day ago" : "\(days) days ago"
}

public func formatAge(since date: Date, now: Date) -> String {
    let seconds = max(0, Int(now.timeIntervalSince(date)))
    if seconds < 60 { return "\(seconds)s ago" }
    let minutes = seconds / 60
    if minutes < 60 { return "\(minutes)m ago" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours)h ago" }
    return "\(hours / 24)d ago"
}

public enum DateParsing {
    static func parseISO8601(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let numeric = Double(trimmed) {
            return Date(timeIntervalSince1970: numeric)
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: trimmed) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: trimmed)
    }

    public static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    static func day(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func normalizeCredentialEpoch(_ value: Double) -> Date {
        if value > Constants.epochMillisecondsThreshold {
            return Date(timeIntervalSince1970: value / 1000)
        }
        return Date(timeIntervalSince1970: value)
    }
}

enum JSONKeyTree {
    static func describe(_ data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return "non-json" }
        let tree = walk(object, prefix: "")
        if tree.count > 500 { return String(tree.prefix(500)) }
        return tree
    }

    private static func walk(_ object: Any, prefix: String) -> String {
        switch object {
        case let dictionary as [String: Any]:
            let keys = dictionary.keys.sorted()
            if keys.isEmpty { return prefix.isEmpty ? "{}" : prefix }
            return keys.map { key in
                let path = prefix.isEmpty ? key : "\(prefix).\(key)"
                return walk(dictionary[key] as Any, prefix: path)
            }.joined(separator: ",")
        case let array as [Any]:
            let path = prefix + "[]"
            if let first = array.first { return walk(first, prefix: path) }
            return path
        default:
            return prefix
        }
    }
}

enum RetryAfterParser {
    static func parse(header: String?, now: Date) -> TimeInterval? {
        guard let raw = header?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if let seconds = TimeInterval(raw) {
            return min(max(seconds, 0), Constants.retryAfterMax)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss zzz"
        guard let date = formatter.date(from: raw) else { return nil }
        return min(max(date.timeIntervalSince(now), 0), Constants.retryAfterMax)
    }
}

func readBounded(url: URL, limit: Int = Constants.credentialReadByteLimit) -> Data? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }
    return try? handle.read(upToCount: limit)
}
