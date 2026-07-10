// DoseTrackWidgets/SmallWidget.swift
import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Timeline Entry

struct SmallWidgetEntry: TimelineEntry {
    let date: Date
    let takenCount: Int
    let totalCount: Int
    let nextDose: WidgetDoseEntry?
}

// MARK: - Timeline Provider

struct SmallWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SmallWidgetEntry {
        SmallWidgetEntry(date: Date(), takenCount: 2, totalCount: 5, nextDose: nil)
    }

    func snapshot(for configuration: SelectDoseAccountIntent, in context: Context) async -> SmallWidgetEntry {
        makeEntry(for: configuration)
    }

    func timeline(for configuration: SelectDoseAccountIntent, in context: Context) async -> Timeline<SmallWidgetEntry> {
        let entry = makeEntry(for: configuration)
        // Refresh at the next dose time, or fall back to a short interval so the widget keeps
        // catching up even on days with no more doses due (rather than sitting stale for an hour).
        let reloadDate = entry.nextDose?.scheduledAt ?? Date(timeIntervalSinceNow: 900)
        return Timeline(entries: [entry], policy: .after(reloadDate))
    }

    private func makeEntry(for configuration: SelectDoseAccountIntent) -> SmallWidgetEntry {
        let accountId = configuration.storageAccountId
        let entries = WidgetDataProvider.shared.todayEntries(for: accountId)
        return SmallWidgetEntry(
            date: Date(),
            takenCount: entries.filter(\.isTaken).count,
            totalCount: entries.count,
            nextDose: WidgetDataProvider.shared.nextDose(for: accountId)
        )
    }
}

// MARK: - Progress Ring

/// Small circular "X of Y taken" indicator, shared visual language with the History tab's
/// AdherenceSummaryRow ring rather than a bespoke widget-only element.
struct DoseProgressRing: View {
    let taken: Int
    let total: Int
    var lineWidth: CGFloat = 3

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return min(Double(taken) / Double(total), 1.0)
    }
    private var allDone: Bool { total > 0 && taken == total }

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(allDone ? Color.green : Color.accentColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Widget View

struct SmallWidgetView: View {
    var entry: SmallWidgetEntry

    private var allDone: Bool { entry.totalCount > 0 && entry.takenCount == entry.totalCount }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "pills.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                ZStack {
                    DoseProgressRing(taken: entry.takenCount, total: entry.totalCount)
                    if entry.totalCount > 0 {
                        Text("\(entry.takenCount)/\(entry.totalCount)")
                            .font(.system(size: 9, weight: .bold))
                    }
                }
                .frame(width: 30, height: 30)
            }

            Spacer(minLength: 4)

            // Shows what's still OUTSTANDING — the whole point of checking this widget — rather
            // than a decorative mascot that said nothing about what's actually due.
            if entry.totalCount == 0 {
                Text("No doses today")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if allDone {
                Label("All done!", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            } else if let next = entry.nextDose {
                Text("Next up")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(next.medicationName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(next.scheduledAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) {
            Color(UIColor.systemBackground)
        }
    }
}

// MARK: - Widget Definition

struct SmallWidget: Widget {
    let kind: String = "SmallWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectDoseAccountIntent.self, provider: SmallWidgetProvider()) { entry in
            SmallWidgetView(entry: entry)
        }
        .configurationDisplayName("Next Dose")
        .description("Shows your next outstanding dose and today's progress at a glance. Caregivers can choose whose medications to show.")
        .supportedFamilies([.systemSmall])
    }
}
