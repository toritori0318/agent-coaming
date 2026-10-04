import Foundation

public enum Constants {
    public static let pollInterval: TimeInterval = 5 * 60
    public static let timerTolerance: TimeInterval = 30
    public static let requestTimeout: TimeInterval = 15
    /// Refresh within 15 seconds of wake. Wait briefly for the network to return.
    public static let wakeRefreshDelay: TimeInterval = 3
    /// Wait for the menu bar to settle after a display is connected or removed, then recreate the status item.
    public static let menuBarReinstallDelay: TimeInterval = 0.3
    public static let expiryLeeway: TimeInterval = 60
    public static let manualRefreshMinInterval: TimeInterval = 60
    public static let retryAfterDefault: TimeInterval = 30 * 60
    public static let retryAfterConsecutive: TimeInterval = 60 * 60
    public static let retryAfterMax: TimeInterval = 60 * 60
    public static let widgetTimelineMax: TimeInterval = 15 * 60
    /// Dim ok values older than this so a stopped host is visible.
    /// Longer than Claude Desktop's 15-minute write interval while in use (about ±2 minutes in practice).
    public static let staleAfter: TimeInterval = 20 * 60
    public static let sqliteBusyTimeoutMillis: Int32 = 250
    public static let appVersion = "1.3.0"
    /// Matches the observed point where Claude Code's weekly warning starts (75%). The official threshold is unpublished and decided server-side.
    public static let usageOrangeThreshold = 0.75
    public static let usageRedThreshold = 0.90
    public static let weeklyWindowMinimumSeconds = 6 * 24 * 3600
    public static let epochMillisecondsThreshold = 10_000_000_000.0
    public static let mediumMaxRows = 6
    public static let weeklyModelMinFraction = 0.5
    public static let credentialReadByteLimit = 1_048_576
    /// Desktop appends plan-usage-history.json about every 15 minutes, roughly 95KB a month. A partial read is not valid JSON.
    public static let desktopHistoryReadByteLimit = 16 * 1_048_576
    public static let appGroupName = "group.agentcoaming"
    // The default build has no network hosts. cursor.com exists only in a COAMING_CURSOR build. See ProviderID.included.
    #if COAMING_CURSOR
    public static let cursorKeychainService = "cursor-access-token"
    public static let allowedHosts: Set<String> = ["cursor.com"]
    public static let cursorUsageURL = URL(string: "https://cursor.com/api/usage-summary")!
    #else
    public static let allowedHosts: Set<String> = []
    #endif
    /// Lower index is kept. When medium exceeds `mediumMaxRows`, drop from the end.
    /// weeklyModel rows below `weeklyModelMinFraction` are removed before consulting this list.
    public static let mediumRowPriority: [WindowKind] = [
        .fiveHour,
        .weekly,
        .billingPlan,
        .weeklyModel,
        .billingOnDemand,
    ]

    public static func capitalize(_ value: String) -> String {
        guard let first = value.first else { return value }
        return String(first).uppercased() + value.dropFirst()
    }
}
