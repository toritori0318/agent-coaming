import Foundation

public struct SmallWidgetRow: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var primary: String
    public var secondary: String?
    public var age: String?
    public var dimmed: Bool
}

public struct SmallWidgetModel: Sendable, Equatable {
    public var rows: [SmallWidgetRow]
    public var footer: String?
    public var emptyMessage: String?
}

public struct MediumWidgetRow: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var plan: String
    public var windowLabel: String
    public var fraction: Double?
    public var valueText: String
    public var resetsAt: Date?
    public var age: String?
    public var dimmed: Bool
    public var showsBar: Bool
}

public enum WidgetLayout {
    #if COAMING_CURSOR
    public static let emptyMessage = "Sign in to Claude, Codex, or Cursor"
    #else
    public static let emptyMessage = "Sign in to Claude or Codex"
    #endif

    public static func small(snapshot: Snapshot, now: Date) -> SmallWidgetModel {
        let visible = ordered(snapshot).filter { $0.status != .notInstalled }
        if visible.isEmpty {
            return SmallWidgetModel(rows: [], footer: nil, emptyMessage: emptyMessage)
        }
        let rows = visible.map { provider -> SmallWidgetRow in
            let windows = provider.windows.filter { $0.kind != .weeklyModel }
            let primary: String
            let secondary: String?
            if let status = statusText(provider), windows.isEmpty || provider.status == .needsLogin || provider.status == .unsupported || provider.status == .notConfigured {
                primary = status
                secondary = nil
            } else if windows.isEmpty {
                primary = "—"
                secondary = nil
            } else {
                primary = valueText(windows[0])
                secondary = windows.count > 1 ? valueText(windows[1]) : nil
            }
            return SmallWidgetRow(
                id: provider.id.rawValue,
                name: provider.displayName,
                primary: primary,
                secondary: secondary,
                age: age(provider, now: now),
                dimmed: isDimmed(provider, now: now)
            )
        }
        return SmallWidgetModel(
            rows: rows,
            footer: "Updated \(formatAge(since: snapshot.generatedAt, now: now))",
            emptyMessage: nil
        )
    }

    public static func medium(snapshot: Snapshot, now: Date) -> [MediumWidgetRow] {
        let visible = ordered(snapshot).filter { $0.status != .notInstalled }
        if visible.isEmpty { return [] }
        var rows: [MediumWidgetRow] = []
        for provider in visible {
            rows.append(contentsOf: lines(for: provider, now: now))
        }
        // Drop rows only when there are too many: low weeklyModel fractions first, then lower-priority kinds.
        if rows.count > Constants.mediumMaxRows {
            rows.removeAll { row in
                row.id.contains("-\(WindowKind.weeklyModel.rawValue)-") && (row.fraction ?? 1) < Constants.weeklyModelMinFraction
            }
        }
        while rows.count > Constants.mediumMaxRows {
            guard let index = dropIndex(in: rows) else { break }
            rows.remove(at: index)
        }
        return markingContinuations(rows)
    }

    private static func lines(for provider: ProviderSnapshot, now: Date) -> [MediumWidgetRow] {
        if provider.status == .needsLogin || provider.status == .unsupported || provider.status == .notConfigured {
            return [statusRow(provider, text: statusText(provider) ?? "—", now: now)]
        }
        let windows = provider.windows
        if windows.isEmpty {
            let text = provider.staleReason == "waiting" ? "Loading" : "—"
            return [statusRow(provider, text: text, now: now)]
        }
        return windows.enumerated().map { index, window in
            MediumWidgetRow(
                id: "\(provider.id.rawValue)-\(window.kind.rawValue)-\(window.label)-\(index)",
                name: provider.displayName,
                plan: provider.planLabel ?? "",
                windowLabel: window.label,
                fraction: window.label == "∞" ? nil : window.usedFraction,
                valueText: valueText(window),
                resetsAt: window.resetsAt,
                age: age(provider, now: now),
                dimmed: isDimmed(provider, now: now),
                showsBar: window.label != "∞"
            )
        }
    }

    private static func statusRow(_ provider: ProviderSnapshot, text: String, now: Date) -> MediumWidgetRow {
        MediumWidgetRow(
            id: "\(provider.id.rawValue)-status",
            name: provider.displayName,
            plan: provider.planLabel ?? "",
            windowLabel: "",
            fraction: nil,
            valueText: text,
            resetsAt: nil,
            age: age(provider, now: now),
            dimmed: isDimmed(provider, now: now),
            showsBar: false
        )
    }

    private static func dropIndex(in rows: [MediumWidgetRow]) -> Int? {
        for kind in Constants.mediumRowPriority.reversed() {
            if let index = rows.lastIndex(where: { $0.id.contains("-\(kind.rawValue)-") }) {
                return index
            }
        }
        return rows.indices.last
    }

    private static func markingContinuations(_ rows: [MediumWidgetRow]) -> [MediumWidgetRow] {
        var seen: Set<String> = []
        return rows.map { row in
            var copy = row
            let key = row.id.split(separator: "-").first.map(String.init) ?? row.id
            if seen.contains(key) {
                copy.name = ""
                copy.plan = ""
                copy.age = nil
            } else {
                seen.insert(key)
            }
            return copy
        }
    }

    private static func ordered(_ snapshot: Snapshot) -> [ProviderSnapshot] {
        ProviderID.included.compactMap { id in snapshot.providers.first { $0.id == id } }
    }

    private static func statusText(_ provider: ProviderSnapshot) -> String? {
        switch provider.status {
        case .needsLogin: "Sign in again"
        case .unsupported: "API key not supported"
        case .notConfigured: "Setup required"
        case .stale where provider.staleReason == "waiting": "Loading"
        default: nil
        }
    }

    private static func valueText(_ window: UsageWindow) -> String {
        window.label == "∞" ? "∞" : formatUsedPercent(window.usedFraction)
    }

    /// Dim when stale, or when an ok value is older than staleAfter (the host is not running).
    public static func isDimmed(_ provider: ProviderSnapshot, now: Date) -> Bool {
        if provider.status == .stale { return true }
        guard provider.status == .ok, let fetchedAt = provider.fetchedAt else { return false }
        return now.timeIntervalSince(fetchedAt) > Constants.staleAfter
    }

    private static func age(_ provider: ProviderSnapshot, now: Date) -> String? {
        guard isDimmed(provider, now: now), let fetchedAt = provider.fetchedAt else { return nil }
        return formatAge(since: fetchedAt, now: now)
    }
}

public func usageIsWarning(_ fraction: Double) -> Bool {
    fraction >= Constants.usageOrangeThreshold && fraction < Constants.usageRedThreshold
}

public func usageIsCritical(_ fraction: Double) -> Bool {
    fraction >= Constants.usageRedThreshold
}
