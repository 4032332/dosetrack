// DoseTrack/Views/Today/TodayView.swift
import SwiftUI

struct TodayView: View {
    @StateObject private var viewModel = TodayViewModel(
        context: PersistenceController.shared.viewContext
    )
    @State private var selectedEntry: DoseEntry?

    var body: some View {
        NavigationStack {
            List {
                // Adherence header
                Section {
                    AdherenceHeaderView(
                        takenCount: viewModel.takenCount,
                        totalCount: viewModel.totalCount,
                        allDone: viewModel.allDonToday
                    )
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                if viewModel.doseEntries.isEmpty {
                    Section {
                        Text("No medications scheduled for today")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 32)
                    }
                    .listRowBackground(Color.clear)
                } else {
                    let past = viewModel.doseEntries.filter {
                        $0.scheduledAt <= Date() || $0.existingLog != nil
                    }
                    let upcoming = viewModel.doseEntries.filter {
                        $0.scheduledAt > Date() && $0.existingLog == nil
                    }

                    if !past.isEmpty {
                        Section("Due / Past") {
                            ForEach(past) { entry in
                                DoseRowView(entry: entry)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedEntry = entry }
                            }
                        }
                    }

                    if !upcoming.isEmpty {
                        Section("Upcoming") {
                            ForEach(upcoming) { entry in
                                DoseRowView(entry: entry)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedEntry = entry }
                            }
                        }
                    }
                }
            }
            .navigationTitle(Date().formatted(.dateTime.weekday(.wide).month().day()))
            .navigationBarTitleDisplayMode(.large)
            .refreshable { viewModel.refresh() }
            .sheet(item: $selectedEntry) { entry in
                DoseActionSheet(
                    entry: entry,
                    onTaken:   { viewModel.markTaken(entry) },
                    onSkipped: { viewModel.markSkipped(entry) },
                    onSnooze:  { viewModel.snooze(entry) }
                )
            }
        }
        .onAppear { viewModel.refresh() }
    }
}

private struct AdherenceHeaderView: View {
    let takenCount: Int
    let totalCount: Int
    let allDone: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if allDone {
                    Label("All doses taken today", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline.weight(.semibold))
                } else if totalCount == 0 {
                    Text("No medications scheduled")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(takenCount) of \(totalCount) doses taken")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if totalCount > 0 {
                AdherenceRingView(percent: Double(takenCount) / Double(totalCount))
                    .frame(width: 44, height: 44)
            }
        }
        .padding()
    }
}

private struct AdherenceRingView: View {
    let percent: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 5)
            Circle()
                .trim(from: 0, to: percent)
                .stroke(
                    percent >= 1.0 ? Color.green : Color.accentColor,
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Text("\(Int(percent * 100))%")
                .font(.system(size: 10, weight: .bold))
        }
    }
}

#Preview {
    TodayView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
        .environmentObject(SubscriptionManager())
}
