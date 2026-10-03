import Foundation

public struct LimitCrossing: Equatable, Sendable {
    public var key: String
    public var providerName: String
    public var windowName: String
    public var percentText: String

    public init(key: String, providerName: String, windowName: String, percentText: String) {
        self.key = key
        self.providerName = providerName
        self.windowName = windowName
        self.percentText = percentText
    }
}

public enum LimitAlerts {
    /// Newly reached limits, and the set of limits that are at or above the threshold now.
    /// `alreadyNotified` suppresses a repeat until usage falls below the threshold.
    public static func evaluate(
        snapshot: Snapshot,
        enabled: Set<ProviderID>,
        alreadyNotified: Set<String>,
        threshold: Double = Constants.usageRedThreshold
    ) -> (crossings: [LimitCrossing], active: Set<String>) {
        let checked = snapshot.providers.filter { enabled.contains($0.id) && $0.status == .ok }
        let checkedIDs = Set(checked.map { $0.id.rawValue })
        // A stale, disabled, or missing provider says nothing about usage, so its keys are kept
        // instead of cleared; clearing them would repeat the alert when it comes back still over.
        var active = alreadyNotified.filter { !checkedIDs.contains(String($0.prefix { $0 != "." })) }
        var crossings: [LimitCrossing] = []
        for provider in checked {
            for window in provider.windows where isQuota(window.kind) && window.label != "∞" && window.usedFraction >= threshold {
                let key = "\(provider.id.rawValue).\(window.kind.rawValue)"
                active.insert(key)
                if alreadyNotified.contains(key) { continue }
                crossings.append(LimitCrossing(
                    key: key,
                    providerName: provider.displayName,
                    windowName: shortName(window.kind),
                    percentText: formatUsedPercent(window.usedFraction)
                ))
            }
        }
        return (crossings, active)
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
