import Foundation

public enum MenuBarReading {
    /// Highest 5-hour and weekly usage among enabled providers, as `5h 10% 1w 35%`.
    public static func title(snapshot: Snapshot, enabled: Set<ProviderID>) -> String {
        let providers = included(snapshot, enabled: enabled)
        let parts = [
            maximum(providers, kind: .fiveHour).map { "5h \(formatUsedPercent($0))" },
            maximum(providers, kind: .weekly).map { "1w \(formatUsedPercent($0))" },
        ].compactMap { $0 }
        return parts.isEmpty ? "—" : parts.joined(separator: " ")
    }

    /// True when any reading behind the title is a previous value, the same rule the overlay dims by.
    public static func isDimmed(snapshot: Snapshot, enabled: Set<ProviderID>, now: Date) -> Bool {
        included(snapshot, enabled: enabled).contains { provider in
            provider.windows.contains { $0.kind == .fiveHour || $0.kind == .weekly }
                && WidgetLayout.isDimmed(provider, now: now)
        }
    }

    private static func included(_ snapshot: Snapshot, enabled: Set<ProviderID>) -> [ProviderSnapshot] {
        snapshot.providers.filter { enabled.contains($0.id) && $0.status != .notInstalled }
    }

    private static func maximum(_ providers: [ProviderSnapshot], kind: WindowKind) -> Double? {
        providers
            .flatMap(\.windows)
            // Only billing windows carry "∞" today. Kept so an unlimited 5h or weekly window never reads as 0%.
            .filter { $0.kind == kind && $0.label != "∞" }
            .map(\.usedFraction)
            .max()
    }
}
