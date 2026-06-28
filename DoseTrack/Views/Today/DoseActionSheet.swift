// DoseTrack/Views/Today/DoseActionSheet.swift
import SwiftUI

struct DoseActionSheet: View {
    let entry: DoseEntry
    let onTaken: () -> Void
    let onSkipped: () -> Void
    let onSnooze: () -> Void
    @Environment(\.dismiss) private var dismiss

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
                    Text("\(entry.medication.wrappedDosage) · \(entry.scheduledAt.formatted(date: .omitted, time: .shortened))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom, 20)

            Divider()

            actionButton(title: "Mark as Taken", icon: "checkmark.circle.fill", color: .green) {
                onTaken(); dismiss()
            }
            Divider().padding(.leading)
            actionButton(title: "Skip This Dose", icon: "arrow.right.circle.fill", color: .orange) {
                onSkipped(); dismiss()
            }
            Divider().padding(.leading)
            actionButton(title: "Snooze 30 Minutes", icon: "clock.fill", color: .blue) {
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
