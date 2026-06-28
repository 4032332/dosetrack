// DoseTrackWidgets/SmallWidget.swift
import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct SmallWidgetEntry: TimelineEntry {
    let date: Date
    let nextDose: WidgetDoseEntry?
}

// MARK: - Timeline Provider

struct SmallWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> SmallWidgetEntry {
        SmallWidgetEntry(date: Date(), nextDose: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (SmallWidgetEntry) -> Void) {
        completion(SmallWidgetEntry(date: Date(), nextDose: WidgetDataProvider.shared.nextDose()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SmallWidgetEntry>) -> Void) {
        let nextDose = WidgetDataProvider.shared.nextDose()
        let entry = SmallWidgetEntry(date: Date(), nextDose: nextDose)

        // Reload exactly when the next dose is due (or in 1 hour if nothing pending)
        let reloadDate = nextDose?.scheduledAt ?? Date(timeIntervalSinceNow: 3600)
        let timeline = Timeline(entries: [entry], policy: .after(reloadDate))
        completion(timeline)
    }
}

// MARK: - View

struct SmallWidgetView: View {
    var entry: SmallWidgetEntry

    var body: some View {
        if let dose = entry.nextDose {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: dose.colorHex))
                        .frame(width: 10, height: 10)
                    Text("Next Dose")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(dose.medicationName)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                Text(dose.dosage)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(dose.scheduledAt, style: .relative)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(for: .widget) {
                Color(UIColor.systemBackground)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                Text("All done!")
                    .font(.caption.weight(.semibold))
                Text("No more doses today")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .containerBackground(for: .widget) {
                Color(UIColor.systemBackground)
            }
        }
    }
}

// MARK: - Widget Definition

struct SmallWidget: Widget {
    let kind: String = "SmallWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SmallWidgetProvider()) { entry in
            SmallWidgetView(entry: entry)
        }
        .configurationDisplayName("Next Dose")
        .description("Shows your next upcoming dose with a countdown timer.")
        .supportedFamilies([.systemSmall])
    }
}
