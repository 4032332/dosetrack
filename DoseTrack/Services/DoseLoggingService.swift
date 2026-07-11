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

        let now = Date()
        let doseLog: DoseLog
        if let existing = existingLog {
            existing.status = status.rawValue
            existing.loggedAt = now
            existing.updatedAt = now
            if let notes { existing.notes = notes }
            doseLog = existing
        } else {
            doseLog = DoseLog.create(in: context, medication: medication, scheduledAt: scheduledAt, status: status)
            doseLog.updatedAt = now
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
            medication.updatedAt = now
        }

        context.saveOrReport()

        // A dose logged (taken or skipped) shouldn't still buzz at its due time — cancel the
        // pending reminder for this exact slot. Handles "I took it early, it reminded me anyway."
        if status == .taken || status == .skipped {
            NotificationScheduler.shared.cancelScheduledNotification(
                medicationId: medication.id?.uuidString ?? "",
                scheduleId: schedule.id?.uuidString ?? "",
                on: scheduledAt
            )
        }

        WidgetCenter.shared.reloadAllTimelines()
        Task { await SupabaseSyncManager.shared.pushDoseLog(doseLog, forUserId: pushUserId) }

        // Keep the Watch app's copy of today's doses current. Previously the phone only ever
        // pushed to the watch once, on app launch (RootView's ActiveSessionView.onAppear) — if
        // the watch wasn't reachable at that exact instant (very common: Bluetooth not yet
        // connected, watch app not foregrounded), nothing ever retried, so the watch was stuck
        // showing "No doses today" indefinitely regardless of how many doses were logged on the
        // phone afterwards. Every log now re-pushes, so the watch catches up the moment it's
        // next reachable (syncTodayMedications itself already falls back to
        // updateApplicationContext for background delivery when not immediately reachable).
        WatchConnectivityManager.shared.syncTodayMedications(context: context)
    }

    /// Reverses a logged dose — used when a user un-takes an accidentally checked-off dose. Deletes
    /// the log, restores the supply that logging "taken" decremented (skipped never decremented, so
    /// only a previously-taken log adds back), and mirrors the same side effects as `log` (widget
    /// reload, Supabase delete, watch re-sync). The pending reminder that `log` cancelled is
    /// restored on the next `NotificationScheduler.refreshAll` (app open) rather than here.
    func untake(
        medication: Medication,
        schedule: Schedule,
        scheduledAt: Date,
        existingLog: DoseLog?,
        context: NSManagedObjectContext,
        pushUserId: UUID?
    ) {
        guard let existingLog else { return }
        let wasTaken = existingLog.status == DoseStatus.taken.rawValue
        let logId = existingLog.id
        let now = Date()

        if wasTaken {
            let scheduleCount = medication.schedulesArray.filter { $0.isEnabled }.count
            let perDose = SupplyMath.quantityPerDose(
                totalDosesPerDay: Int(medication.totalDosesPerDay),
                enabledScheduleCount: scheduleCount
            )
            medication.currentCount += Int32(perDose)
            medication.updatedAt = now
        }

        context.delete(existingLog)
        context.saveOrReport()

        WidgetCenter.shared.reloadAllTimelines()
        if let logId {
            Task { await SupabaseSyncManager.shared.deleteDoseLog(id: logId) }
        }
        WatchConnectivityManager.shared.syncTodayMedications(context: context)
    }
}
