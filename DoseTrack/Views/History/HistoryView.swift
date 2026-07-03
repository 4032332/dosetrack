// DoseTrack/Views/History/HistoryView.swift
import SwiftUI

struct HistoryView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @StateObject private var viewModel = HistoryViewModel(
        context: PersistenceController.shared.viewContext
    )

    @State private var showingCalendar = false
    @State private var calendarMonth = Date()
    @State private var showingExportSheet = false
    @State private var exportItem: ExportItem? = nil
    @State private var showingPaywall = false

    var body: some View {
        NavigationStack {
            List {
                // Range picker
                Section {
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
                Section {
                    AdherenceSummaryRow(percent: viewModel.overallPercent)
                }

                // Chart vs calendar toggle
                Section {
                    HStack {
                        Text(showingCalendar ? "Calendar" : "Chart")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Picker("View", selection: $showingCalendar) {
                            Label("Chart", systemImage: "chart.bar.fill").tag(false)
                            Label("Calendar", systemImage: "calendar").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 120)
                    }

                    if showingCalendar {
                        CalendarView(days: viewModel.dayAdherences, displayedMonth: $calendarMonth)
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

                // Per-medication breakdown
                if !viewModel.medicationAdherences.isEmpty {
                    Section("By Medication") {
                        ForEach(viewModel.medicationAdherences) { item in
                            MedicationAdherenceRow(item: item)
                        }
                    }
                }

                // Legend
                Section {
                    HStack(spacing: 16) {
                        LegendDot(color: .green, label: "≥90%")
                        LegendDot(color: .orange, label: "50–89%")
                        LegendDot(color: .red, label: "<50%")
                        LegendDot(color: .gray.opacity(0.4), label: "No doses")
                    }
                    .font(.caption)
                }

                // Disclaimer
                Section {
                    Text("DoseTrack is a reminder tool, not medical advice. Always follow your healthcare provider's instructions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollIndicators(.visible)
            .contentMargins(.bottom, 32, for: .scrollContent)
            .navigationTitle("History")
            .toolbar {
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
                            Label("Doctor Report (PDF)", systemImage: "doc.richtext")
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
                ActivityView(activityItems: [item.data as Any, item.filename])
            }
            .refreshable {
                viewModel.refresh()
            }
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
        exportItem = ExportItem(data: data, filename: filename)
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
        let patientName = UserDefaults.standard.string(forKey: "patientName") ?? ""
        let data = ReportGenerator.shared.generatePDF(
            logs: logs, medications: meds, dateRange: interval, patientName: patientName
        )
        let filename = "dosetrack-report-\(Date().formatted(.dateTime.year().month().day())).pdf"
        exportItem = ExportItem(data: data, filename: filename)
    }
}

// MARK: - Supporting types

/// Wraps export data for `.sheet(item:)` presentation.
struct ExportItem: Identifiable {
    let id = UUID()
    let data: Data
    let filename: String
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
}
