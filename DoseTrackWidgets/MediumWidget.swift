// DoseTrackWidgets/MediumWidget.swift
import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Timeline Entry

struct MediumWidgetEntry: TimelineEntry {
    let date: Date
    /// Outstanding (not-yet-taken) doses only, already capped to what the current widget
    /// family (medium vs. large) can comfortably fit — WidgetKit doesn't support scrolling
    /// inside a widget at all (an Apple platform restriction, not a choice made here), so a
    /// bigger widget size is the correct substitute for "see more" rather than a scroll gesture.
    let outstanding: [WidgetDoseEntry]
    /// Total outstanding count BEFORE capping, so the view can show "+N more".
    let outstandingTotal: Int
    let takenCount: Int
    let totalCount: Int
    /// Interactive "mark taken" only writes to the signed-in user's own store (see
    /// MarkDoseTakenIntent) — when showing an overseen patient's doses instead, rows render
    /// read-only rather than offer a checkbox whose tap wouldn't actually do anything useful.
    var isOwnAccount: Bool = true
}

// MARK: - Timeline Provider

struct MediumWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> MediumWidgetEntry {
        MediumWidgetEntry(date: Date(), outstanding: [], outstandingTotal: 0, takenCount: 0, totalCount: 0, isOwnAccount: true)
    }

    func snapshot(for configuration: SelectDoseAccountIntent, in context: Context) async -> MediumWidgetEntry {
        makeEntry(for: configuration, family: context.family)
    }

    func timeline(for configuration: SelectDoseAccountIntent, in context: Context) async -> Timeline<MediumWidgetEntry> {
        let entry = makeEntry(for: configuration, family: context.family)
        // Refresh at the next outstanding dose's time, or fall back to a short interval so the
        // widget keeps catching up even on days with no more doses due.
        let reloadDate = entry.outstanding.first?.scheduledAt ?? Date(timeIntervalSinceNow: 900)
        return Timeline(entries: [entry], policy: .after(reloadDate))
    }

    private func makeEntry(for configuration: SelectDoseAccountIntent, family: WidgetFamily) -> MediumWidgetEntry {
        let accountId = configuration.storageAccountId
        let allEntries = WidgetDataProvider.shared.todayEntries(for: accountId)
        let taken = allEntries.filter { $0.isTaken }.count
        let outstandingAll = allEntries.filter { !$0.isTaken }
        // Conservative row caps chosen to comfortably fit within each family's content area
        // without needing (unsupported) scrolling — a systemLarge widget can show roughly
        // double what systemMedium can.
        let cap = family == .systemLarge ? 8 : 3
        return MediumWidgetEntry(
            date: Date(),
            outstanding: Array(outstandingAll.prefix(cap)),
            outstandingTotal: outstandingAll.count,
            takenCount: taken,
            totalCount: allEntries.count,
            isOwnAccount: accountId == nil
        )
    }
}

// MARK: - View

struct MediumWidgetView: View {
    var entry: MediumWidgetEntry

    private var allDone: Bool { entry.totalCount > 0 && entry.takenCount == entry.totalCount }
    private var hiddenCount: Int { max(entry.outstandingTotal - entry.outstanding.count, 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if entry.totalCount == 0 {
                Spacer()
                Text("No doses today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            } else if allDone {
                Spacer()
                Label("All doses taken today", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
                Spacer()
            } else {
                // Outstanding doses only — a fully-taken row mixed in with pending ones was
                // exactly what made the old design read as "halfway between a few options."
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(entry.outstanding) { dose in
                        MediumDoseRow(dose: dose, isInteractive: entry.isOwnAccount)
                        if dose.id != entry.outstanding.last?.id {
                            Divider().padding(.vertical, 2)
                        }
                    }
                    if hiddenCount > 0 {
                        Text("+\(hiddenCount) more — open DoseTrack")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) {
            Color(UIColor.systemBackground)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            DoseProgressRing(taken: entry.takenCount, total: entry.totalCount, lineWidth: 3)
                .frame(width: 20, height: 20)
            Text(allDone ? "All done!" : "\(entry.takenCount) of \(entry.totalCount) taken today")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
        }
    }
}

private struct MediumDoseRow: View {
    let dose: WidgetDoseEntry
    /// False when showing an overseen patient's doses — MarkDoseTakenIntent only ever writes to
    /// the signed-in user's own store, so a checkbox here would silently do nothing useful.
    var isInteractive: Bool = true

    var body: some View {
        HStack(spacing: 8) {
            if isInteractive {
                // Interactive checkbox — marks taken without opening the app
                Button(intent: MarkDoseTakenIntent(
                    medicationId: dose.medicationId,
                    scheduleId: dose.scheduleId,
                    scheduledAt: dose.scheduledAt
                )) {
                    Image(systemName: "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }

            Circle()
                .fill(Color(hex: dose.colorHex))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(dose.medicationName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Text(dose.dosage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(dose.scheduledAt, style: .time)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 1)
    }
}

// MARK: - Widget Definition

struct MediumWidget: Widget {
    let kind: String = "MediumWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectDoseAccountIntent.self, provider: MediumWidgetProvider()) { entry in
            MediumWidgetView(entry: entry)
        }
        .configurationDisplayName("Outstanding Doses")
        .description("Shows only what's still due today, with a bigger size available for more at once. Mark doses taken without opening the app.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
