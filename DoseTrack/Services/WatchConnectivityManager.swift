// DoseTrack/Services/WatchConnectivityManager.swift
// Sends today's medication schedule to Apple Watch and processes dose confirmations received from it.
import WatchConnectivity
import CoreData
import SwiftUI

@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {

    static let shared = WatchConnectivityManager()

    @Published var isWatchReachable: Bool = false

    private var viewContext: NSManagedObjectContext?

    private override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func configure(context: NSManagedObjectContext) {
        self.viewContext = context
    }

    // MARK: - Send medications to Watch

    /// Encodes today's upcoming/pending medications and pushes them to the Watch.
    func syncTodayMedications(context: NSManagedObjectContext) {
        guard WCSession.default.activationState == .activated else { return }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let request: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "Medication")
        request.predicate = NSPredicate(format: "isActive == YES")

        guard let medications = try? context.fetch(request) else { return }

        var watchMedications: [[String: Any]] = []

        for med in medications {
            guard
                let medId = (med.value(forKey: "id") as? UUID)?.uuidString,
                let name = med.value(forKey: "name") as? String,
                let colorHex = med.value(forKey: "colorHex") as? String,
                let schedules = med.value(forKey: "schedules") as? Set<NSManagedObject>,
                let medication = med as? Medication
            else { continue }
            // The full "what to take" summary (e.g. "2 tablets · 1000mg"), not just the raw
            // per-unit strength — see Medication.doseSummary.
            let dosage = medication.doseSummary

            for schedule in schedules {
                guard
                    let scheduleId = (schedule.value(forKey: "id") as? UUID)?.uuidString,
                    let isEnabled = schedule.value(forKey: "isEnabled") as? Bool,
                    isEnabled,
                    let hour = schedule.value(forKey: "hour") as? Int,
                    let minute = schedule.value(forKey: "minute") as? Int
                else { continue }

                var components = calendar.dateComponents([.year, .month, .day], from: Date())
                components.hour = hour
                components.minute = minute
                guard let scheduledAt = calendar.date(from: components),
                      scheduledAt >= startOfDay && scheduledAt < endOfDay else { continue }

                // Check if already logged
                let logRequest: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "DoseLog")
                logRequest.predicate = NSPredicate(
                    format: "medication.id == %@ AND scheduledAt >= %@ AND scheduledAt < %@",
                    medId, startOfDay as CVarArg, endOfDay as CVarArg
                )
                let logs = (try? context.fetch(logRequest)) ?? []
                let isTaken = logs.contains {
                    ($0.value(forKey: "status") as? String) == "taken"
                }

                // A schedule linked to a Daily Routine Time carries its routine name (e.g.
                // "Bedtime"); the watch shows that instead of a clock time, mirroring iOS Today.
                let routineLabel = schedule.value(forKey: "routineLabel") as? String

                var entry: [String: Any] = [
                    "id": medId,
                    "name": name,
                    "dosage": dosage,
                    "colorHex": colorHex,
                    "scheduledAt": scheduledAt.timeIntervalSince1970,
                    "isTaken": isTaken,
                    "scheduleId": scheduleId
                ]
                if let routineLabel { entry["routineLabel"] = routineLabel }
                watchMedications.append(entry)
            }
        }

        watchMedications.sort {
            ($0["scheduledAt"] as! Double) < ($1["scheduledAt"] as! Double)
        }

        // As-needed items travel in their own list, not as pseudo-scheduled entries. They have no
        // schedule and no due time, so squeezing them into `watchMedications` would give them a
        // fabricated `scheduledAt` and make them sortable/completable alongside real doses — which
        // is exactly the confusion the separate section avoids on iOS.
        var watchAsNeeded: [[String: Any]] = []
        for med in medications {
            guard
                let medication = med as? Medication,
                medication.allowsAsNeeded,
                let medId = medication.id?.uuidString
            else { continue }

            let logRequest: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "DoseLog")
            logRequest.predicate = NSPredicate(
                format: "medication.id == %@ AND isAsNeeded == YES AND loggedAt >= %@ AND loggedAt < %@",
                medId, startOfDay as CVarArg, endOfDay as CVarArg
            )
            let takenToday = (try? context.count(for: logRequest)) ?? 0

            watchAsNeeded.append([
                "id": medId,
                "name": medication.wrappedName,
                "dosage": medication.doseSummary,
                "colorHex": medication.wrappedColorHex,
                "unit": medication.wrappedUnit,
                "dosesTakenToday": takenToday,
            ])
        }
        watchAsNeeded.sort { ($0["name"] as! String) < ($1["name"] as! String) }

        // Build Codable arrays to send
        guard let data = try? JSONSerialization.data(withJSONObject: watchMedications) else { return }
        // Sent alongside, never merged: an older watch build simply ignores the extra key.
        let asNeededData = (try? JSONSerialization.data(withJSONObject: watchAsNeeded)) ?? Data()

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(
                ["type": "medicationSync", "medications": data, "asNeeded": asNeededData],
                replyHandler: nil,
                errorHandler: { _ in
                    // Fallback to application context for background delivery
                    try? WCSession.default.updateApplicationContext(
                        ["medications": data, "asNeeded": asNeededData]
                    )
                }
            )
        } else {
            try? WCSession.default.updateApplicationContext(
                ["medications": data, "asNeeded": asNeededData]
            )
        }
    }

    // MARK: - Handle incoming dose confirmation from Watch

    private func handleDoseConfirmation(_ message: [String: Any], context: NSManagedObjectContext) {
        guard
            let medicationIdStr = message["medicationId"] as? String,
            let medicationId = UUID(uuidString: medicationIdStr),
            let scheduledAtTimestamp = message["scheduledAt"] as? Double,
            let loggedAtTimestamp = message["loggedAt"] as? Double,
            let status = message["status"] as? String
        else { return }

        let scheduledAt = Date(timeIntervalSince1970: scheduledAtTimestamp)
        let loggedAt = Date(timeIntervalSince1970: loggedAtTimestamp)

        context.perform {
            // Fetch the medication
            let request: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "Medication")
            request.predicate = NSPredicate(format: "id == %@", medicationId as CVarArg)
            guard let med = try? context.fetch(request).first else { return }

            // Avoid duplicate logs
            let dupCheck: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "DoseLog")
            dupCheck.predicate = NSPredicate(
                format: "medication.id == %@ AND scheduledAt == %@",
                medicationId as CVarArg, scheduledAt as CVarArg
            )
            if let existing = try? context.fetch(dupCheck), !existing.isEmpty { return }

            let log = NSEntityDescription.insertNewObject(forEntityName: "DoseLog", into: context)
            log.setValue(UUID(), forKey: "id")
            log.setValue(scheduledAt, forKey: "scheduledAt")
            log.setValue(loggedAt, forKey: "loggedAt")
            log.setValue(status, forKey: "status")
            log.setValue(med, forKey: "medication")
            try? context.save()
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.isWatchReachable = session.isReachable
            // Activation completing is itself a good moment to push — this is what fires when
            // the phone app launches and WCSession finishes activating, which previously raced
            // against the one-shot sync call in RootView (if activation hadn't finished yet,
            // that first sync's `activationState == .activated` guard silently no-opped it).
            if let context = self.viewContext {
                self.syncTodayMedications(context: context)
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isWatchReachable = session.isReachable
            // The watch app frequently isn't reachable at the exact moment the phone app
            // launches (Bluetooth still connecting, watch app not yet foregrounded) — that's
            // when the old one-shot sync used to fire and never again. Re-push the moment the
            // watch actually becomes reachable so a watch that connects late still catches up
            // without the phone app needing to be relaunched.
            if session.isReachable, let context = self.viewContext {
                self.syncTodayMedications(context: context)
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let type = message["type"] as? String
        guard type == "doseConfirmation" || type == "asNeededDose" else { return }
        Task { @MainActor [weak self] in
            guard let self, let ctx = self.viewContext else { return }
            if type == "asNeededDose" {
                self.handleAsNeededDose(message, context: ctx)
            } else {
                self.handleDoseConfirmation(message, context: ctx)
            }
        }
    }

    /// Records an ad-hoc dose logged on the watch.
    ///
    /// Routed through `DoseLoggingService.logAsNeeded` rather than writing a DoseLog here, so the
    /// watch path picks up supply decrement, the Supabase push and the widget reload identically to
    /// the phone — the exact drift that the shared logging service exists to prevent.
    private func handleAsNeededDose(_ message: [String: Any], context: NSManagedObjectContext) {
        guard
            let medicationIdStr = message["medicationId"] as? String,
            let medicationId = UUID(uuidString: medicationIdStr)
        else { return }
        let doseCount = (message["doseCount"] as? Int) ?? 1

        let request = Medication.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", medicationId as CVarArg)
        guard let med = try? context.fetch(request).first else { return }

        DoseLoggingService.shared.logAsNeeded(
            medication: med,
            doseCount: doseCount,
            notes: nil,   // the watch has no practical note entry; notes are added on the phone
            context: context,
            pushUserId: ActiveAccountResolver.shared.activeUserId
        )
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        guard let pending = applicationContext["pendingConfirmations"] as? [[String: Any]] else { return }
        Task { @MainActor [weak self] in
            guard let self, let ctx = self.viewContext else { return }
            for msg in pending {
                // The queue carries both kinds — route by type, or an as-needed dose queued while
                // the phone was unreachable would be silently dropped (handleDoseConfirmation
                // requires a scheduledAt that as-needed messages don't carry).
                if msg["type"] as? String == "asNeededDose" {
                    self.handleAsNeededDose(msg, context: ctx)
                } else {
                    self.handleDoseConfirmation(msg, context: ctx)
                }
            }
        }
    }
}
