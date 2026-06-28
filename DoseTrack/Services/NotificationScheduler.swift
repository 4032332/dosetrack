// DoseTrack/Services/NotificationScheduler.swift
import UserNotifications
import CoreData
import Foundation

/// Schedules UNCalendarNotificationTrigger-based reminders for all active medications.
/// Calendar triggers survive device restarts and timezone changes.
final class NotificationScheduler {

    static let shared = NotificationScheduler()
    private init() {}

    private let center = UNUserNotificationCenter.current()

    // iOS allows a maximum of 64 pending notifications per app.
    // We schedule 30 days ahead and refresh each app open.
    private let daysAhead = 30

    // MARK: - Public API

    /// Refresh the full notification queue for all active medications.
    /// Call on every app foreground and after any medication/schedule change.
    func refreshAll(context: NSManagedObjectContext) {
        let request = NSFetchRequest<Medication>(entityName: "Medication")
        request.predicate = NSPredicate(format: "isActive == YES")

        guard let medications = try? context.fetch(request) else { return }

        // Cancel everything then rebuild (simplest correctness guarantee)
        center.removeAllPendingNotificationRequests()

        let now = Date()
        let calendar = Calendar.current
        guard let horizon = calendar.date(byAdding: .day, value: daysAhead, to: now) else { return }

        var requests: [UNNotificationRequest] = []

        for medication in medications {
            for schedule in medication.schedulesArray where schedule.isEnabled {
                if schedule.wrappedFrequency == "custom" && schedule.intervalDays > 1 {
                    // Interval-based schedule (e.g. contraceptives) — compute from last DoseLog
                    let intervalRequests = buildIntervalRequests(
                        for: medication,
                        schedule: schedule,
                        now: now,
                        calendar: calendar
                    )
                    requests.append(contentsOf: intervalRequests)
                } else {
                    let scheduleRequests = buildRequests(
                        for: medication,
                        schedule: schedule,
                        from: now,
                        to: horizon,
                        calendar: calendar
                    )
                    requests.append(contentsOf: scheduleRequests)
                }
            }
        }

        // iOS cap: 64 pending notifications. Sort by fire date and take earliest.
        let sorted = requests.prefix(64)
        for req in sorted {
            center.add(req) { _ in }
        }

        UserDefaults.standard.set(Date(), forKey: Constants.UserDefaultsKeys.lastNotificationRefresh)
    }

    /// Cancel all pending notifications for a single medication.
    func cancelNotifications(for medication: Medication) {
        var ids: [String] = []
        for schedule in medication.schedulesArray {
            ids.append(contentsOf: schedule.notificationIdsArray)
        }
        if !ids.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    /// Schedule a one-time snooze notification for `minutes` from now.
    func scheduleSnooze(
        medicationId: String,
        medicationName: String,
        dosage: String,
        scheduleId: String,
        scheduledAt: Date,
        minutes: Int
    ) {
        let content = makeContent(
            medicationName: medicationName,
            dosage: dosage,
            medicationId: medicationId,
            scheduleId: scheduleId,
            scheduledAt: scheduledAt
        )

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: Double(minutes * 60),
            repeats: false
        )
        let id = "snooze.\(medicationId).\(UUID().uuidString)"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request) { _ in }
    }

    // MARK: - Private

    private func buildRequests(
        for medication: Medication,
        schedule: Schedule,
        from start: Date,
        to end: Date,
        calendar: Calendar
    ) -> [UNNotificationRequest] {
        var requests: [UNNotificationRequest] = []
        var ids: [String] = []

        var cursor = start
        while cursor <= end {
            let weekday = calendar.component(.weekday, from: cursor) // 1=Sun..7=Sat

            if isDue(schedule: schedule, onWeekday: weekday) {
                var components = calendar.dateComponents([.year, .month, .day], from: cursor)
                components.hour = Int(schedule.hour)
                components.minute = Int(schedule.minute)
                components.second = 0

                guard let fireDate = calendar.date(from: components),
                      fireDate > start else {
                    cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? end
                    continue
                }

                let id = notificationId(medicationId: medication.id, schedule: schedule, fireDate: fireDate)
                ids.append(id)

                let content = makeContent(
                    medicationName: medication.wrappedName,
                    dosage: medication.wrappedDosage,
                    medicationId: medication.id?.uuidString ?? "",
                    scheduleId: schedule.id?.uuidString ?? "",
                    scheduledAt: fireDate
                )

                // UNCalendarNotificationTrigger — survives device restarts
                let triggerComponents = calendar.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: fireDate
                )
                let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
                requests.append(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            }

            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? end
        }

        // Persist ids back onto the schedule so we can cancel later
        // (best-effort; main context save not guaranteed here)
        schedule.notificationIdsArray = ids

        return requests
    }

    private func isDue(schedule: Schedule, onWeekday weekday: Int) -> Bool {
        switch schedule.wrappedFrequency {
        case "daily":
            return true
        case "weekly", "custom":
            let days = schedule.daysOfWeekArray
            return days.isEmpty || days.contains(weekday)
        case "as_needed":
            return false
        default:
            return true
        }
    }

    private func makeContent(
        medicationName: String,
        dosage: String,
        medicationId: String,
        scheduleId: String,
        scheduledAt: Date
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = medicationName
        content.body = "Time to take \(dosage)"
        content.sound = .defaultCritical
        content.categoryIdentifier = Constants.Notification.categoryMedicationDue
        content.userInfo = [
            "medicationId": medicationId,
            "scheduleId": scheduleId,
            "scheduledAt": scheduledAt.timeIntervalSince1970
        ]
        return content
    }

    private func notificationId(medicationId: UUID?, schedule: Schedule, fireDate: Date) -> String {
        let medId = medicationId?.uuidString ?? "unknown"
        let schId = schedule.id?.uuidString ?? "unknown"
        let ts = Int(fireDate.timeIntervalSince1970)
        return "dt.\(medId).\(schId).\(ts)"
    }

    // MARK: - Interval-based scheduling (contraceptives, long-interval meds)

    /// Builds due + lead-time notifications for interval-based medications.
    /// Next due date is derived from the most recent "taken" DoseLog.
    private func buildIntervalRequests(
        for medication: Medication,
        schedule: Schedule,
        now: Date,
        calendar: Calendar
    ) -> [UNNotificationRequest] {
        let intervalDays = Int(schedule.intervalDays)
        guard intervalDays > 0 else { return [] }

        // Find the last time this was taken — the DoseLog is the source of truth
        let lastTakenDate: Date
        if let lastLog = medication.doseLogsArray.last(where: { $0.doseStatus == .taken }),
           let loggedAt = lastLog.loggedAt {
            lastTakenDate = loggedAt
        } else {
            // No log yet — treat today as baseline
            lastTakenDate = now
        }

        let intervalSeconds = TimeInterval(intervalDays * 86400)
        let dueDate = lastTakenDate.addingTimeInterval(intervalSeconds)

        var requests: [UNNotificationRequest] = []

        // Due notification (fire on the actual due date)
        if dueDate > now {
            let dueId = "dt.interval.due.\(medication.id?.uuidString ?? "").\(Int(dueDate.timeIntervalSince1970))"
            let content = makeContent(
                medicationName: medication.wrappedName,
                dosage: "due today",
                medicationId: medication.id?.uuidString ?? "",
                scheduleId: schedule.id?.uuidString ?? "",
                scheduledAt: dueDate
            )
            content.title = medication.wrappedName
            content.body = "Your \(medication.wrappedName) is due today."
            let triggerComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
            requests.append(UNNotificationRequest(identifier: dueId, content: content, trigger: trigger))
        }

        // Lead-time warning notification
        let lead = Constants.Contraceptive.leadDays(for: intervalDays)
        if lead > 0 {
            let warnDate = dueDate.addingTimeInterval(-TimeInterval(lead * 86400))
            if warnDate > now {
                let warnId = "dt.interval.warn.\(medication.id?.uuidString ?? "").\(Int(dueDate.timeIntervalSince1970))"
                let content = UNMutableNotificationContent()
                content.title = "\(medication.wrappedName) Due Soon"
                content.body = "Your \(medication.wrappedName) is due in \(lead) days."
                content.sound = .default
                content.categoryIdentifier = Constants.Notification.categoryMedicationDue
                content.userInfo = [
                    "medicationId": medication.id?.uuidString ?? "",
                    "scheduleId": schedule.id?.uuidString ?? "",
                    "scheduledAt": dueDate.timeIntervalSince1970
                ]
                let triggerComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: warnDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
                requests.append(UNNotificationRequest(identifier: warnId, content: content, trigger: trigger))
            }
        }

        return requests
    }
}
