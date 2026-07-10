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
    ///
    /// - Parameter completion: called on the main queue once the queue has been rebuilt.
    ///   Optional — production call sites don't need it, but it makes the async rebuild
    ///   deterministic for tests and for BGAppRefreshTask's `setTaskCompleted`.
    func refreshAll(context: NSManagedObjectContext, completion: (() -> Void)? = nil) {
        let request = NSFetchRequest<Medication>(entityName: "Medication")
        request.predicate = NSPredicate(format: "isActive == YES")

        guard let medications = try? context.fetch(request) else { completion?(); return }

        let now = Date()
        let calendar = Calendar.current
        guard let horizon = calendar.date(byAdding: .day, value: daysAhead, to: now) else {
            completion?(); return
        }

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

        // Sort by fire date and take the earliest 64 (iOS's pending-notification cap) so a
        // medication added later never silently loses all its reminders to one added earlier.
        let fireables = requests.map { req -> Fireable in
            let fireDate = (req.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
                ?? (req.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate()
                ?? now
            return Fireable(id: req.identifier, fireDate: fireDate)
        }
        let keptIds = Set(Self.earliest64(fireables).map(\.id))
        let toAdd = requests.filter { keptIds.contains($0.identifier) }

        // Cancel only the scheduled (dt.*) requests we're about to rebuild — a one-off snooze
        // (snooze.*) isn't rebuilt here, so removing it would silently destroy it.
        center.getPendingNotificationRequests { [weak self] pending in
            guard let self else { completion?(); return }
            let cancelIds = Self.identifiersToCancel(from: pending.map(\.identifier))
            self.center.removePendingNotificationRequests(withIdentifiers: cancelIds)

            let group = DispatchGroup()
            for req in toAdd {
                group.enter()
                self.center.add(req) { _ in group.leave() }
            }
            group.notify(queue: .main) {
                UserDefaults.standard.set(Date(), forKey: Constants.UserDefaultsKeys.lastNotificationRefresh)
                completion?()
            }
        }
    }

    /// Scheduled reminders are namespaced `dt.*`; one-off snoozes are `snooze.*`. A full
    /// refresh must rebuild the former without destroying the latter (snoozes aren't rebuilt).
    static func identifiersToCancel(from pending: [String]) -> [String] {
        pending.filter { $0.hasPrefix("dt.") }
    }

    struct Fireable {
        let id: String
        let fireDate: Date
    }

    /// iOS allows at most 64 pending notifications per app. Keep the earliest-firing ones
    /// across ALL medications, rather than filling the cap from the first medication built.
    static func earliest64(_ items: [Fireable]) -> [Fireable] {
        Array(items.sorted { $0.fireDate < $1.fireDate }.prefix(64))
    }

    /// Whether to use the (loud, bypasses silent mode) critical sound, per the user's
    /// Critical Alerts setting. Actual critical delivery additionally requires the Critical
    /// Alerts entitlement; without it iOS silently downgrades, but the toggle still
    /// meaningfully switches sound/interruption level either way.
    static func useCriticalSound(criticalEnabled: Bool) -> Bool {
        criticalEnabled
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

    /// Whether a taken/skipped DoseLog already exists for this medication at (approximately)
    /// the given fire time — matched to the minute so a logged dose suppresses its reminder.
    static func doseAlreadyLogged(medication: Medication, at fireDate: Date, calendar: Calendar) -> Bool {
        medication.doseLogsArray.contains { log in
            guard let scheduledAt = log.scheduledAt,
                  log.doseStatus == .taken || log.doseStatus == .skipped else { return false }
            return calendar.isDate(scheduledAt, equalTo: fireDate, toGranularity: .minute)
        }
    }

    /// Cancel the pending scheduled reminder for a medication+schedule on a given day — called
    /// the moment a dose is logged taken/skipped so a reminder marked done early never fires.
    /// Matches on the `dt.<medId>.<schId>.` id prefix plus the trigger's own fire day, so it's
    /// robust to any sub-minute mismatch between the logged `scheduledAt` and the built fire date.
    func cancelScheduledNotification(medicationId: String, scheduleId: String, on day: Date) {
        guard !medicationId.isEmpty, !scheduleId.isEmpty else { return }
        let calendar = Calendar.current
        let prefix = "dt.\(medicationId).\(scheduleId)."
        center.getPendingNotificationRequests { [weak self] pending in
            let ids = pending.compactMap { req -> String? in
                guard req.identifier.hasPrefix(prefix),
                      let trigger = req.trigger as? UNCalendarNotificationTrigger,
                      let next = trigger.nextTriggerDate(),
                      calendar.isDate(next, inSameDayAs: day) else { return nil }
                return req.identifier
            }
            if !ids.isEmpty { self?.center.removePendingNotificationRequests(withIdentifiers: ids) }
        }
    }

    /// Schedule a one-time snooze notification for `minutes` from now.
    func scheduleSnooze(
        medicationId: String,
        medicationName: String,
        unit: String,
        scheduleId: String,
        scheduledAt: Date,
        minutes: Int
    ) {
        let content = makeContent(
            medicationName: medicationName,
            unit: unit,
            hour: Calendar.current.component(.hour, from: scheduledAt),
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

                // Don't (re)schedule a reminder for a dose that's already been logged taken or
                // skipped for this exact slot. Without this, a dose marked taken early still had
                // its reminder fire at the due time, and any refresh (app launch) would re-create
                // a reminder that was just cancelled on logging.
                if Self.doseAlreadyLogged(medication: medication, at: fireDate, calendar: calendar) {
                    cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? end
                    continue
                }

                let id = notificationId(medicationId: medication.id, schedule: schedule, fireDate: fireDate)
                ids.append(id)

                let content = makeContent(
                    medicationName: medication.wrappedName,
                    unit: medication.wrappedUnit,
                    hour: Int(schedule.hour),
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
        unit: String,
        hour: Int,
        medicationId: String,
        scheduleId: String,
        scheduledAt: Date
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = medicationName
        content.body = NotificationCopy.randomLine(medicationName: medicationName, unit: unit, hour: hour)
        let criticalEnabled = UserDefaults.standard.object(forKey: "criticalAlertsEnabled") as? Bool ?? true
        if Self.useCriticalSound(criticalEnabled: criticalEnabled) {
            content.sound = .defaultCritical
            content.interruptionLevel = .critical
        } else {
            content.sound = .default
            content.interruptionLevel = .timeSensitive
        }
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
                unit: medication.wrappedUnit,
                hour: calendar.component(.hour, from: dueDate),
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
