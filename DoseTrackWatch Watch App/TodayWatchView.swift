// DoseTrackWatch Watch App/TodayWatchView.swift
import SwiftUI

struct TodayWatchView: View {
    @EnvironmentObject private var connectivity: WatchConnectivityReceiver
    @State private var showConfetti = false
    /// Taken doses collapse into their own expandable section by default — on a watch screen
    /// this small, a fully-taken list otherwise pushes anything still outstanding off screen,
    /// which is the opposite of what matters most at a glance.
    @State private var showTaken = false

    private var outstanding: [WatchMedication] { connectivity.medications.filter { !$0.isTaken } }
    private var takenMeds: [WatchMedication] { connectivity.medications.filter { $0.isTaken } }
    private var taken: Int { connectivity.medications.filter { $0.isTaken }.count }
    private var total: Int { connectivity.medications.count }
    private var allDone: Bool { total > 0 && taken == total }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    headerCard
                    doseList
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 12)
            }
            .navigationTitle("DoseTrack")
            .navigationBarTitleDisplayMode(.inline)
        }
        .overlay {
            if showConfetti {
                WatchConfettiView { showConfetti = false }
                    .transition(.opacity)
            }
        }
        .onChange(of: connectivity.celebrateNow) { _, newValue in
            if newValue { showConfetti = true }
        }
    }

    // MARK: - Header card

    private var headerCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    LinearGradient(
                        colors: allDone
                            ? [Color(hex: "27AE60"), Color(hex: "2ECC71")]
                            : [Color(hex: "1A73E8"), Color(hex: "34A0F7")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            HStack(spacing: 10) {
                // Milli avatar — WatchHero is a transparent cut-out (no baked-in background), so
                // it drops straight onto the gradient with no box/circle backing needed.
                Image("WatchHero")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text(allDone ? "All done! 🎉" : "Today's doses")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                    Text("\(taken) of \(total) taken")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.85))
                }

                Spacer()

                // Ring
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.3), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: total > 0 ? CGFloat(taken) / CGFloat(total) : 0)
                        .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(total > 0 ? "\(Int(CGFloat(taken) / CGFloat(total) * 100))%" : "–")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 32, height: 32)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Dose list

    @ViewBuilder
    private var doseList: some View {
        if connectivity.medications.isEmpty {
            emptyState
        } else {
            VStack(spacing: 6) {
                if outstanding.isEmpty && !takenMeds.isEmpty {
                    // Everything's done — no separate "outstanding" heading needed, the header
                    // card already says "All done! 🎉". Show the taken list directly (it's the
                    // only content there is), still collapsed by default.
                    takenSection
                } else {
                    ForEach(outstanding) { med in doseRow(for: med) }
                    if !takenMeds.isEmpty {
                        takenSection
                    }
                }
            }
        }
    }

    private func doseRow(for med: WatchMedication) -> some View {
        WatchDoseRow(medication: med) { status in
            connectivity.confirmDose(
                medicationId: med.id,
                scheduleId: med.scheduleId,
                scheduledAt: med.scheduledAt,
                status: status
            )
        }
    }

    private var takenSection: some View {
        VStack(spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showTaken.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Text("Taken (\(takenMeds.count))")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Image(systemName: showTaken ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.top, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showTaken {
                ForEach(takenMeds) { med in doseRow(for: med) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image("WatchHero")
                .resizable()
                .scaledToFit()
                .frame(width: 50, height: 50)
            Text("No doses today")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            Text("Open DoseTrack on iPhone to sync")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 16)
    }
}

// MARK: - Dose Row

private struct WatchDoseRow: View {
    let medication: WatchMedication
    let onAction: (String) -> Void

    @State private var showingActions = false

    private var medColor: Color { Color(hex: medication.colorHex) }

    var body: some View {
        Button {
            showingActions = true
        } label: {
            HStack(spacing: 8) {
                // Colour icon square
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(medColor.opacity(medication.isTaken ? 0.2 : 0.18))
                    Image(systemName: medication.isTaken ? "checkmark" : "pill.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(medication.isTaken ? .green : medColor)
                }
                .frame(width: 30, height: 30)

                // Name + dose
                VStack(alignment: .leading, spacing: 1) {
                    Text(medication.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(medication.isTaken ? .secondary : .primary)
                        .strikethrough(medication.isTaken, color: .secondary)
                        .lineLimit(1)
                    Text(medication.dosage)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Time + status chip
                VStack(alignment: .trailing, spacing: 2) {
                    Text(medication.scheduledAt, style: .time)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    if medication.isTaken {
                        Text("Done")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.green.opacity(0.2))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(white: 0.12))
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingActions) {
            WatchDoseActionSheet(
                medication: medication,
                onTaken:  { onAction("taken");   showingActions = false },
                onSkip:   { onAction("skipped"); showingActions = false },
                onUntake: { onAction("untake");  showingActions = false }
            )
        }
    }
}

// MARK: - Action Sheet

private struct WatchDoseActionSheet: View {
    let medication: WatchMedication
    let onTaken: () -> Void
    let onSkip: () -> Void
    let onUntake: () -> Void

    private var medColor: Color { Color(hex: medication.colorHex) }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(medColor.opacity(0.18))
                    Image(systemName: "pill.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(medColor)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 1) {
                    Text(medication.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(medication.dosage)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            if medication.isTaken {
                Button(action: onUntake) {
                    Label("Undo taken", systemImage: "arrow.uturn.backward.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            } else {
                Button(action: onTaken) {
                    Label("Taken", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.green)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                Button(action: onSkip) {
                    Label("Skip", systemImage: "forward.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color(white: 0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
    }
}

// MARK: - Color hex helper (watch-local copy)

private extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: h).scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8)  & 0xFF) / 255
        let b = Double(rgb & 0xFF)          / 255
        self.init(red: r, green: g, blue: b)
    }
}
