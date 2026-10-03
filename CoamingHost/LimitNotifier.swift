import CoamingCore
import Foundation
import UserNotifications

@MainActor
final class LimitNotifier {
    private var notified: Set<String>
    private let defaults: UserDefaults

    init(defaults: UserDefaults = PreferenceStore.defaults()) {
        self.defaults = defaults
        let stored = Set(defaults.stringArray(forKey: PreferenceKey.notifiedLimits) ?? [])
        let migrated = LimitAlerts.migrate(stored)
        notified = migrated
        if migrated != stored {
            defaults.set(Array(migrated), forKey: PreferenceKey.notifiedLimits)
        }
    }

    func sync(
        _ snapshot: Snapshot,
        enabled: Set<ProviderID>,
        language: AppLanguage,
        allowed: Bool,
        notifyLevels: Set<String>,
        notifyKinds: Set<WindowKind>
    ) {
        // Bands are recorded even while notifications are off, so turning them on does not
        // report a line usage has already crossed.
        let result = LimitAlerts.evaluate(
            snapshot: snapshot,
            enabled: enabled,
            alreadyNotified: notified,
            notifyLevels: allowed ? notifyLevels : [],
            notifyKinds: notifyKinds
        )
        notified = result.active
        defaults.set(Array(result.active), forKey: PreferenceKey.notifiedLimits)
        guard allowed, !result.crossings.isEmpty else { return }
        let crossings = result.crossings
        Task { await self.deliver(crossings, language: language) }
    }

    func requestAuthorization() {
        Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
    }

    private func deliver(_ crossings: [LimitCrossing], language: AppLanguage) async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }
        for crossing in crossings {
            let content = UNMutableNotificationContent()
            content.title = "Agent Coaming"
            content.body = language.pick(
                ja: "\(crossing.providerName) の \(crossing.windowName) が \(crossing.thresholdText) を超えました。",
                en: "\(crossing.providerName) \(crossing.windowName) crossed \(crossing.thresholdText)."
            )
            content.sound = .default
            let request = UNNotificationRequest(identifier: crossing.key, content: content, trigger: nil)
            try? await center.add(request)
        }
    }
}
