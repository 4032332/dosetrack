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

// MARK: - Milli Progress View

/// Shows the Milli mascot image transitioning from greyscale to full colour
/// as a proportion of today's doses are completed.
struct MilliProgressView: View {
    let fraction: Double   // 0.0 → 1.0

    var body: some View {
        ZStack {
            // Greyscale base layer (always full image)
            if let img = UIImage(named: "OnboardingWelcome") {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .grayscale(1.0)
                    .opacity(0.55)
            } else {
                milliPlaceholder
            }

            // Coloured overlay — revealed from bottom up based on completion fraction
            if fraction > 0 {
                if let img = UIImage(named: "OnboardingWelcome") {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .mask(alignment: .bottom) {
                            GeometryReader { geo in
                                Rectangle()
                                    .frame(height: geo.size.height * fraction)
                                    .frame(maxHeight: .infinity, alignment: .bottom)
                            }
                        }
                } else {
                    milliPlaceholder
                        .mask(alignment: .bottom) {
                            GeometryReader { geo in
                                Rectangle()
                                    .frame(height: geo.size.height * fraction)
                                    .frame(maxHeight: .infinity, alignment: .bottom)
                            }
                        }
                }
            }
        }
    }

    private var milliPlaceholder: some View {
        ZStack {
            Circle().fill(Color(red: 0.95, green: 0.96, blue: 1.0))
            Text("💊").font(.system(size: 32))
        }
    }
}

// MARK: - Widget View

struct SmallWidgetView: View {
    var entry: SmallWidgetEntry

    private var completionFraction: Double {
        guard entry.totalCount > 0 else { return 0 }
        return min(Double(entry.takenCount) / Double(entry.totalCount), 1.0)
    }

    private var allDone: Bool { entry.takenCount == entry.totalCount && entry.totalCount > 0 }

    var body: some View {
        VStack(spacing: 4) {
            MilliProgressView(fraction: completionFraction)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.top, 8)

            if allDone {
                Text("All done! 🎉")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green)
            } else if entry.totalCount > 0 {
                Text("\(entry.takenCount)/\(entry.totalCount)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                +
                Text(" today")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("No doses")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 8)
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
        .configurationDisplayName("Milli Progress")
        .description("Shows Milli gaining colour as you take your medications. Caregivers can choose whose medications to show.")
        .supportedFamilies([.systemSmall])
    }
}
