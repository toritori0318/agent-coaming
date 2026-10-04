import CoamingCore
import SwiftUI
import WidgetKit

struct CoamingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: UsageEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                SmallUsageView(snapshot: entry.snapshot, now: entry.date)
            default:
                MediumUsageView(snapshot: entry.snapshot, now: entry.date)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

private struct SmallUsageView: View {
    var snapshot: Snapshot
    var now: Date

    var body: some View {
        let model = WidgetLayout.small(snapshot: snapshot, now: now)
        if let message = model.emptyMessage {
            Text(message)
                .font(.system(.caption, design: .rounded))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(model.rows) { row in
                    HStack(spacing: 4) {
                        Text(row.name)
                            .frame(width: 52, alignment: .leading)
                        Spacer(minLength: 2)
                        Text(row.primary)
                            .frame(width: 36, alignment: .trailing)
                        if let secondary = row.secondary {
                            Text(secondary)
                                .frame(width: 36, alignment: .trailing)
                        }
                    }
                    .opacity(row.dimmed ? 0.45 : 1)
                    if row.dimmed, let age = row.age {
                        Text(age)
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if let footer = model.footer {
                    Text(footer)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(.caption, design: .rounded))
            .monospacedDigit()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct MediumUsageView: View {
    var snapshot: Snapshot
    var now: Date

    var body: some View {
        let rows = WidgetLayout.medium(snapshot: snapshot, now: now)
        if rows.isEmpty {
            Text(WidgetLayout.emptyMessage)
                .font(.system(.caption, design: .rounded))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(rows) { row in
                    HStack(spacing: 6) {
                        Text(row.name)
                            .frame(width: 52, alignment: .leading)
                        Text(row.plan)
                            .frame(width: 58, alignment: .leading)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(row.windowLabel)
                            .frame(width: 62, alignment: .trailing)
                            .lineLimit(1)
                        if row.showsBar, let fraction = row.fraction {
                            UsageBar(fraction: fraction)
                                .frame(width: 52, height: 6)
                        } else {
                            Color.clear.frame(width: 52, height: 6)
                        }
                        Text(row.valueText)
                            .frame(width: 40, alignment: .trailing)
                        // For an old value, show its age instead of the reset time.
                        if row.dimmed, let age = row.age {
                            Text(age)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .foregroundStyle(.secondary)
                        } else if let resets = row.resetsAt, resets > now {
                            Text(formatResetRemaining(resets, now: now, locale: .current))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        } else {
                            Spacer(minLength: 0)
                        }
                    }
                    .opacity(row.dimmed ? 0.45 : 1)
                }
            }
            .font(.system(size: 11, weight: .regular, design: .rounded))
            .monospacedDigit()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct UsageBar: View {
    var fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(color)
                    .frame(width: geo.size.width * CGFloat(min(1, max(0, fraction))))
            }
        }
    }

    private var color: Color {
        if usageIsCritical(fraction) { return .red }
        if usageIsWarning(fraction) { return .orange }
        return .primary
    }
}
