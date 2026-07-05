// DoseTrack/Views/Today/DoseRowView.swift
import SwiftUI

struct DoseRowView: View {
    let entry: DoseEntry
    @AppStorage("timeFormat") private var timeFormat: String = "system"
    @AppStorage("compactRows") private var compactRows: Bool = false

    private var iconSize: CGFloat { compactRows ? 30 : 40 }

    var body: some View {
        HStack(spacing: compactRows ? 10 : 14) {
            // Colour-coded pill icon
            ZStack {
                RoundedRectangle(cornerRadius: compactRows ? 7 : 10)
                    .fill(entry.medication.color.opacity(0.15))
                    .frame(width: iconSize, height: iconSize)
                Image(systemName: unitIcon)
                    .font(.system(size: compactRows ? 13 : 16))
                    .foregroundStyle(entry.medication.color)
            }

            VStack(alignment: .leading, spacing: compactRows ? 1 : 3) {
                Text(entry.medication.wrappedName)
                    .font(compactRows ? .subheadline.weight(.medium) : .body.weight(.medium))
                if !compactRows {
                    Text(entry.medication.wrappedDosage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(TimeFormatPreference.string(for: entry.scheduledAt, preference: timeFormat))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                StatusChip(status: entry.status)
            }
        }
        .padding(.vertical, compactRows ? 2 : 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(entry.medication.wrappedName), \(entry.medication.wrappedDosage), " +
            "due at \(TimeFormatPreference.string(for: entry.scheduledAt, preference: timeFormat)), " +
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
