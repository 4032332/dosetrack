// DoseTrack/Views/Today/DoseRowView.swift
import SwiftUI

struct DoseRowView: View {
    let entry: DoseEntry
    @AppStorage("timeFormat") private var timeFormat: String = "system"
    @AppStorage("compactRows") private var compactRows: Bool = false

    private var iconSize: CGFloat { 40 }

    private var timeOrRoutine: String {
        // A schedule linked to a Daily Routine Time (e.g. "Bedtime") is really keyed to that
        // routine, not a fixed clock time — the actual fire time follows wherever the user has
        // that routine set in Settings. Showing the routine name is more meaningful than a clock
        // time that's really just a byproduct of it, and stays correct even if the routine moves.
        entry.schedule.wrappedRoutineLabel ?? TimeFormatPreference.string(for: entry.scheduledAt, preference: timeFormat)
    }

    var body: some View {
        Group {
            if compactRows { compactBody } else { fullBody }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(entry.medication.wrappedName), \(entry.medication.wrappedDosage), " +
            "due at \(entry.schedule.wrappedRoutineLabel ?? TimeFormatPreference.string(for: entry.scheduledAt, preference: timeFormat)), " +
            "\(entry.isUpcoming ? "upcoming" : entry.status.displayName)"
        )
    }

    // MARK: - Full (default) row

    private var fullBody: some View {
        HStack(spacing: 14) {
            // Colour-coded pill icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(entry.medication.color.opacity(0.15))
                    .frame(width: iconSize, height: iconSize)
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
                Text(timeOrRoutine)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if entry.isUpcoming {
                    UpcomingChip()
                } else {
                    StatusChip(status: entry.status)
                }
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Compact row

    // ~Half height: the tinted icon tile is dropped in favour of a slim colour bar (the colour
    // tag is preserved, just thinner), name + dose sit on one line, and the status becomes a
    // dot-only chip. Time/routine + status stay, per the Compact Dose Rows brief.
    private var compactBody: some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(entry.medication.color)
                .frame(width: 4, height: 22)

            Text(entry.medication.wrappedName)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Text(entry.medication.wrappedDosage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 6)

            Text(timeOrRoutine)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if entry.isUpcoming {
                UpcomingChip(compact: true)
            } else {
                StatusChip(status: entry.status, compact: true)
            }
        }
        .padding(.vertical, 2)
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
    /// Compact rows show a dot-only chip (no text label) to save vertical/horizontal space
    /// while still colour-coding the status.
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: chipIcon)
                .font(.system(size: 9, weight: .bold))
            if !compact {
                Text(label)
                    // Was a fixed size 10 that never scaled with Dynamic Type — status text
                    // ("Taken"/"Skipped"/"Missed") is exactly the kind of small readable label
                    // where that matters most for low-vision users.
                    .font(.caption2.weight(.semibold))
            }
        }
        .padding(.horizontal, compact ? 5 : 7)
        .padding(.vertical, compact ? 3 : 3)
        .background(chipColor.opacity(0.15))
        .foregroundStyle(chipColor)
        .clipShape(Capsule())
        .accessibilityLabel(label)
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

/// Neutral chip for a future dose that hasn't been logged yet — deliberately distinct from
/// the green "Taken" chip so an un-taken upcoming dose is never mistaken for a taken one.
struct UpcomingChip: View {
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "clock")
                .font(.system(size: 9, weight: .bold))
            if !compact {
                Text("Upcoming")
                    .font(.caption2.weight(.semibold))
            }
        }
        .padding(.horizontal, compact ? 5 : 7)
        .padding(.vertical, 3)
        .background(Color.blue.opacity(0.15))
        .foregroundStyle(Color.blue)
        .clipShape(Capsule())
        .accessibilityLabel("Upcoming")
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
