// DoseTrack/Views/Today/DoseActionSheet.swift
import SwiftUI
import UIKit

struct DoseActionSheet: View {
    let entry: DoseEntry
    let onTaken: () -> Void
    let onSkipped: (String?) -> Void
    let onSnooze: () -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("timeFormat") private var timeFormat: String = "system"

    @State private var showingSkipReasonChoice = false
    @State private var showingReasonEntry = false
    @State private var skipReasonText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Handle indicator
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 16)

            // Medication info header
            HStack(spacing: 12) {
                Circle()
                    .fill(entry.medication.color)
                    .frame(width: 16, height: 16)
                VStack(alignment: .leading) {
                    Text(entry.medication.wrappedName)
                        .font(.headline)
                    Text("\(entry.medication.wrappedDosage) · \(entry.schedule.wrappedRoutineLabel ?? TimeFormatPreference.string(for: entry.scheduledAt, preference: timeFormat))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom, 20)

            Divider()

            actionButton(title: "Mark as Taken", icon: "checkmark.circle.fill", color: .green) {
                haptic(.medium)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onTaken(); dismiss()
            }
            Divider().padding(.leading)
            actionButton(title: "Skip This Dose", icon: "arrow.right.circle.fill", color: .orange) {
                haptic(.light)
                showingSkipReasonChoice = true
            }
            Divider().padding(.leading)
            actionButton(title: "Snooze 30 Minutes", icon: "clock.fill", color: .blue) {
                haptic(.light)
                onSnooze(); dismiss()
            }

            Divider().padding(.top, 8)

            Button("Cancel") { dismiss() }
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding()
        }
        .background(.background)
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.hidden)
        .confirmationDialog(
            "Record a reason for skipping?",
            isPresented: $showingSkipReasonChoice,
            titleVisibility: .visible
        ) {
            Button("Yes, Add a Reason") { showingReasonEntry = true }
            Button("No, Just Skip") { onSkipped(nil); dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The reason is saved with this dose in your history — useful if you export a report later.")
        }
        .alert("Reason for Skipping", isPresented: $showingReasonEntry) {
            TextField("e.g. Felt nauseous", text: $skipReasonText)
            Button("Skip") {
                let trimmed = skipReasonText.trimmingCharacters(in: .whitespacesAndNewlines)
                onSkipped(trimmed.isEmpty ? nil : trimmed)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    private func actionButton(
        title: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                    .frame(width: 28)
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
