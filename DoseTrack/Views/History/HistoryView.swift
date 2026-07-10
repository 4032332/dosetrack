// DoseTrack/Views/History/HistoryView.swift
import SwiftUI

struct HistoryView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @EnvironmentObject private var caregiverManager: CaregiverManager
    @EnvironmentObject private var activeAccount: ActiveAccountContext
    @StateObject private var viewModel = HistoryViewModel(
        context: PersistenceController.shared.viewContext
    )

    @State private var showingCalendar = false
    @State private var calendarMonth = Date()
    @State private var showingExportSheet = false
    @State private var exportItem: ExportItem? = nil
    @State private var showingPaywall = false
    @State private var daySelection: DaySelection? = nil
    @Binding var showingAccountSwitcher: Bool

    init(showingAccountSwitcher: Binding<Bool> = .constant(false)) {
        self._showingAccountSwitcher = showingAccountSwitcher
    }

    var body: some View {
        NavigationStack {
            // Plain ScrollView + styled cards, NOT List. SwiftUI's List is UICollectionView-
            // backed on modern iOS, and embedding a self-sizing custom grid (CalendarView's
            // LazyVGrid) or a Swift Charts view directly inside a List row is a known-unreliable
            // combination — the List row's own sizing pass and the embedded content's internal
            // layout pass can end up invalidating each other in a loop. That's exactly the
            // reproducible crash reported on a real device (_UICollectionViewFeedbackLoop,
            // _updateVisibleCellsNow: appearing twice in its own stack — UIKit's own internal
            // anti-infinite-loop safety net firing). A fixed day-count in the calendar grid
            // (previous attempt) reduced but didn't eliminate the risk, since the underlying
            // List+self-sizing-grid combination is the real problem. ScrollView has no such
            // collection-view backing, so this removes the entire crash class rather than
            // continuing to patch symptoms of it.
            ScrollView {
                VStack(spacing: 16) {
                    // Range picker
                    HistoryCard {
                        Picker("Range", selection: $viewModel.rangeMode) {
                            ForEach(DateRangeMode.allCases, id: \.self) {
                                Text($0.rawValue).tag($0)
                            }
                        }
                        .pickerStyle(.segmented)

                        if viewModel.rangeMode == .custom {
                            CollapsibleDatePicker(
                                label: "From",
                                systemImage: "calendar",
                                date: $viewModel.customStart,
                                range: ...viewModel.customEnd
                            )
                            CollapsibleDatePicker(
                                label: "To",
                                systemImage: "calendar",
                                date: $viewModel.customEnd,
                                range: ...Date()
                            )
                        }
                    }

                    // Overall adherence
                    HistoryCard {
                        AdherenceSummaryRow(percent: viewModel.overallPercent)
                    }

                    // Chart vs calendar toggle
                    HistoryCard {
                        // Full-width segmented control (matching the Range picker above it)
                        // rather than a cramped fixed 120pt width next to a redundant duplicate
                        // text label — the old layout truncated "Calendar" to "Calen...".
                        Picker("View", selection: $showingCalendar) {
                            Label("Chart", systemImage: "chart.bar.fill").tag(false)
                            Label("Calendar", systemImage: "calendar").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .animation(nil, value: showingCalendar)

                        if showingCalendar {
                            CalendarView(days: viewModel.dayAdherences, displayedMonth: $calendarMonth,
                                         onSelectDay: { day in daySelection = DaySelection(day: day) })
                                .padding(.vertical, 4)
                        } else {
                            if viewModel.dayAdherences.isEmpty {
                                ContentUnavailableView(
                                    "No data",
                                    systemImage: "chart.bar",
                                    description: Text("Log doses to see adherence trends")
                                )
                                .frame(height: 180)
                            } else {
                                AdherenceChartView(days: viewModel.dayAdherences)
                                    .padding(.vertical, 4)
                            }
                        }
                    }

                    // Per-medication breakdown — tap through to each medication's logged doses
                    if !viewModel.medicationAdherences.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HistorySectionHeader("By Medication")
                            HistoryCard(spacing: 14) {
                                ForEach(Array(viewModel.medicationAdherences.enumerated()), id: \.element.id) { index, item in
                                    NavigationLink {
                                        HistoryEntriesView(
                                            title: item.name,
                                            showMedicationName: false,
                                            entries: viewModel.entries(forMedication: item.id)
                                        )
                                    } label: {
                                        MedicationAdherenceRow(item: item)
                                    }
                                    .buttonStyle(.plain)
                                    if index != viewModel.medicationAdherences.count - 1 {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }

                    // Legend
                    HistoryCard {
                        HStack(spacing: 16) {
                            LegendDot(color: .green, label: "≥90%")
                            LegendDot(color: .orange, label: "50–89%")
                            LegendDot(color: .red, label: "<50%")
                            LegendDot(color: .gray.opacity(0.4), label: "No doses")
                        }
                        .font(.caption)
                    }

                    // Disclaimer
                    Text("DoseTrack is a reminder tool, not medical advice. Always follow your healthcare provider's instructions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollIndicators(.visible)
            .contentMargins(.bottom, 32, for: .scrollContent)
            .navigationTitle("History")
            .toolbar {
                if !caregiverManager.overseenPatients.isEmpty {
                    ToolbarItem(placement: .principal) {
                        AccountSwitcherPill(isPresented: $showingAccountSwitcher)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            exportCSV()
                        } label: {
                            Label("Export CSV", systemImage: "doc.text")
                        }

                        Button {
                            if subscriptionManager.isProSubscriber {
                                exportPDF()
                            } else {
                                showingPaywall = true
                            }
                        } label: {
                            Label("Adherence Report (PDF)", systemImage: "doc.richtext")
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
                    .environmentObject(subscriptionManager)
            }
            .sheet(item: $exportItem) { item in
                ActivityView(activityItems: [item.url])
            }
            .sheet(item: $daySelection) { sel in
                NavigationStack {
                    HistoryEntriesView(
                        title: sel.day.formatted(date: .complete, time: .omitted),
                        showMedicationName: true,
                        entries: viewModel.entries(forDay: sel.day)
                    )
                }
            }
            .refreshable {
                viewModel.refresh()
            }
        }
        .onAppear {
            viewModel.updateContext(context)
        }
        .onChange(of: context) { _, newContext in
            viewModel.updateContext(newContext)
        }
    }

    // MARK: - Export

    private func exportCSV() {
        let interval = DateInterval(
            start: Calendar.current.startOfDay(for: viewModel.effectiveStart),
            end: Calendar.current.date(
                byAdding: .day, value: 1,
                to: Calendar.current.startOfDay(for: viewModel.effectiveEnd)
            ) ?? viewModel.effectiveEnd
        )
        let logs = ExportManager.shared.fetchAllLogs(context: context, in: interval)
        let data = ExportManager.shared.generateCSV(from: logs, dateRange: interval)
        let filename = "dosetrack-export-\(Date().formatted(.dateTime.year().month().day())).csv"
        if let url = ExportManager.shared.writeTemporaryFile(data: data, filename: filename) {
            exportItem = ExportItem(url: url)
        }
    }

    private func exportPDF() {
        let interval = DateInterval(
            start: Calendar.current.startOfDay(for: viewModel.effectiveStart),
            end: Calendar.current.date(
                byAdding: .day, value: 1,
                to: Calendar.current.startOfDay(for: viewModel.effectiveEnd)
            ) ?? viewModel.effectiveEnd
        )
        let logs = ExportManager.shared.fetchAllLogs(context: context, in: interval)
        let medRequest = Medication.fetchRequest()
        medRequest.predicate = NSPredicate(format: "isActive == YES")
        let meds = (try? context.fetch(medRequest)) ?? []
        // A caregiver viewing an overseen patient must get that patient's name on the report,
        // not their own — UserDefaults["patientName"] is always the signed-in user's own
        // profile field, regardless of which account's data is currently being viewed.
        let patientName = activeAccount.isViewingOtherAccount
            ? activeAccount.activeDisplayName
            : (UserDefaults.standard.string(forKey: "patientName") ?? "")
        let data = ReportGenerator.shared.generatePDF(
            logs: logs, medications: meds, dateRange: interval, patientName: patientName
        )
        let filename = "dosetrack-report-\(Date().formatted(.dateTime.year().month().day())).pdf"
        if let url = ExportManager.shared.writeTemporaryFile(data: data, filename: filename) {
            exportItem = ExportItem(url: url)
        }
    }
}

// MARK: - Supporting types

/// Wraps an on-disk export file for `.sheet(item:)` presentation. Carries a file URL (not raw
/// Data) so `UIActivityViewController` shares a correctly-named, correctly-typed document.
struct ExportItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// Identifiable wrapper so a tapped calendar day can drive `.sheet(item:)`.
struct DaySelection: Identifiable {
    let id = UUID()
    let day: Date
}

// MARK: - History detail (per medication / per day)

/// Lists individual logged doses with the time each was actually taken/skipped/missed.
/// Reused for both the per-medication drill-down and the calendar day tap.
struct HistoryEntriesView: View {
    let title: String
    let showMedicationName: Bool
    let entries: [DoseHistoryEntry]

    @AppStorage("timeFormat") private var timeFormat: String = "system"

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView(
                    "No doses logged",
                    systemImage: "calendar.badge.clock",
                    description: Text("Nothing was recorded for this selection.")
                )
            } else {
                List(entries) { entry in
                    HistoryEntryRow(entry: entry, showMedicationName: showMedicationName, timeFormat: timeFormat)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct HistoryEntryRow: View {
    let entry: DoseHistoryEntry
    let showMedicationName: Bool
    let timeFormat: String

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: entry.colorHex))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                if showMedicationName {
                    Text(entry.medicationName)
                        .font(.subheadline.weight(.medium))
                }
                Text("Due \(TimeFormatPreference.string(for: entry.scheduledAt, preference: timeFormat))")
                    .font(showMedicationName ? .caption : .subheadline)
                    .foregroundStyle(.secondary)
                if let loggedAt = entry.loggedAt, entry.status == .taken {
                    Text("Taken at \(TimeFormatPreference.string(for: loggedAt, preference: timeFormat))")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            Spacer()
            statusChip
        }
        .padding(.vertical, 2)
    }

    private var statusChip: some View {
        let (label, color, icon): (String, Color, String) = {
            switch entry.status {
            case .taken:   return ("Taken", .green, "checkmark.circle.fill")
            case .skipped: return ("Skipped", .orange, "arrow.uturn.right.circle.fill")
            case .missed:  return ("Missed", .red, "xmark.circle.fill")
            }
        }()
        return Label(label, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .labelStyle(.titleAndIcon)
    }
}

// MARK: - Card container (replaces List's Section styling now that History uses ScrollView)

/// Rounded card wrapper standing in for a `List` `Section`'s grouped-inset look, now that
/// HistoryView uses a plain `ScrollView` instead of `List` (see the crash-fix comment on
/// `HistoryView.body`).
private struct HistoryCard<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct HistorySectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        // Sentence case to match every other section header in the app ("Due / Past",
        // "Upcoming Today") — an ALL-CAPS header was the odd one out.
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
    }
}

// MARK: - Subviews

private struct AdherenceSummaryRow: View {
    let percent: Double

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 6)
                    .frame(width: 56, height: 56)
                Circle()
                    .trim(from: 0, to: percent)
                    .stroke(adherenceColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 56, height: 56)
                    .rotationEffect(.degrees(-90))
                Text("\(Int(percent * 100))%")
                    .font(.caption.weight(.bold))
            }
            VStack(alignment: .leading) {
                Text("Overall Adherence")
                    .font(.subheadline.weight(.semibold))
                Text(adherenceLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var adherenceColor: Color {
        percent >= 0.9 ? .green : percent >= 0.5 ? .orange : .red
    }

    private var adherenceLabel: String {
        percent >= 0.9 ? "Great job!" : percent >= 0.5 ? "Room to improve" : "Needs attention"
    }
}

private struct MedicationAdherenceRow: View {
    let item: MedicationAdherence

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: item.colorHex))
                .frame(width: 10, height: 10)
            Text(item.name)
                .font(.subheadline)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(item.percent * 100))%")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(item.percent >= 0.9 ? .green : item.percent >= 0.5 ? .orange : .red)
                Text("\(item.taken)/\(item.total)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct LegendDot: View {
    let color: Color
    let label: String
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).foregroundStyle(.secondary)
        }
    }
}

/// UIActivityViewController wrapper for sharing files.
struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    HistoryView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
        .environmentObject(SubscriptionManager.shared)
        .environmentObject(CaregiverManager.shared)
        .environmentObject(ActiveAccountContext(ownUserId: UUID(), ownDisplayName: "Preview User"))
}
