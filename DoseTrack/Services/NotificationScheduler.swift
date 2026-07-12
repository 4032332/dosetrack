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
        var pending: [PendingDose] = []

        for medication in medications {
            for schedule in medication.schedulesArray where schedule.isEnabled {
                if schedule.wrappedFrequency == "custom" && schedule.intervalDays > 1 {
                    // Interval-based schedule (e.g. contraceptives) — compute from last DoseLog.
                    // These stay individual (never stacked): they're each a distinct, infrequent event.
                    let intervalRequests = buildIntervalRequests(
                        for: medication,
                        schedule: schedule,
                        now: now,
                        calendar: calendar
                    )
                    requests.append(contentsOf: intervalRequests)
                } else {
                    pending.append(contentsOf: collectDoses(
                        for: medication,
                        schedule: schedule,
                        from: now,
                        to: horizon,
                        calendar: calendar
                    ))
                }
            }
        }

        // Turn the collected doses into requests — grouped into one-per-minute reminders when
        // "Group Reminders" is on, otherwise one request per dose. Also records each schedule's
        // notification ids (for later cancellation).
        requests.append(contentsOf: buildDoseRequests(from: pending, calendar: calendar))

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

    // MARK: - Privacy Focused Notifications

    /// When on, reminders never name the medication — protecting the user's medical info on the
    /// lock screen / Watch. Read fresh each build so a settings change takes effect on reschedule.
    static var privacyMode: Bool { UserDefaults.standard.bool(forKey: "privacyNotifications") }
    static let privacyTitle = "Medication Reminder"
    static let privacyBody = "Please open DoseTrack for more information."

    /// When on, all doses due at the same minute are delivered as ONE grouped reminder instead of
    /// a separate notification per medication.
    static var stackingEnabled: Bool { UserDefaults.standard.bool(forKey: "stackNotifications") }

    /// Groups doses that fire at the same wall-clock minute (the key iOS also collapses a routine
    /// to). Pure + static so the grouping is unit-testable. Returns groups in no particular order.
    static func groupByMinute<T>(_ items: [T], date: (T) -> Date, calendar: Calendar = .current) -> [[T]] {
        let grouped = Dictionary(grouping: items) { item -> String in
            let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date(item))
            return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)-\(c.hour ?? 0)-\(c.minute ?? 0)"
        }
        return Array(grouped.values)
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

    /// One due dose, before it's turned into a (possibly grouped) notification request.
    private struct PendingDose {
        let fireDate: Date
        let medicationName: String
        let unit: String
        let hour: Int
        let medicationId: String
        let scheduleId: String
        let routineLabel: String?
        let schedule: Schedule
    }

    /// Enumerate the due doses for one schedule across the horizon (skipping any already logged),
    /// WITHOUT building notifications yet — so refreshAll can decide whether to group them.
    private func collectDoses(
        for medication: Medication,
        schedule: Schedule,
        from start: Date,
        to end: Date,
        calendar: Calendar
    ) -> [PendingDose] {
        var doses: [PendingDose] = []
        var cursor = start
        while cursor <= end {
            let weekday = calendar.component(.weekday, from: cursor) // 1=Sun..7=Sat
            if isDue(schedule: schedule, onWeekday: weekday) {
                var components = calendar.dateComponents([.year, .month, .day], from: cursor)
                components.hour = Int(schedule.hour)
                components.minute = Int(schedule.minute)
                components.second = 0

                if let fireDate = calendar.date(from: components), fireDate > start,
                   !Self.doseAlreadyLogged(medication: medication, at: fireDate, calendar: calendar) {
                    doses.append(PendingDose(
                        fireDate: fireDate,
                        medicationName: medication.wrappedName,
                        unit: medication.wrappedUnit,
                        hour: Int(schedule.hour),
                        medicationId: medication.id?.uuidString ?? "",
                        scheduleId: schedule.id?.uuidString ?? "",
                        routineLabel: schedule.wrappedRoutineLabel,
                        schedule: schedule
                    ))
                }
            }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? end
        }
        return doses
    }

    /// Build notification requests from collected doses. With "Group Reminders" on, doses sharing a
    /// wall-clock minute become ONE grouped reminder; otherwise it's one request per dose. Records
    /// each schedule's notification ids so they can be cancelled later.
    private func buildDoseRequests(from pending: [PendingDose], calendar: Calendar) -> [UNNotificationRequest] {
        var requests: [UNNotificationRequest] = []
        // schedule objectID → ids, so multi-schedule stacks still let each schedule track its ids.
        var idsBySchedule: [ObjectIdentifier: (schedule: Schedule, ids: [String])] = [:]
        func record(_ schedule: Schedule, _ id: String) {
            let key = ObjectIdentifier(schedule)
            idsBySchedule[key, default: (schedule, [])].ids.append(id)
        }

        func trigger(for fireDate: Date) -> UNCalendarNotificationTrigger {
            let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            return UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        }

        if Self.stackingEnabled {
            for group in Self.groupByMinute(pending, date: { $0.fireDate }, calendar: calendar) {
                guard let first = group.first else { continue }
                if group.count == 1 {
                    requests.append(singleRequest(for: first, trigger: trigger(for: first.fireDate), record: record))
                } else {
                    // One grouped reminder for the whole minute/routine.
                    let stackId = "dt.stack.\(Int(first.fireDate.timeIntervalSince1970))"
                    let content = makeStackedContent(for: group)
                    requests.append(UNNotificationRequest(identifier: stackId, content: content, trigger: trigger(for: first.fireDate)))
                    for dose in group { record(dose.schedule, stackId) }
                }
            }
        } else {
            for dose in pending {
                requests.append(singleRequest(for: dose, trigger: trigger(for: dose.fireDate), record: record))
            }
        }

        // Persist ids back onto each schedule (best-effort; main context save not guaranteed here).
        for (_, entry) in idsBySchedule { entry.schedule.notificationIdsArray = entry.ids }
        return requests
    }

    private func singleRequest(
        for dose: PendingDose,
        trigger: UNCalendarNotificationTrigger,
        record: (Schedule, String) -> Void
    ) -> UNNotificationRequest {
        let id = notificationId(medicationId: dose.schedule.medication?.id, schedule: dose.schedule, fireDate: dose.fireDate)
        record(dose.schedule, id)
        let content = makeContent(
            medicationName: dose.medicationName,
            unit: dose.unit,
            hour: dose.hour,
            medicationId: dose.medicationId,
            scheduleId: dose.scheduleId,
            scheduledAt: dose.fireDate
        )
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }

    /// A grouped reminder for several doses due at once. Names no medication (the whole point is one
    /// reminder for the stack); uses the shared routine name when they all share one ("Bedtime").
    private func makeStackedContent(for group: [PendingDose]) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        let count = group.count
        if Self.privacyMode {
            content.title = Self.privacyTitle
            content.body = Self.privacyBody
        } else {
            let sharedRoutine = group.allSatisfy { $0.routineLabel == group.first?.routineLabel } ? group.first?.routineLabel : nil
            if let routine = sharedRoutine, !routine.isEmpty {
                content.title = "\(routine) medications"
                content.body = "\(count) medications due for your \(routine.lowercased()) routine. Open DoseTrack to take them."
            } else {
                content.title = "Medication Reminder"
                content.body = "You have \(count) medications due now. Open DoseTrack to take them."
            }
        }
        let criticalEnabled = UserDefaults.standard.object(forKey: "criticalAlertsEnabled") as? Bool ?? true
        if Self.useCriticalSound(criticalEnabled: criticalEnabled) {
            content.sound = .defaultCritical
            content.interruptionLevel = .critical
        } else {
            content.sound = .default
            content.interruptionLevel = .timeSensitive
        }
        // No per-dose actions on a stack (they'd be ambiguous) — tapping opens the app to review.
        content.userInfo = ["scheduledAt": (group.first?.fireDate ?? Date()).timeIntervalSince1970]
        return content
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
        if Self.privacyMode {
            // Privacy Focused Notifications: never reveal the medication name on the lock screen /
            // Watch. The reminder just prompts the user to open the app.
            content.title = Self.privacyTitle
            content.body = Self.privacyBody
        } else {
            content.title = medicationName
            content.body = NotificationCopy.randomLine(medicationName: medicationName, unit: unit, hour: hour)
        }
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
            // makeContent already applied privacy mode; only name the medication when it's off.
            if !Self.privacyMode {
                content.title = medication.wrappedName
                content.body = "Your \(medication.wrappedName) is due today."
            }
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
                if Self.privacyMode {
                    content.title = Self.privacyTitle
                    content.body = Self.privacyBody
                } else {
                    content.title = "\(medication.wrappedName) Due Soon"
                    content.body = "Your \(medication.wrappedName) is due in \(lead) days."
                }
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
