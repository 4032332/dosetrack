// DoseTrackWidgets/LockScreenWidget.swift
import WidgetKit
import SwiftUI

// Reuses SmallWidgetEntry and WidgetDataProvider — same data shape.

struct LockScreenWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> SmallWidgetEntry {
        SmallWidgetEntry(date: Date(), takenCount: 0, totalCount: 0, nextDose: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (SmallWidgetEntry) -> Void) {
        let entries = WidgetDataProvider.shared.todayEntries()
        completion(SmallWidgetEntry(
            date: Date(),
            takenCount: entries.filter(\.isTaken).count,
            totalCount: entries.count,
            nextDose: WidgetDataProvider.shared.nextDose()
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SmallWidgetEntry>) -> Void) {
        let entries = WidgetDataProvider.shared.todayEntries()
        let nextDose = WidgetDataProvider.shared.nextDose()
        let entry = SmallWidgetEntry(
            date: Date(),
            takenCount: entries.filter(\.isTaken).count,
            totalCount: entries.count,
            nextDose: nextDose
        )
        let reloadDate = nextDose?.scheduledAt ?? Date(timeIntervalSinceNow: 3600)
        completion(Timeline(entries: [entry], policy: .after(reloadDate)))
    }
}

// MARK: - Lock screen view (rectangular accessory)

struct LockScreenWidgetView: View {
    var entry: SmallWidgetEntry

    var body: some View {
        if let dose = entry.nextDose {
            HStack(spacing: 6) {
                Image(systemName: "pills.fill")
                    .font(.caption2)
                VStack(alignment: .leading, spacing: 1) {
                    Text(dose.medicationName)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                    Text(dose.scheduledAt, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .containerBackground(for: .widget) { Color.clear }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle")
                    .font(.caption2)
                Text("All doses taken")
                    .font(.caption2)
            }
            .containerBackground(for: .widget) { Color.clear }
        }
    }
}

// MARK: - Widget Definition

struct LockScreenWidget: Widget {
    let kind: String = "LockScreenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LockScreenWidgetProvider()) { entry in
            LockScreenWidgetView(entry: entry)
        }
        .configurationDisplayName("Next Dose")
        .description("Shows your next medication on the lock screen.")
        .supportedFamilies([.accessoryRectangular])
    }
}
