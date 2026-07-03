// DoseTrackWidgets/MediumWidget.swift
import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Timeline Entry

struct MediumWidgetEntry: TimelineEntry {
    let date: Date
    let entries: [WidgetDoseEntry]
    let takenCount: Int
    let totalCount: Int
}

// MARK: - Timeline Provider

struct MediumWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> MediumWidgetEntry {
        MediumWidgetEntry(date: Date(), entries: [], takenCount: 0, totalCount: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (MediumWidgetEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MediumWidgetEntry>) -> Void) {
        let entry = makeEntry()
        let nextDue = entry.entries.first { !$0.isTaken }?.scheduledAt
        let reloadDate = nextDue ?? Date(timeIntervalSinceNow: 3600)
        completion(Timeline(entries: [entry], policy: .after(reloadDate)))
    }

    private func makeEntry() -> MediumWidgetEntry {
        let allEntries = WidgetDataProvider.shared.todayEntries()
        let taken = allEntries.filter { $0.isTaken }.count
        return MediumWidgetEntry(
            date: Date(),
            entries: Array(allEntries.prefix(5)),  // Show up to 5 rows in medium widget
            takenCount: taken,
            totalCount: allEntries.count
        )
    }
}

// MARK: - View

struct MediumWidgetView: View {
    var entry: MediumWidgetEntry

    private var completionFraction: Double {
        guard entry.totalCount > 0 else { return 0 }
        return min(Double(entry.takenCount) / Double(entry.totalCount), 1.0)
    }

    private var allDone: Bool { entry.takenCount == entry.totalCount && entry.totalCount > 0 }

    var body: some View {
        HStack(spacing: 12) {
            // Milli progress column
            VStack(spacing: 4) {
                MilliProgressView(fraction: completionFraction)
                    .frame(width: 56, height: 56)
                if allDone {
                    Text("Done! 🎉")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.green)
                } else {
                    Text("\(entry.takenCount) of \(entry.totalCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.primary)
                }
            }
            .frame(width: 60)

            // Dose list
            VStack(alignment: .leading, spacing: 0) {
                Text(allDone ? "All done today!" : "medications taken today")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)

                if entry.entries.isEmpty {
                    Spacer()
                    Text("No doses today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    ForEach(entry.entries, id: \.medicationId) { dose in
                        MediumDoseRow(dose: dose)
                        if dose.medicationId != entry.entries.last?.medicationId {
                            Divider().padding(.vertical, 2)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) {
            Color(UIColor.systemBackground)
        }
    }
}

private struct MediumDoseRow: View {
    let dose: WidgetDoseEntry

    var body: some View {
        HStack(spacing: 8) {
            // Interactive checkbox — marks taken without opening the app
            Button(intent: MarkDoseTakenIntent(
                medicationId: dose.medicationId,
                scheduleId: dose.scheduleId,
                scheduledAt: dose.scheduledAt
            )) {
                Image(systemName: dose.isTaken ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(dose.isTaken ? .green : .secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .disabled(dose.isTaken)

            Circle()
                .fill(Color(hex: dose.colorHex))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(dose.medicationName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .strikethrough(dose.isTaken)
                    .foregroundStyle(dose.isTaken ? .secondary : .primary)
                Text(dose.dosage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(dose.scheduledAt, style: .time)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Widget Definition

struct MediumWidget: Widget {
    let kind: String = "MediumWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MediumWidgetProvider()) { entry in
            MediumWidgetView(entry: entry)
        }
        .configurationDisplayName("Today's Doses")
        .description("See today's medications and mark them taken without opening the app.")
        .supportedFamilies([.systemMedium])
    }
}
