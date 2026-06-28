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
                let dosage = med.value(forKey: "dosage") as? String,
                let colorHex = med.value(forKey: "colorHex") as? String,
                let schedules = med.value(forKey: "schedules") as? Set<NSManagedObject>
            else { continue }

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

                watchMedications.append([
                    "id": medId,
                    "name": name,
                    "dosage": dosage,
                    "colorHex": colorHex,
                    "scheduledAt": scheduledAt.timeIntervalSince1970,
                    "isTaken": isTaken,
                    "scheduleId": scheduleId
                ])
            }
        }

        watchMedications.sort {
            ($0["scheduledAt"] as! Double) < ($1["scheduledAt"] as! Double)
        }

        // Build Codable array to send
        let sendable: [[String: Any]] = watchMedications
        guard let data = try? JSONSerialization.data(withJSONObject: sendable) else { return }

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(
                ["type": "medicationSync", "medications": data],
                replyHandler: nil,
                errorHandler: { _ in
                    // Fallback to application context for background delivery
                    try? WCSession.default.updateApplicationContext(["medications": data])
                }
            )
        } else {
            try? WCSession.default.updateApplicationContext(["medications": data])
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
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isWatchReachable = session.isReachable
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard message["type"] as? String == "doseConfirmation" else { return }
        Task { @MainActor [weak self] in
            guard let self, let ctx = self.viewContext else { return }
            self.handleDoseConfirmation(message, context: ctx)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        guard let pending = applicationContext["pendingConfirmations"] as? [[String: Any]] else { return }
        Task { @MainActor [weak self] in
            guard let self, let ctx = self.viewContext else { return }
            for msg in pending {
                self.handleDoseConfirmation(msg, context: ctx)
            }
        }
    }
}
