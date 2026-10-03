import Foundation

public struct LimitCrossing: Equatable, Sendable {
    public var key: String
    public var providerName: String
    public var windowName: String
    public var thresholdText: String

    public init(key: String, providerName: String, windowName: String, thresholdText: String) {
        self.key = key
        self.providerName = providerName
        self.windowName = windowName
        self.thresholdText = thresholdText
    }
}

public enum LimitAlerts {
    public static let orange = "75"
    public static let red = "90"

    /// Lower line first, so a jump past both reports 75% and then 90%.
    public static let levels: [(token: String, fraction: Double)] = [
        (orange, Constants.usageOrangeThreshold),
        (red, Constants.usageRedThreshold),
    ]

    /// Keys for lines usage is at or above, and the lines just crossed from below.
    /// A line already crossed stays quiet until usage falls below it and crosses it again.
    /// `notifyLevels` and `notifyKinds` choose which crossings are reported. The active set still
    /// tracks every line, so turning a line on later does not fire for a crossing already past.
    public static func evaluate(
        snapshot: Snapshot,
        enabled: Set<ProviderID>,
        alreadyNotified: Set<String>,
        notifyLevels: Set<String>,
        notifyKinds: Set<WindowKind>
    ) -> (crossings: [LimitCrossing], active: Set<String>) {
        let checked = snapshot.providers.filter { enabled.contains($0.id) && $0.status == .ok }
        let checkedIDs = Set(checked.map { $0.id.rawValue })
        // A stale, disabled, or missing provider says nothing about usage, so its keys are kept
        // instead of cleared; clearing them would repeat the alert when it comes back still over.
        var active = alreadyNotified.filter { !checkedIDs.contains(providerID(of: $0)) }
        var crossings: [LimitCrossing] = []
        for provider in checked {
            for window in provider.windows where isQuota(window.kind) && window.label != "∞" {
                for level in levels where window.usedFraction >= level.fraction {
                    let key = "\(provider.id.rawValue).\(window.kind.rawValue).\(level.token)"
                    active.insert(key)
                    guard notifyLevels.contains(level.token), notifyKinds.contains(window.kind) else { continue }
                    if alreadyNotified.contains(key) { continue }
                    crossings.append(LimitCrossing(
                        key: key,
                        providerName: provider.displayName,
                        windowName: shortName(window.kind),
                        thresholdText: formatUsedPercent(level.fraction)
                    ))
                }
            }
        }
        return (crossings, active)
    }

    /// Older builds stored `claude.fiveHour` for "at or above 90%". That includes 75%.
    public static func migrate(_ keys: Set<String>) -> Set<String> {
        var migrated: Set<String> = []
        for key in keys {
            let parts = key.split(separator: ".")
            if parts.count == 2 {
                migrated.insert("\(key).\(orange)")
                migrated.insert("\(key).\(red)")
            } else {
                migrated.insert(key)
            }
        }
        return migrated
    }

    private static func providerID(of key: String) -> String {
        String(key.prefix { $0 != "." })
    }

    private static func isQuota(_ kind: WindowKind) -> Bool {
        switch kind {
        case .fiveHour, .weekly, .billingPlan: true
        case .weeklyModel, .billingOnDemand: false
        }
    }

    private static func shortName(_ kind: WindowKind) -> String {
        switch kind {
        case .fiveHour: "5h"
        case .weekly: "1w"
        case .billingPlan: "1mo"
        case .weeklyModel, .billingOnDemand: ""
        }
    }
}
