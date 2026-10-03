import CoamingCore
import Foundation
import UserNotifications

@MainActor
final class LimitNotifier {
    private var notified: Set<String>
    private let defaults: UserDefaults

    init(defaults: UserDefaults = PreferenceStore.defaults()) {
        self.defaults = defaults
        notified = Set(defaults.stringArray(forKey: PreferenceKey.notifiedLimits) ?? [])
    }

    func sync(_ snapshot: Snapshot, enabled: Set<ProviderID>, language: AppLanguage, allowed: Bool) {
        // Not recorded while off, so a limit reached meanwhile notifies when it is turned on.
        guard allowed else { return }
        let result = LimitAlerts.evaluate(snapshot: snapshot, enabled: enabled, alreadyNotified: notified)
        notified = result.active
        defaults.set(Array(result.active), forKey: PreferenceKey.notifiedLimits)
        guard !result.crossings.isEmpty else { return }
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
                ja: "\(crossing.providerName) の \(crossing.windowName) が \(crossing.percentText) になりました。",
                en: "\(crossing.providerName) \(crossing.windowName) reached \(crossing.percentText)."
            )
            content.sound = .default
            let request = UNNotificationRequest(identifier: crossing.key, content: content, trigger: nil)
            try? await center.add(request)
        }
    }
}
