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

        // Count engagement on the same fresh not-taken -> taken transition the supply decrement
        // uses, so re-saving an already-taken dose can't inflate it. Drives the review prompt's
        // eligibility check — see ReviewPromptManager.
        if status == .taken && !wasAlreadyTaken {
            ReviewPromptManager.shared.recordDoseTaken()
        }

        // Decrement supply only on a fresh not-taken -> taken transition.
        if status == .taken && !wasAlreadyTaken && medication.currentCount > 0 {
            let scheduleCount = medication.schedulesArray.filter { $0.isEnabled }.count
            let perDose = SupplyMath.quantityPerDose(
                totalDosesPerDay: medication.totalDosesPerDay,
                enabledScheduleCount: scheduleCount
            )
            medication.currentCount = SupplyMath.decrementedCount(current: medication.currentCount, by: perDose)
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

    /// Logs one or more ad-hoc ("as needed" / PRN) doses the user has just taken.
    ///
    /// Differs from `log` in three ways that matter:
    ///  - There is no `Schedule` and no due time — `scheduledAt` is set to now purely so the row
    ///    sorts into the right day in History; nothing was ever "due".
    ///  - `isAsNeeded` is set, which keeps these rows out of the adherence ratio entirely (see
    ///    `DoseLog.countsTowardAdherence`). A PRN dose can't be missed, so counting it as taken
    ///    would only ever inflate the score.
    ///  - No notification to cancel, since as-needed items are never scheduled to fire.
    ///
    /// - Parameter doseCount: how many doses were taken at once (the sheet lets the user pick).
    ///   Supply decrements by `doseCount × units-per-dose`.
    @discardableResult
    func logAsNeeded(
        medication: Medication,
        doseCount: Int,
        notes: String?,
        at date: Date = Date(),
        context: NSManagedObjectContext,
        pushUserId: UUID?
    ) -> [DoseLog] {
        guard doseCount > 0 else { return [] }
        let now = Date()

        // One row per dose rather than a single row with a count: History, the CSV export and the
        // PDF report all render one line per dose, and a doctor reading "3 doses at 14:05" wants
        // to see three entries, not a quantity column they might miss.
        var logs: [DoseLog] = []
        for _ in 0..<doseCount {
            let log = DoseLog.create(
                in: context,
                medication: medication,
                scheduledAt: date,
                status: .taken,
                isAsNeeded: true
            )
            log.updatedAt = now
            if let notes, !notes.isEmpty { log.notes = notes }
            logs.append(log)
        }

        let consumed = medication.quantityPerDose * Double(doseCount)
        if medication.currentCount > 0 {
            medication.currentCount = SupplyMath.decrementedCount(current: medication.currentCount, by: consumed)
            medication.updatedAt = now
        }

        context.saveOrReport()

        WidgetCenter.shared.reloadAllTimelines()
        Task {
            for log in logs {
                await SupabaseSyncManager.shared.pushDoseLog(log, forUserId: pushUserId)
            }
        }
        WatchConnectivityManager.shared.syncTodayMedications(context: context)

        return logs
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
                totalDosesPerDay: medication.totalDosesPerDay,
                enabledScheduleCount: scheduleCount
            )
            medication.currentCount += perDose
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

    /// Corrects a past log's status from History — e.g. a dose the `MissedDoseSweeper`
    /// auto-marked "missed" that was actually taken, or any other after-the-fact correction.
    /// Marked `isBackdated` so reports and the History detail view can show this was corrected
    /// after the fact rather than checked off on the day — an adherence report should never let
    /// a backdated "taken" read identically to a same-day one, since that's exactly the kind of
    /// silent rewrite that undermines the report's value to a doctor.
    func backdateEdit(
        log: DoseLog,
        newStatus: DoseStatus,
        notes: String?,
        context: NSManagedObjectContext,
        pushUserId: UUID?
    ) {
        guard let medication = log.medication else { return }
        let wasTaken = log.doseStatus == .taken
        let willBeTaken = newStatus == .taken
        let now = Date()

        log.status = newStatus.rawValue
        log.loggedAt = now
        log.updatedAt = now
        log.isBackdated = true
        if let notes { log.notes = notes }

        // Adjust supply for either direction of the taken-ness transition — a backdated edit
        // can move a dose onto "taken" (decrement, matching `log`) or off it (restore, matching
        // `untake`), not just the fresh not-taken -> taken case those two methods each assume.
        if willBeTaken != wasTaken {
            let scheduleCount = medication.schedulesArray.filter { $0.isEnabled }.count
            let perDose = SupplyMath.quantityPerDose(
                totalDosesPerDay: medication.totalDosesPerDay,
                enabledScheduleCount: scheduleCount
            )
            if willBeTaken {
                medication.currentCount = SupplyMath.decrementedCount(current: medication.currentCount, by: perDose)
            } else {
                medication.currentCount += perDose
            }
            medication.updatedAt = now
        }

        context.saveOrReport()

        WidgetCenter.shared.reloadAllTimelines()
        Task { await SupabaseSyncManager.shared.pushDoseLog(log, forUserId: pushUserId) }
    }
}
