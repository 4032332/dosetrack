// DoseTrack/Views/Today/TodayView.swift
import SwiftUI

struct TodayView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var caregiverManager: CaregiverManager
    // Not initialized with the environment context directly: @StateObject's initial value is
    // evaluated before the environment is available. Instead we seed it with a placeholder and
    // rebuild it in `.task`/`.onChange(of: context)` below so the view always operates against
    // whichever context RootView has injected (own store vs. a caregiver-viewed patient store).
    @StateObject private var viewModel = TodayViewModel(
        context: PersistenceController.shared.viewContext
    )
    @State private var selectedEntry: DoseEntry?
    @AppStorage("patientName") private var patientName: String = ""
    @State private var showConfetti = false
    /// Taken-and-past doses default to collapsed so a long list of already-handled doses
    /// doesn't push "Upcoming Today" off screen — the user can still expand to review them.
    @State private var showTakenPast = false
    @Binding var showingAccountSwitcher: Bool

    init(showingAccountSwitcher: Binding<Bool> = .constant(false)) {
        self._showingAccountSwitcher = showingAccountSwitcher
    }

    private func syncContext() {
        viewModel.updateContext(context)
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: Gradient header card
                Section {
                    TodayHeaderCard(
                        name: patientName,
                        takenCount: viewModel.takenCount,
                        totalCount: viewModel.totalCount,
                        allDone: viewModel.allDonToday
                    )
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                // MARK: Dose list
                if viewModel.doseEntries.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            // OnboardingAllDone.png has an opaque background baked in — see AuthView.
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(colors: [.green.opacity(0.3), .green.opacity(0.12)],
                                                          startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 108, height: 108)
                                Image("OnboardingAllDone")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 76, height: 76)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            Text("No medications scheduled today")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    }
                    .listRowBackground(Color.clear)
                } else {
                    let past = viewModel.doseEntries.filter {
                        $0.scheduledAt <= Date() || $0.existingLog != nil
                    }
                    let upcoming = viewModel.doseEntries.filter {
                        $0.scheduledAt > Date() && $0.existingLog == nil
                    }
                    // Split past doses into anything still needing attention (pending/skipped/
                    // missed) — always shown — and doses already marked taken, which collapse
                    // into their own expandable section so a long taken history doesn't push
                    // "Upcoming Today" off screen.
                    let pendingPast = past.filter { $0.status != .taken }
                    let takenPast = past.filter { $0.status == .taken }

                    if !pendingPast.isEmpty {
                        let pastGroups = groupedByTime(pendingPast)
                        ForEach(Array(pastGroups.enumerated()), id: \.element.time) { index, group in
                            Section {
                                ForEach(group.entries) { entry in
                                    DoseRowView(entry: entry)
                                        .contentShape(Rectangle())
                                        .onTapGesture { selectedEntry = entry }
                                }
                            } header: {
                                TimeGroupHeader(
                                    title: index == 0 ? "Due / Past" : nil,
                                    entries: group.entries,
                                    onMarkAllTaken: { viewModel.markAllTaken(group.entries) }
                                )
                            }
                        }
                    }

                    if !takenPast.isEmpty {
                        Section {
                            DisclosureGroup(isExpanded: $showTakenPast) {
                                ForEach(takenPast.sorted { $0.scheduledAt < $1.scheduledAt }) { entry in
                                    DoseRowView(entry: entry)
                                        .contentShape(Rectangle())
                                        .onTapGesture { selectedEntry = entry }
                                }
                            } label: {
                                Text(pendingPast.isEmpty ? "Due / Past — Taken (\(takenPast.count))" : "Taken (\(takenPast.count))")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .textCase(nil)
                        }
                    }

                    if !upcoming.isEmpty {
                        Section {
                            ForEach(upcoming) { entry in
                                DoseRowView(entry: entry)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedEntry = entry }
                            }
                        } header: {
                            SectionHeader("Upcoming Today")
                        }
                    }
                }
            }
            .scrollIndicators(.visible)
            .contentMargins(.bottom, 32, for: .scrollContent)
            .navigationTitle(Date().formatted(.dateTime.weekday(.wide).month().day()))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if !caregiverManager.overseenPatients.isEmpty {
                    ToolbarItem(placement: .principal) {
                        AccountSwitcherPill(isPresented: $showingAccountSwitcher)
                    }
                }
            }
            .refreshable { viewModel.refresh() }
            .safeAreaInset(edge: .bottom) {
                if !viewModel.medicationAlerts.isEmpty {
                    AlertsPanelView(alerts: viewModel.medicationAlerts)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }
            }
            .sheet(item: $selectedEntry) { entry in
                DoseActionSheet(
                    entry: entry,
                    onTaken:   { viewModel.markTaken(entry) },
                    onSkipped: { reason in viewModel.markSkipped(entry, reason: reason) },
                    onSnooze:  { viewModel.snooze(entry) }
                )
            }
        }
        .onAppear {
            syncContext()
            viewModel.refresh()
        }
        .onChange(of: context) { _, _ in syncContext() }
        .onChange(of: viewModel.celebrateNow) { _, newValue in
            if newValue { showConfetti = true }
        }
        .overlay {
            if showConfetti {
                ConfettiView { showConfetti = false }
                    .transition(.opacity)
            }
        }
    }

    /// Groups entries that share an exact scheduled hour/minute — e.g. three medications
    /// all due at 08:00 — so the UI can offer a single "Mark all taken" action for the
    /// whole group instead of requiring one tap per medication.
    private func groupedByTime(_ entries: [DoseEntry]) -> [(time: Date, entries: [DoseEntry])] {
        let calendar = Calendar.current
        let buckets = Dictionary(grouping: entries) { entry in
            calendar.date(bySettingHour: calendar.component(.hour, from: entry.scheduledAt),
                          minute: calendar.component(.minute, from: entry.scheduledAt),
                          second: 0, of: entry.scheduledAt) ?? entry.scheduledAt
        }
        return buckets.keys.sorted().map { time in
            (time: time, entries: buckets[time]!.sorted { $0.medication.wrappedName < $1.medication.wrappedName })
        }
    }
}

// MARK: - Time Group Header

/// Section header for a group of doses due at the same time. Shows an optional section
/// title (only on the first group, so "Due / Past" still reads as one section visually)
/// plus a "Mark all taken" button when 2+ medications share this time slot and at least
/// one hasn't been logged as taken yet.
private struct TimeGroupHeader: View {
    let title: String?
    let entries: [DoseEntry]
    let onMarkAllTaken: () -> Void

    @AppStorage("timeFormat") private var timeFormat: String = "system"

    private var allTaken: Bool {
        entries.allSatisfy { $0.status == .taken }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if entries.count > 1 {
                HStack {
                    Text(TimeFormatPreference.string(for: entries[0].scheduledAt, preference: timeFormat))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !allTaken {
                        Button(action: onMarkAllTaken) {
                            Label("Mark all \(entries.count) taken", systemImage: "checkmark.circle.fill")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
        .textCase(nil)
    }
}

// MARK: - Header Card

private struct TodayHeaderCard: View {
    let name: String
    let takenCount: Int
    let totalCount: Int
    let allDone: Bool

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        default:      return "Good evening"
        }
    }

    private var adherencePercent: Double {
        totalCount > 0 ? Double(takenCount) / Double(totalCount) : 1.0
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Gradient background
            LinearGradient(
                colors: allDone
                    ? [Color(hex: "#34C759").opacity(0.85), Color(hex: "#30A46C")]
                    : [Color(hex: "#5B8AF0"), Color(hex: "#3B5FCC")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Subtle pill watermark
            Image(systemName: "pills.fill")
                .font(.system(size: 120))
                .foregroundStyle(.white.opacity(0.07))
                .offset(x: 200, y: -10)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name.isEmpty ? greeting : "\(greeting), \(name.split(separator: " ").first.map(String.init) ?? name)")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.9))

                    if allDone {
                        Label("All doses taken today!", systemImage: "checkmark.seal.fill")
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                    } else if totalCount == 0 {
                        Text("Nothing scheduled today")
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                    } else {
                        Text("\(takenCount) of \(totalCount)")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("doses taken")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
                Spacer()
                if totalCount > 0 {
                    AdherenceRingView(percent: adherencePercent, allDone: allDone)
                        .frame(width: 64, height: 64)
                }
            }
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

private struct AdherenceRingView: View {
    let percent: Double
    let allDone: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.25), lineWidth: 6)
            Circle()
                .trim(from: 0, to: percent)
                .stroke(.white, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(percent * 100))%")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Section Header

private struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(nil)
    }
}

// MARK: - Alerts Panel

struct AlertsPanelView: View {
    let alerts: [MedicationAlert]
    @State private var isExpanded = false
    @EnvironmentObject private var navigator: TabNavigator

    var body: some View {
        VStack(spacing: 0) {
            // Collapse/expand handle
            Button {
                withAnimation(.spring(duration: 0.3)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "bell.badge.fill")
                        .foregroundStyle(.orange)
                        .font(.subheadline)
                    Text("\(alerts.count) alert\(alerts.count == 1 ? "" : "s")")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .padding(.horizontal, 16)

                VStack(spacing: 0) {
                    ForEach(alerts) { alert in
                        AlertRow(alert: alert)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if case .lowRefill = alert {
                                    withAnimation { navigator.selectedTab = .restock }
                                }
                            }
                        if alert.id != alerts.last?.id {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 8, y: -2)
    }
}

private struct AlertRow: View {
    let alert: MedicationAlert

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(iconColor.opacity(0.15))
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: iconName)
                        .font(.system(size: 15))
                        .foregroundStyle(iconColor)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var iconName: String {
        switch alert {
        case .lowRefill:        return "cross.case.fill"
        case .upcomingDue:      return "calendar.badge.exclamationmark"
        case .contraceptiveDue: return "calendar.badge.clock"
        }
    }

    private var iconColor: Color {
        switch alert {
        case .lowRefill:
            return .orange
        case .upcomingDue(_, _, let days):
            return days <= 7 ? .red : .purple
        case .contraceptiveDue(_, _, let days):
            if days < 0  { return .red }
            if days < 14 { return .orange }
            return .purple
        }
    }

    private var title: String {
        switch alert {
        case .lowRefill(let med, _):          return "\(med.wrappedName) running low"
        case .upcomingDue(let med, _, _):     return "\(med.wrappedName) due soon"
        case .contraceptiveDue(let name, _, _): return "\(name) due soon"
        }
    }

    private var subtitle: String {
        switch alert {
        case .lowRefill(let med, let remaining):
            let dpd = max(Int(med.totalDosesPerDay), 1)
            let days = remaining / dpd
            if days == 0 { return "\(remaining) dose\(remaining == 1 ? "" : "s") left — refill now" }
            return "\(days) day\(days == 1 ? "" : "s") supply left (\(remaining) \(med.wrappedUnit)\(remaining == 1 ? "" : "s")) — time to refill"
        case .upcomingDue(_, let date, let days):
            if days == 0 { return "Due today — \(date.formatted(date: .abbreviated, time: .omitted))" }
            return "\(days) day\(days == 1 ? "" : "s") until due — \(date.formatted(date: .abbreviated, time: .omitted))"
        case .contraceptiveDue(_, let date, let days):
            if days < 0  { return "Overdue since \(date.formatted(date: .abbreviated, time: .omitted)) — check with your provider" }
            if days == 0 { return "Due today — \(date.formatted(date: .abbreviated, time: .omitted))" }
            return "\(days) day\(days == 1 ? "" : "s") until due — \(date.formatted(date: .abbreviated, time: .omitted))"
        }
    }
}

#Preview {
    TodayView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
        .environmentObject(SubscriptionManager())
        .environmentObject(CaregiverManager.shared)
}
