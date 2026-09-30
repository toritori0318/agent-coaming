import Foundation

public enum MenuBarReading {
    /// Highest 5-hour and weekly usage among enabled providers, as `10% | W35%`.
    public static func title(snapshot: Snapshot, enabled: Set<ProviderID>) -> String {
        let providers = snapshot.providers.filter { enabled.contains($0.id) && $0.status != .notInstalled }
        let fiveHour = maximum(providers, kind: .fiveHour)
        let weekly = maximum(providers, kind: .weekly)
        switch (fiveHour, weekly) {
        case let (fiveHour?, weekly?):
            return "\(formatUsedPercent(fiveHour)) | W\(formatUsedPercent(weekly))"
        case let (fiveHour?, nil):
            return formatUsedPercent(fiveHour)
        case let (nil, weekly?):
            return "W\(formatUsedPercent(weekly))"
        case (nil, nil):
            return "—"
        }
    }

    private static func maximum(_ providers: [ProviderSnapshot], kind: WindowKind) -> Double? {
        providers
            .flatMap(\.windows)
            .filter { $0.kind == kind && $0.label != "∞" }
            .map(\.usedFraction)
            .max()
    }
}
