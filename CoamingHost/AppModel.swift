import CoamingCore
import AppKit
import ServiceManagement
import SwiftUI
import WidgetKit

@MainActor
@Observable
final class AppModel {
    var snapshot = Snapshot.waiting()
    var containerAvailable = true
    var menuBar = false
    var overlayVisible = false
    var launchAtLogin = false
    var launchAtLoginNotice: LoginItemNotice?
    var refreshing = false
    var refreshSkipped = false
    var language: AppLanguage = .ja
    var enabled: [ProviderID: Bool] = Dictionary(uniqueKeysWithValues: ProviderID.included.map { ($0, true) })

    private var refresher: Refresher?
    private var store = SnapshotStore(fileURL: nil)
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var pendingForce = false
    private let defaults = PreferenceStore.defaults()
    let status = StatusItemController()
    let overlay = UsageOverlayController()

    func start() async {
        store = SnapshotStore.live()
        containerAvailable = store.fileURL != nil
        if let previous = store.read()?.keepingIncluded() {
            snapshot = previous
        }
        menuBar = defaults.bool(forKey: PreferenceKey.menuBarVisible)
        overlayVisible = defaults.bool(forKey: PreferenceKey.overlayVisible)
        launchAtLogin = SMAppService.mainApp.status == .enabled
        if let raw = defaults.string(forKey: PreferenceKey.language), let stored = AppLanguage(rawValue: raw) {
            language = stored
        }
        for id in ProviderID.included {
            let key = PreferenceKey.providerEnabled(id)
            enabled[id] = defaults.object(forKey: key) == nil ? true : defaults.bool(forKey: key)
        }
        status.setVisible(menuBar)
        status.update(snapshot, enabled: enabledIDs)
        overlay.bind(self)
        overlay.setVisible(overlayVisible)
        let previous = store.read()?.keepingIncluded()
        refresher = await Task.detached {
            CoamingLive.makeRefresher(previous: previous)
        }.value
        await refresh(force: false)
        armTimer()
        armWake()
    }

    func setMenuBar(_ value: Bool) {
        menuBar = value
        defaults.set(value, forKey: PreferenceKey.menuBarVisible)
        status.setVisible(value)
        status.update(snapshot, enabled: enabledIDs)
    }

    func setLanguage(_ value: AppLanguage) {
        language = value
        defaults.set(value.rawValue, forKey: PreferenceKey.language)
        scheduleOverlayLayout()
    }

    func isEnabled(_ id: ProviderID) -> Bool {
        enabled[id] ?? true
    }

    var enabledIDs: Set<ProviderID> {
        Set(ProviderID.included.filter { isEnabled($0) })
    }

    func setEnabled(_ id: ProviderID, _ value: Bool) {
        enabled[id] = value
        defaults.set(value, forKey: PreferenceKey.providerEnabled(id))
        status.update(snapshot, enabled: enabledIDs)
        scheduleOverlayLayout()
        Task { await refresh(force: true) }
    }

    func setOverlay(_ value: Bool) {
        overlayVisible = value
        defaults.set(value, forKey: PreferenceKey.overlayVisible)
        overlay.setVisible(value)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            let status = SMAppService.mainApp.status
            launchAtLogin = status == .enabled
            launchAtLoginNotice = status == .requiresApproval ? .needsApproval : nil
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            launchAtLoginNotice = .placeInApplications
        }
    }

    func refresh(force: Bool) async {
        if refreshing {
            pendingForce = pendingForce || force
            return
        }
        refreshing = true
        refreshSkipped = false
        defer {
            refreshing = false
            if pendingForce {
                pendingForce = false
                Task { await self.refresh(force: true) }
            }
        }
        guard let refresher else { return }
        let before = snapshot.generatedAt
        let next = await refresher.refresh(force: force, enabled: enabledIDs)
        if force, next.generatedAt == before {
            refreshSkipped = true
        }
        snapshot = next
        status.update(snapshot, enabled: enabledIDs)
        scheduleOverlayLayout()
        guard store.fileURL != nil else {
            containerAvailable = false
            return
        }
        do {
            try store.write(snapshot)
            containerAvailable = true
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            containerAvailable = false
        }
    }

    private func armTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: Constants.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh(force: false)
            }
        }
        timer.tolerance = Constants.timerTolerance
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func armWake() {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(Constants.wakeRefreshDelay))
                await self?.refresh(force: false)
            }
        }
    }

    private func scheduleOverlayLayout() {
        Task { @MainActor in
            overlay.relayout()
        }
    }
}

enum LoginItemNotice {
    case needsApproval
    case placeInApplications
}
