import CoamingCore
import AppKit
import SwiftUI

/// Small indicator that stays at the screen edge while other apps are in front.
/// A borderless panel above everything else, in the same style as Kotofumi's recording overlay.
@MainActor
final class UsageOverlayController {
    var onClick: () -> Void = {}
    private weak var model: AppModel?
    private var panel: NSPanel?
    private var moveObserver: NSObjectProtocol?
    private let defaults = PreferenceStore.defaults()

    func bind(_ model: AppModel) {
        self.model = model
    }

    func setVisible(_ visible: Bool) {
        if visible {
            ensurePanel()
            panel?.orderFrontRegardless()
        } else {
            panel?.orderOut(nil)
        }
    }

    private func ensurePanel() {
        guard panel == nil, let model else { return }
        let host = OverlayHostView(rootView: UsageOverlayView(model: model))
        host.onClick = { [weak self] in self?.onClick() }
        host.sizingOptions = [.intrinsicContentSize]
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        let resolved = size.width > 80 && size.height > 60 ? size : NSSize(width: 120, height: 96)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: resolved),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = true
        panel.contentView = host
        panel.setContentSize(resolved)
        place(panel)
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.saveOrigin()
            }
        }
        self.panel = panel
    }

    private func place(_ panel: NSPanel) {
        let size = panel.frame.size
        guard let visible = NSScreen.main?.visibleFrame else { return }
        let savedX = defaults.object(forKey: PreferenceKey.overlayOriginX) as? Double
        let savedY = defaults.object(forKey: PreferenceKey.overlayOriginY) as? Double
        var origin = NSPoint(x: visible.maxX - size.width - 16, y: visible.maxY - size.height - 72)
        if let savedX, let savedY {
            origin = NSPoint(x: savedX, y: savedY)
        }
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        panel.setFrameOrigin(origin)
    }

    private func saveOrigin() {
        guard let origin = panel?.frame.origin else { return }
        defaults.set(origin.x, forKey: PreferenceKey.overlayOriginX)
        defaults.set(origin.y, forKey: PreferenceKey.overlayOriginY)
    }

    func relayout() {
        guard let host = panel?.contentView else { return }
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        guard size.width > 40, size.height > 20 else { return }
        let origin = panel?.frame.origin ?? .zero
        panel?.setContentSize(size)
        if let visible = NSScreen.main?.visibleFrame {
            var clamped = origin
            clamped.x = min(max(clamped.x, visible.minX), visible.maxX - size.width)
            clamped.y = min(max(clamped.y, visible.minY), visible.maxY - size.height)
            panel?.setFrameOrigin(clamped)
        }
    }
}

/// A click opens settings. A small movement is treated as a drag.
private final class OverlayHostView<Content: View>: NSHostingView<Content> {
    var onClick: () -> Void = {}

    override func mouseDown(with event: NSEvent) {
        let start = NSEvent.mouseLocation
        window?.performDrag(with: event)
        let end = NSEvent.mouseLocation
        let moved = hypot(end.x - start.x, end.y - start.y)
        if moved < 5 {
            onClick()
        }
    }
}

private enum OverlayMetrics {
    static let nameWidth: CGFloat = 46
    static let slotWidth: CGFloat = 26
}

private struct UsageOverlayView: View {
    var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if meters.isEmpty {
                Text(model.language.pick(ja: "オフ", en: "Off"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            } else {
                HStack(spacing: 0) {
                    Color.clear.frame(width: OverlayMetrics.nameWidth, height: 1)
                    if showsFiveHourColumn {
                        Text("5h").frame(width: OverlayMetrics.slotWidth)
                    }
                    if showsWeekColumn {
                        Text("1w").frame(width: OverlayMetrics.slotWidth)
                    }
                    if showsMonthColumn {
                        Text("1mo").frame(width: OverlayMetrics.slotWidth)
                    }
                }
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))

                ForEach(meters) { meter in
                    HStack(spacing: 0) {
                        Text(meter.name)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(width: OverlayMetrics.nameWidth, alignment: .leading)
                        if meter.showsFiveHour {
                            MeterBar(fraction: meter.fiveHour.fraction, alert: meter.fiveHour.alert)
                                .frame(width: OverlayMetrics.slotWidth)
                            MeterBar(fraction: meter.week.fraction, alert: meter.week.alert)
                                .frame(width: OverlayMetrics.slotWidth)
                            if showsMonthColumn {
                                Color.clear.frame(width: OverlayMetrics.slotWidth, height: 18)
                            }
                        } else {
                            if showsFiveHourColumn {
                                Color.clear.frame(width: OverlayMetrics.slotWidth, height: 18)
                            }
                            if showsWeekColumn {
                                Color.clear.frame(width: OverlayMetrics.slotWidth, height: 18)
                            }
                            MeterBar(fraction: meter.week.fraction, alert: meter.week.alert)
                                .frame(width: OverlayMetrics.slotWidth)
                        }
                    }
                    .opacity(meter.opacity)
                    .help(meter.hint)
                    .accessibilityLabel(meter.hint)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .fixedSize()
    }

    private var meters: [UsageMeter] {
        model.snapshot.providers
            .filter { model.isEnabled($0.id) }
            .map { UsageMeter($0, language: model.language) }
    }

    private var showsFiveHourColumn: Bool {
        meters.contains(where: \.showsFiveHour)
    }

    private var showsWeekColumn: Bool {
        meters.contains(where: \.showsFiveHour)
    }

    private var showsMonthColumn: Bool {
        meters.contains { !$0.showsFiveHour }
    }
}

private struct MeterSlot {
    var fraction: Double?
    var alert: Bool
}

private struct UsageMeter: Identifiable {
    var id: ProviderID
    var name: String
    var opacity: Double
    var showsFiveHour: Bool
    var fiveHour: MeterSlot
    var week: MeterSlot
    var hint: String

    init(_ provider: ProviderSnapshot, language: AppLanguage) {
        id = provider.id
        name = provider.displayName
        showsFiveHour = provider.id != .cursor
        let showsReading = provider.status == .ok || provider.status == .stale
        let fiveWindow = provider.windows.first { $0.kind == .fiveHour }
        let weeklyWindow = provider.windows.first { $0.kind == .weekly }
        let planWindow = provider.windows.first { $0.kind == .billingPlan }
        let weekWindow = weeklyWindow ?? planWindow
        // An old ok value (stopped host, or Desktop not running) looks the same as stale.
        let fresh = provider.status == .ok && !WidgetLayout.isDimmed(provider, now: Date())
        fiveHour = Self.slot(fiveWindow, visible: showsReading, alert: fresh)
        week = Self.slot(weekWindow, visible: showsReading, alert: fresh)
        let weekIsPlan = weeklyWindow == nil && planWindow != nil
        switch provider.status {
        case .notInstalled:
            opacity = 0.35
            hint = language.pick(ja: "\(name)、未インストール", en: "\(name), not installed")
        case .unsupported:
            opacity = 0.35
            hint = language.pick(ja: "\(name)、対象外", en: "\(name), unsupported")
        case .needsLogin:
            opacity = 0.45
            hint = language.pick(ja: "\(name)、再ログインが必要", en: "\(name), sign in again")
        case .notConfigured:
            opacity = 0.45
            hint = language.pick(ja: "\(name)、未取得", en: "\(name), no data yet")
        case .stale, .ok where !fresh:
            opacity = 0.55
            hint = Self.readingHint(name: name, five: fiveWindow, week: weekWindow, weekIsPlan: weekIsPlan, language: language, showsFiveHour: showsFiveHour)
                + language.pick(ja: "前回の値。", en: " Previous value.")
        case .ok:
            opacity = 1
            hint = Self.readingHint(name: name, five: fiveWindow, week: weekWindow, weekIsPlan: weekIsPlan, language: language, showsFiveHour: showsFiveHour)
        }
    }

    private static func slot(_ window: UsageWindow?, visible: Bool, alert: Bool) -> MeterSlot {
        guard visible, let window else { return MeterSlot(fraction: nil, alert: false) }
        if window.label == "∞" { return MeterSlot(fraction: 0, alert: false) }
        return MeterSlot(
            fraction: window.usedFraction,
            alert: alert && window.usedFraction >= Constants.usageRedThreshold
        )
    }

    private static func readingHint(
        name: String,
        five: UsageWindow?,
        week: UsageWindow?,
        weekIsPlan: Bool,
        language: AppLanguage,
        showsFiveHour: Bool
    ) -> String {
        let weekTitle = weekIsPlan
            ? language.pick(ja: "月次", en: "Monthly")
            : language.pick(ja: "週次", en: "Weekly")
        let weekText = "\(weekTitle)は\(phrase(week, language: language))。"
        guard showsFiveHour else {
            return language.pick(ja: "\(name)。\(weekText)", en: "\(name). \(weekTitle) is \(phrase(week, language: language)).")
        }
        return language.pick(
            ja: "\(name)。5時間は\(phrase(five, language: language))。\(weekText)",
            en: "\(name). 5h is \(phrase(five, language: language)). \(weekTitle) is \(phrase(week, language: language))."
        )
    }

    private static func phrase(_ window: UsageWindow?, language: AppLanguage) -> String {
        guard let window else { return language.pick(ja: "枠がありません", en: "no window") }
        if window.label == "∞" { return language.pick(ja: "上限なし", en: "unlimited") }
        if window.usedFraction >= Constants.usageRedThreshold { return language.pick(ja: "枠が残り少ない", en: "nearly used up") }
        if window.usedFraction >= Constants.usageOrangeThreshold { return language.pick(ja: "枠が減ってきている", en: "getting low") }
        return language.pick(ja: "余裕がある", en: "plenty left")
    }
}

private struct MeterBar: View {
    var fraction: Double?
    var alert: Bool
    @State private var pulse = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Capsule()
                .fill(.white.opacity(0.16))
            if let fraction, let height = Self.fillHeight(fraction) {
                Capsule()
                    .fill(Self.color(fraction))
                    .frame(height: height)
                    .opacity(alert && pulse ? 0.35 : 1)
            }
        }
        .frame(width: 8, height: 18)
        .animation(alert ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : nil, value: pulse)
        .onAppear { pulse = true }
    }

    /// Do not paint a bar that rounds to 0%. A 2pt minimum made unused look slightly used.
    private static func fillHeight(_ fraction: Double) -> CGFloat? {
        guard (fraction * 100).rounded() >= 1 else { return nil }
        return max(2, 18 * fraction)
    }

    private static func color(_ fraction: Double) -> Color {
        if fraction >= Constants.usageRedThreshold { return .red }
        if fraction >= Constants.usageOrangeThreshold { return .orange }
        return .white
    }
}
