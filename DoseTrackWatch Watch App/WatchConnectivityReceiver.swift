// DoseTrackWatch Watch App/WatchConnectivityReceiver.swift
// Receives medication data from the iPhone and sends dose confirmations back.
import WatchConnectivity
import SwiftUI
import Combine

/// Lightweight medication snapshot sent from iPhone to Watch via WatchConnectivity.
struct WatchMedication: Identifiable, Codable {
    let id: String
    let name: String
    let dosage: String
    let colorHex: String
    let scheduledAt: Date
    var isTaken: Bool
    var scheduleId: String
    /// Present when the schedule is linked to a Daily Routine Time (e.g. "Bedtime"); the watch
    /// shows this instead of a clock time, mirroring iOS Today.
    var routineLabel: String? = nil
}

@MainActor
final class WatchConnectivityReceiver: NSObject, ObservableObject {

    static let shared = WatchConnectivityReceiver()

    @Published var medications: [WatchMedication] = []
    @Published var lastUpdated: Date? = nil
    @Published var isPhoneReachable: Bool = false
    /// Pulses true→false when the last dose for the day is confirmed.
    @Published var celebrateNow: Bool = false

    private override init() {
        super.init()
        #if DEBUG
        loadMockDataIfNeeded()
        #endif
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    #if DEBUG
    private func loadMockDataIfNeeded() {
        let cal = Calendar.current
        let today = Date()
        func time(_ h: Int, _ m: Int) -> Date {
            cal.date(bySettingHour: h, minute: m, second: 0, of: today) ?? today
        }
        medications = [
            WatchMedication(id: UUID().uuidString, name: "Metformin",
                            dosage: "500mg", colorHex: "4A90D9",
                            scheduledAt: time(8, 0), isTaken: false, scheduleId: UUID().uuidString),
            WatchMedication(id: UUID().uuidString, name: "Lisinopril",
                            dosage: "10mg", colorHex: "E74C3C",
                            scheduledAt: time(8, 0), isTaken: false, scheduleId: UUID().uuidString),
            WatchMedication(id: UUID().uuidString, name: "Vitamin D",
                            dosage: "1000IU", colorHex: "F39C12",
                            scheduledAt: time(12, 0), isTaken: false, scheduleId: UUID().uuidString),
            WatchMedication(id: UUID().uuidString, name: "Omega-3",
                            dosage: "1000mg", colorHex: "27AE60",
                            scheduledAt: time(18, 0), isTaken: false, scheduleId: UUID().uuidString),
            WatchMedication(id: UUID().uuidString, name: "Metformin",
                            dosage: "500mg", colorHex: "4A90D9",
                            scheduledAt: time(20, 0), isTaken: false, scheduleId: UUID().uuidString),
        ]
        lastUpdated = Date()
    }
    #endif

    // MARK: - Send dose confirmation to iPhone

    func confirmDose(medicationId: String, scheduleId: String, scheduledAt: Date, status: String) {
        #if DEBUG
        // Debug builds (e.g. Watch Simulator, no real WCSession pairing) skip the actual
        // message send and just update local Watch UI state directly.
        if let idx = medications.firstIndex(where: { $0.id == medicationId }) {
            medications[idx].isTaken = (status == "taken")
        }
        // Only celebrate when the last dose is marked taken (not untaken)
        if status == "taken" && medications.allSatisfy({ $0.isTaken }) && !medications.isEmpty {
            celebrateNow = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.celebrateNow = false
            }
        }
        #else
        guard WCSession.default.isReachable else {
            // Store locally for next sync opportunity
            queueConfirmation(medicationId: medicationId, scheduleId: scheduleId,
                              scheduledAt: scheduledAt, status: status)
            return
        }

        let message: [String: Any] = [
            "type": "doseConfirmation",
            "medicationId": medicationId,
            "scheduleId": scheduleId,
            "scheduledAt": scheduledAt.timeIntervalSince1970,
            "status": status,
            "loggedAt": Date().timeIntervalSince1970
        ]
        WCSession.default.sendMessage(message, replyHandler: nil) { error in
            print("WatchConnectivity send error: \(error)")
        }

        // Optimistic update in Watch UI
        if let idx = medications.firstIndex(where: { $0.id == medicationId }) {
            medications[idx].isTaken = (status == "taken")
        }
        // Celebrate only when marking taken and all doses are now done
        if status == "taken" && medications.allSatisfy({ $0.isTaken }) && !medications.isEmpty {
            celebrateNow = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.celebrateNow = false
            }
        }
        #endif
    }

    // MARK: - Queued confirmations (when iPhone not reachable)

    private var pendingConfirmations: [[String: Any]] = []

    private func queueConfirmation(medicationId: String, scheduleId: String,
                                   scheduledAt: Date, status: String) {
        let entry: [String: Any] = [
            "type": "doseConfirmation",
            "medicationId": medicationId,
            "scheduleId": scheduleId,
            "scheduledAt": scheduledAt.timeIntervalSince1970,
            "status": status,
            "loggedAt": Date().timeIntervalSince1970
        ]
        pendingConfirmations.append(entry)
        // Transfer via application context so it arrives when reachable
        try? WCSession.default.updateApplicationContext(["pendingConfirmations": pendingConfirmations])
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityReceiver: WCSessionDelegate {

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.isPhoneReachable = session.isReachable
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isPhoneReachable = session.isReachable
            // Flush any queued confirmations
            if session.isReachable && !self.pendingConfirmations.isEmpty {
                for msg in self.pendingConfirmations {
                    session.sendMessage(msg, replyHandler: nil, errorHandler: nil)
                }
                self.pendingConfirmations.removeAll()
                try? session.updateApplicationContext([:])
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard message["type"] as? String == "medicationSync",
              let data = message["medications"] as? Data,
              let meds = try? JSONDecoder().decode([WatchMedication].self, from: data)
        else { return }

        Task { @MainActor in
            self.medications = meds
            self.lastUpdated = Date()
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        guard let data = applicationContext["medications"] as? Data,
              let meds = try? JSONDecoder().decode([WatchMedication].self, from: data)
        else { return }

        Task { @MainActor in
            self.medications = meds
            self.lastUpdated = Date()
        }
    }
}
