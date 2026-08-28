// DoseTrack/Models/DoseLog+Extensions.swift
import CoreData

enum DoseStatus: String, CaseIterable {
    case taken = "taken"
    case skipped = "skipped"
    case missed = "missed"

    var displayName: String {
        switch self {
        case .taken:   return "Taken"
        case .skipped: return "Skipped"
        case .missed:  return "Missed"
        }
    }
}

extension DoseLog {

    // MARK: - Factory

    @discardableResult
    static func create(
        in context: NSManagedObjectContext,
        medication: Medication,
        scheduledAt: Date,
        status: DoseStatus,
        isAsNeeded: Bool = false
    ) -> DoseLog {
        let log = DoseLog(context: context)
        log.id = UUID()
        log.scheduledAt = scheduledAt
        log.loggedAt = Date()
        log.status = status.rawValue
        log.medication = medication
        log.isAsNeeded = isAsNeeded
        return log
    }

    // MARK: - Computed

    var doseStatus: DoseStatus {
        DoseStatus(rawValue: status ?? "missed") ?? .missed
    }

    var wrappedNotes: String { notes ?? "" }

    /// Whether this log should be scored in the headline adherence percentage.
    ///
    /// Two exclusions, both deliberate:
    ///  - **As-needed doses**: never scheduled, so they can't be missed. Counting them as "taken"
    ///    would only ever push the score up, making adherence a measure of how much PRN medication
    ///    someone takes rather than whether they kept to their prescription.
    ///  - **Vitamins and supplements**: a forgotten multivitamin shouldn't read as a missed
    ///    prescription. They still appear in History and get their own take-rate — see
    ///    HistoryViewModel's per-item breakdown — they're just kept out of the headline number.
    var countsTowardAdherence: Bool {
        !isAsNeeded && (medication?.medicationKind ?? .medication) == .medication
    }
}
