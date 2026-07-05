// DoseTrack/Services/DoseLoggingService.swift
import CoreData
import WidgetKit

/// The single write path for logging a dose (taken / skipped / missed). Every caller —
/// TodayViewModel, AppDelegate's notification-action handler, the widget intent bridge —
/// goes through here so side effects (supply decrement, Supabase push, widget reload) are
/// identical no matter how a dose is logged. Previously TodayViewModel and AppDelegate had
/// separate, divergent implementations; that drift is the bug this fixes.
@MainActor
final class DoseLoggingService {
    static let shared = DoseLoggingService()
    private init() {}

    /// - Parameter pushUserId: which Supabase user this write belongs to. `nil` = the
    ///   signed-in user's own account. A caregiver acting on a patient MUST pass the
    ///   patient's id (resolve via ActiveAccountResolver at the call site) or the row
    ///   uploads under the wrong user.
    func log(
        medication: Medication,
        schedule: Schedule,
        scheduledAt: Date,
        status: DoseStatus,
        existingLog: DoseLog?,
        notes: String?,
        context: NSManagedObjectContext,
        pushUserId: UUID?
    ) {
        let wasAlreadyTaken = existingLog?.status == DoseStatus.taken.rawValue

        let doseLog: DoseLog
        if let existing = existingLog {
            existing.status = status.rawValue
            existing.loggedAt = Date()
            if let notes { existing.notes = notes }
            doseLog = existing
        } else {
            doseLog = DoseLog.create(in: context, medication: medication, scheduledAt: scheduledAt, status: status)
            if let notes { doseLog.notes = notes }
        }

        // Decrement supply only on a fresh not-taken -> taken transition.
        if status == .taken && !wasAlreadyTaken && medication.currentCount > 0 {
            let scheduleCount = medication.schedulesArray.filter { $0.isEnabled }.count
            let perDose = SupplyMath.quantityPerDose(
                totalDosesPerDay: Int(medication.totalDosesPerDay),
                enabledScheduleCount: scheduleCount
            )
            medication.currentCount = Int32(SupplyMath.decrementedCount(current: Int(medication.currentCount), by: perDose))
        }

        do { try context.save() } catch { assertionFailure("DoseLoggingService save failed: \(error)") }

        WidgetCenter.shared.reloadAllTimelines()
        Task { await SupabaseSyncManager.shared.pushDoseLog(doseLog, forUserId: pushUserId) }
    }
}
