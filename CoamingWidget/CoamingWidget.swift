import CoamingCore
import SwiftUI
import WidgetKit

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot
}

struct CoamingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AgentCoaming", provider: UsageTimeline()) { entry in
            CoamingWidgetView(entry: entry)
        }
        .configurationDisplayName("Agent Coaming")
        #if COAMING_CURSOR
        .description("Usage for Claude, Codex, and Cursor")
        #else
        .description("Usage for Claude and Codex")
        #endif
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct UsageTimeline: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), snapshot: GallerySnapshot.make())
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (UsageEntry) -> Void) {
        let now = Date()
        completion(UsageEntry(date: now, snapshot: SnapshotStore.live().read() ?? GallerySnapshot.make(now: now)))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<UsageEntry>) -> Void) {
        let now = Date()
        let snapshot = SnapshotStore.live().read() ?? Snapshot.waiting(now: now)
        let resets = snapshot.providers.flatMap(\.windows).compactMap(\.resetsAt).filter { $0 > now }
        let horizon = now.addingTimeInterval(Constants.widgetTimelineMax)
        let next = resets.min().map { min($0, horizon) } ?? horizon
        completion(Timeline(entries: [UsageEntry(date: now, snapshot: snapshot)], policy: .after(next)))
    }
}

private enum GallerySnapshot {
    static func make(now: Date = Date()) -> Snapshot {
        let primary = UsageWindow(kind: .fiveHour, label: "5h", usedFraction: 0.37, resetsAt: now.addingTimeInterval(3600))
        let secondary = UsageWindow(kind: .weekly, label: "Weekly", usedFraction: 0.12, resetsAt: now.addingTimeInterval(86_400))
        var providers = [
            ProviderSnapshot(id: .claude, displayName: "Claude", status: .ok, planLabel: "Max 5x", windows: [primary, secondary], fetchedAt: now, staleReason: nil),
            ProviderSnapshot(id: .codex, displayName: "Codex", status: .ok, planLabel: "Codex plus", windows: [primary, secondary], fetchedAt: now, staleReason: nil),
        ]
        // The gallery shows Cursor only when this extension was built with COAMING_CURSOR. See ProviderID.included.
        #if COAMING_CURSOR
        providers.append(ProviderSnapshot(
            id: .cursor,
            displayName: "Cursor",
            status: .ok,
            planLabel: "Pro",
            windows: [
                UsageWindow(kind: .billingPlan, label: "Plan", usedFraction: 0.37, resetsAt: now.addingTimeInterval(86_400)),
                UsageWindow(kind: .billingOnDemand, label: "On-demand", usedFraction: 0.12, resetsAt: now.addingTimeInterval(86_400)),
            ],
            fetchedAt: now,
            staleReason: nil
        ))
        #endif
        return Snapshot(
            schemaVersion: Snapshot.currentSchemaVersion,
            generatedAt: now,
            providers: providers
        )
    }
}

@main
struct CoamingWidgetBundle: WidgetBundle {
    var body: some Widget {
        CoamingWidget()
    }
}
