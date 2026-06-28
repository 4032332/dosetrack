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
        status: DoseStatus
    ) -> DoseLog {
        let log = DoseLog(context: context)
        log.id = UUID()
        log.scheduledAt = scheduledAt
        log.loggedAt = Date()
        log.status = status.rawValue
        log.medication = medication
        return log
    }

    // MARK: - Computed

    var doseStatus: DoseStatus {
        DoseStatus(rawValue: status ?? "missed") ?? .missed
    }

    var wrappedNotes: String { notes ?? "" }
}
