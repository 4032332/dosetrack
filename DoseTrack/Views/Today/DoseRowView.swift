// DoseTrack/Views/Today/DoseRowView.swift
import SwiftUI

struct DoseRowView: View {
    let entry: DoseEntry

    var body: some View {
        HStack(spacing: 14) {
            // Colour-coded pill icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(entry.medication.color.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: unitIcon)
                    .font(.system(size: 16))
                    .foregroundStyle(entry.medication.color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.medication.wrappedName)
                    .font(.body.weight(.medium))
                Text(entry.medication.wrappedDosage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(entry.scheduledAt, format: .dateTime.hour().minute())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                StatusChip(status: entry.status)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(entry.medication.wrappedName), \(entry.medication.wrappedDosage), " +
            "due at \(entry.scheduledAt.formatted(date: .omitted, time: .shortened)), " +
            "\(entry.status.displayName)"
        )
    }

    private var unitIcon: String {
        switch entry.medication.wrappedUnit {
        case "injection":     return "syringe.fill"
        case "ml":            return "drop.fill"
        case "spray":         return "aqi.medium"
        case "contraceptive": return "calendar.badge.clock"
        case "supplement":    return "leaf.fill"
        default:              return "pill.fill"
        }
    }
}

struct StatusChip: View {
    let status: DoseStatus

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: chipIcon)
                .font(.system(size: 9, weight: .bold))
            Text(label)
                .font(.system(size: 10, weight: .semibold))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
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

    private var chipIcon: String {
        switch status {
        case .taken:   return "checkmark"
        case .skipped: return "forward.fill"
        case .missed:  return "clock"
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
