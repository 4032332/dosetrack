// DoseTrackWatch Watch App/TodayWatchView.swift
import SwiftUI

struct TodayWatchView: View {
    @EnvironmentObject private var connectivity: WatchConnectivityReceiver

    private var taken: Int { connectivity.medications.filter { $0.isTaken }.count }
    private var total: Int { connectivity.medications.count }

    var body: some View {
        NavigationStack {
            Group {
                if connectivity.medications.isEmpty {
                    emptyState
                } else {
                    medicationList
                }
            }
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Subviews

    private var medicationList: some View {
        List {
            // Adherence header
            Section {
                HStack {
                    ZStack {
                        Circle()
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 3)
                        Circle()
                            .trim(from: 0, to: total > 0 ? CGFloat(taken) / CGFloat(total) : 0)
                            .stroke(taken == total ? Color.green : Color.accentColor,
                                    style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(taken)/\(total)")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .frame(width: 36, height: 36)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(taken == total && total > 0 ? "All done!" : "Today's doses")
                            .font(.caption2.weight(.semibold))
                        if let updated = connectivity.lastUpdated {
                            Text("Updated \(updated, style: .relative) ago")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // Dose rows
            ForEach(connectivity.medications) { med in
                WatchDoseRow(medication: med) { status in
                    connectivity.confirmDose(
                        medicationId: med.id,
                        scheduleId: med.scheduleId,
                        scheduledAt: med.scheduledAt,
                        status: status
                    )
                }
            }
        }
        .listStyle(.carousel)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.green)
            Text("No doses today")
                .font(.caption)
                .multilineTextAlignment(.center)
            Text("Open DoseTrack on iPhone to sync")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - WatchDoseRow

private struct WatchDoseRow: View {
    let medication: WatchMedication
    let onAction: (String) -> Void

    @State private var showingActions = false

    var body: some View {
        Button {
            if !medication.isTaken {
                showingActions = true
            }
        } label: {
            HStack(spacing: 8) {
                // Status indicator
                Image(systemName: medication.isTaken ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(medication.isTaken ? .green : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(medication.name)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .foregroundStyle(medication.isTaken ? .secondary : .primary)
                        .strikethrough(medication.isTaken)
                    Text(medication.dosage)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(medication.scheduledAt, style: .time)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingActions) {
            WatchDoseActionSheet(
                medicationName: medication.name,
                onTaken: { onAction("taken"); showingActions = false },
                onSkip: { onAction("skipped"); showingActions = false }
            )
        }
    }
}

// MARK: - WatchDoseActionSheet

private struct WatchDoseActionSheet: View {
    let medicationName: String
    let onTaken: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text(medicationName)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Button(action: onTaken) {
                Label("Taken", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green.opacity(0.2))

            Button(action: onSkip) {
                Label("Skip", systemImage: "xmark.circle")
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}
