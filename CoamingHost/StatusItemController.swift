import CoamingCore
import AppKit

@MainActor
final class StatusItemController: NSObject {
    var onClick: () -> Void = {}
    private var item: NSStatusItem?
    private var title = "—"
    private var screenObserver: NSObjectProtocol?
    private var reinstallTask: Task<Void, Never>?

    override init() {
        super.init()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleReinstall()
            }
        }
    }

    func setVisible(_ visible: Bool) {
        if visible {
            guard item == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.target = self
            item.button?.action = #selector(clicked)
            item.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            item.button?.title = title
            self.item = item
        } else if let item {
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        }
    }

    func update(_ snapshot: Snapshot, enabled: Set<ProviderID>) {
        let highest = snapshot.providers
            .filter { enabled.contains($0.id) && $0.status != .notInstalled }
            .flatMap(\.windows)
            .filter { $0.kind == .fiveHour }
            .map(\.usedFraction)
            .max()
        title = highest.map(formatUsedPercent) ?? "—"
        item?.button?.title = title
    }

    /// A status item created while an external display is attached can stay on that menu bar
    /// after the display is removed. Remove it and create it again on the menu bar that remains.
    private func scheduleReinstall() {
        guard item != nil else { return }
        reinstallTask?.cancel()
        reinstallTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Constants.menuBarReinstallDelay))
            guard !Task.isCancelled, item != nil else { return }
            setVisible(false)
            setVisible(true)
        }
    }

    @objc private func clicked() {
        onClick()
    }
}
