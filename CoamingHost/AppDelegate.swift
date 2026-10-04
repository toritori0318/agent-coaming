import AppKit
import CoreServices
import Sparkle
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var window: NSWindow?
    private let notificationPresenter = NotificationPresenter()
    // Automatic checks stay off. SUEnableAutomaticChecks in Info.plist is false.
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = notificationPresenter
        model.status.onClick = { [weak self] in
            self?.showSettings()
        }
        model.overlay.onClick = { [weak self] in
            self?.showSettings()
        }
        let login = Self.launchedAsLoginItem()
        Task {
            if !login {
                showSettings()
            }
            await model.start()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        updaterController.checkForUpdates(nil)
    }

    func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let view = SettingsView(model: model, checkForUpdates: { [weak self] in
            self?.checkForUpdates()
        })
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Agent Coaming"
        // The visible header is SettingsTitle in the toolbar. This title stays for the Window menu.
        window.titleVisibility = .hidden
        window.toolbarStyle = .unifiedCompact
        window.titlebarSeparatorStyle = .line
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 560, height: 680))
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        // SwiftUI installs the toolbar while the window appears, and may reset these.
        window.toolbarStyle = .unifiedCompact
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .line
        self.window = window
    }

    private static func launchedAsLoginItem() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        if event.eventID != AEEventID(kAEOpenApplication) { return false }
        guard let descriptor = event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData)) else { return false }
        return descriptor.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }
}

private final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
