import CoamingCore
import AppKit

@MainActor
final class StatusItemController: NSObject {
    var onClick: () -> Void = {}
    private var item: NSStatusItem?

    func setVisible(_ visible: Bool) {
        if visible {
            guard item == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.target = self
            item.button?.action = #selector(clicked)
            item.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            self.item = item
        } else if let item {
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        }
    }

    func update(_ snapshot: Snapshot, enabled: Set<ProviderID>) {
        item?.button?.title = MenuBarReading.title(snapshot: snapshot, enabled: enabled)
        item?.button?.appearsDisabled = MenuBarReading.isDimmed(snapshot: snapshot, enabled: enabled, now: Date())
    }

    @objc private func clicked() {
        onClick()
    }
}
