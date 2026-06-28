// DoseTrack/Views/Today/DoseRowView.swift
import SwiftUI

struct DoseRowView: View {
    let entry: DoseEntry

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(entry.medication.color)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.medication.wrappedName)
                    .font(.body)
                    .fontWeight(.medium)
                Text(entry.medication.wrappedDosage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.scheduledAt, format: .dateTime.hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                StatusChip(status: entry.status)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(entry.medication.wrappedName), \(entry.medication.wrappedDosage), " +
            "due at \(entry.scheduledAt.formatted(date: .omitted, time: .shortened)), " +
            "\(entry.status.displayName)"
        )
    }
}

struct StatusChip: View {
    let status: DoseStatus

    var body: some View {
        Text(label)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(chipColor.opacity(0.15))
            .foregroundStyle(chipColor)
            .clipShape(Capsule())
    }

    private var label: String {
        switch status {
        case .taken:   return "Taken"
        case .skipped: return "Skipped"
        case .missed:  return "Missed"
        }
    }

    private var chipColor: Color {
        switch status {
        case .taken:   return .green
        case .skipped: return .orange
        case .missed:  return .red
        }
    }
}

#Preview {
    let context = PersistenceController.preview.viewContext
    let med = Medication.create(in: context, name: "Metformin", dosage: "500mg")
    let sched = Schedule.create(in: context, medication: med, hour: 8, minute: 0)
    let entry = DoseEntry(
        id: UUID(), medication: med, schedule: sched,
        scheduledAt: Date(), status: .missed, existingLog: nil
    )
    return DoseRowView(entry: entry)
        .padding()
}
