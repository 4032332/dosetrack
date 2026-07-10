// DoseTrack/ViewModels/TodayViewModel.swift
import CoreData
import Combine
import WidgetKit

/// An actionable alert shown in the Today screen bottom panel.
enum MedicationAlert: Identifiable {
    case lowRefill(Medication, remaining: Int)
    case upcomingDue(Medication, dueDate: Date, daysRemaining: Int)
    case contraceptiveDue(name: String, dueDate: Date, daysRemaining: Int)

    var id: String {
        switch self {
        case .lowRefill(let med, _):          return "refill-\(med.id?.uuidString ?? "")"
        case .upcomingDue(let med, _, _):     return "due-\(med.id?.uuidString ?? "")"
        case .contraceptiveDue(let name, _, _): return "contra-\(name)"
        }
    }
}

/// Represents a single dose slot on the Today screen.
struct DoseEntry: Identifiable {
    let id: UUID
    let medication: Medication
    let schedule: Schedule
    let scheduledAt: Date
    var status: DoseStatus
    var existingLog: DoseLog?
    /// True for a future dose that hasn't been logged yet. Such a dose has no real status —
    /// it's neither taken nor missed — so the UI shows a neutral "Upcoming" chip and the
    /// adherence count excludes it. Previously these were assigned `.taken` purely for
    /// display, which both rendered a misleading green "Taken" chip and inflated takenCount.
    var isUpcoming: Bool = false
}

@MainActor
final class TodayViewModel: ObservableObject {

    @Published var doseEntries: [DoseEntry] = []
    @Published var takenCount: Int = 0
    @Published var totalCount: Int = 0
    @Published var medicationAlerts: [MedicationAlert] = []
    /// Pulses true→false when the last dose for today is marked taken.
    @Published var celebrateNow: Bool = false

    private var context: NSManagedObjectContext
    private var cancellables = Set<AnyCancellable>()

    init(context: NSManagedObjectContext) {
        self.context = context
        refresh()
        // Refresh when app returns from background — catches overnight date change
        NotificationCenter.default.publisher(for: .appDidBecomeActive)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    // MARK: - Public

    /// Swaps the underlying store this view model reads/writes against (e.g. when a caregiver
    /// switches between their own account and an overseen patient's separate local store) and
    /// refreshes immediately so the UI reflects the new store's data.
    func updateContext(_ newContext: NSManagedObjectContext) {
        guard newContext !== context else { return }
        context = newContext
        refresh()
    }

    func refresh() {
        let entries = buildTodayEntries()
        doseEntries = entries.sorted { $0.scheduledAt < $1.scheduledAt }
        totalCount = entries.count
        // Exclude upcoming (not-yet-taken future) doses — only doses actually logged as taken
        // count toward the daily adherence total.
        takenCount = entries.filter { !$0.isUpcoming && $0.status == .taken }.count
        medicationAlerts = buildAlerts()
    }

    func markTaken(_ entry: DoseEntry) {
        log(entry: entry, status: .taken)
    }

    func markSkipped(_ entry: DoseEntry, reason: String? = nil) {
        log(entry: entry, status: .skipped, notes: reason)
    }

    /// Marks every not-yet-taken entry in `entries` as taken in one pass — used for the
    /// "mark all taken" action on a group of doses due at the same time. Refreshes once at
    /// the end rather than once per entry, so the celebration pulse (and any UI observing
    /// `doseEntries`) doesn't flicker through intermediate partial states.
    func markAllTaken(_ entries: [DoseEntry]) {
        for entry in entries where entry.status != .taken {
            DoseLoggingService.shared.log(
                medication: entry.medication,
                schedule: entry.schedule,
                scheduledAt: entry.scheduledAt,
                status: .taken,
                existingLog: entry.existingLog,
                notes: nil,
                context: context,
                pushUserId: ActiveAccountResolver.shared.activeUserId
            )
        }
        refresh()
        if totalCount > 0 && takenCount == totalCount {
            celebrateNow = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.celebrateNow = false
            }
        }
    }

    private func log(entry: DoseEntry, status: DoseStatus, notes: String? = nil) {
        DoseLoggingService.shared.log(
            medication: entry.medication,
            schedule: entry.schedule,
            scheduledAt: entry.scheduledAt,
            status: status,
            existingLog: entry.existingLog,
            notes: notes,
            context: context,
            pushUserId: ActiveAccountResolver.shared.activeUserId
        )
        refresh()
        // Pulse celebrateNow after refresh so the count is up-to-date
        if status == .taken && totalCount > 0 && takenCount == totalCount {
            celebrateNow = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.celebrateNow = false
            }
        }
    }

    func snooze(_ entry: DoseEntry, minutes: Int = 30) {
        NotificationScheduler.shared.scheduleSnooze(
            medicationId: entry.medication.id?.uuidString ?? "",
            medicationName: entry.medication.wrappedName,
            unit: entry.medication.wrappedUnit,
            scheduleId: entry.schedule.id?.uuidString ?? "",
            scheduledAt: entry.scheduledAt,
            minutes: minutes
        )
    }

    // MARK: - Computed

    var adherencePercent: Int {
        guard totalCount > 0 else { return 100 }
        return Int(Double(takenCount) / Double(totalCount) * 100)
    }

    var allDonToday: Bool {
        totalCount > 0 && takenCount == totalCount
    }

    // MARK: - Private

    private func buildTodayEntries() -> [DoseEntry] {
        let medRequest = Medication.fetchRequest()
        medRequest.predicate = NSPredicate(format: "isActive == YES")
        guard let medications = try? context.fetch(medRequest) else { return [] }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return [] }
        let weekday = calendar.component(.weekday, from: Date())

        let logRequest = DoseLog.fetchRequest()
        logRequest.predicate = NSPredicate(
            format: "scheduledAt >= %@ AND scheduledAt < %@",
            today as NSDate, tomorrow as NSDate
        )
        let todayLogs = (try? context.fetch(logRequest)) ?? []

        var entries: [DoseEntry] = []

        for med in medications {
            for schedule in med.schedulesArray where schedule.isEnabled {
                guard isDueToday(schedule: schedule, weekday: weekday) else { continue }

                var components = calendar.dateComponents([.year, .month, .day], from: Date())
                components.hour = Int(schedule.hour)
                components.minute = Int(schedule.minute)
                guard let scheduledAt = calendar.date(from: components) else { continue }

                let existing = todayLogs.first {
                    $0.medication == med &&
                    calendar.isDate($0.scheduledAt ?? .distantPast, equalTo: scheduledAt, toGranularity: .minute)
                }

                let displayStatus: DoseStatus
                var isUpcoming = false
                if let log = existing {
                    displayStatus = log.doseStatus
                } else if scheduledAt <= Date() {
                    displayStatus = .missed
                } else {
                    // Future dose with no log yet — a distinct "upcoming" state. The status
                    // value here is a placeholder that the UI never renders (it keys off
                    // isUpcoming instead); it's excluded from the taken count in refresh().
                    displayStatus = .taken
                    isUpcoming = true
                }

                entries.append(DoseEntry(
                    id: schedule.id ?? UUID(),
                    medication: med,
                    schedule: schedule,
                    scheduledAt: scheduledAt,
                    status: displayStatus,
                    existingLog: existing,
                    isUpcoming: isUpcoming
                ))
            }
        }

        return entries
    }

    private func buildAlerts() -> [MedicationAlert] {
        let medRequest = Medication.fetchRequest()
        medRequest.predicate = NSPredicate(format: "isActive == YES")
        guard let medications = try? context.fetch(medRequest) else { return [] }

        var alerts: [MedicationAlert] = []

        for med in medications {
            // Uses Medication.isRefillWarning — the single canonical low-supply definition also
            // used by the Medications list icon and Restock urgency colouring. This used to be a
            // separate, looser copy here (`count > 0 && daysLeft < 7`, hardcoded 7 instead of the
            // user's threshold) that disagreed with the other two screens.
            if med.isRefillWarning {
                alerts.append(.lowRefill(med, remaining: Int(med.currentCount)))
            }
        }

        // Contraceptive tracker alert (stored in UserDefaults by ContraceptiveTrackerView)
        let defaults = UserDefaults.standard
        let startInterval = defaults.double(forKey: "contraceptiveStartInterval")
        let durationValue = defaults.integer(forKey: "contraceptiveDurationValue")
        let durationUnit  = defaults.string(forKey: "contraceptiveDurationUnit") ?? "year"
        let contraName    = defaults.string(forKey: "contraceptiveName") ?? "Contraceptive"
        let method        = defaults.string(forKey: "contraceptiveMethod") ?? ""

        if startInterval > 0 && durationValue > 0 && !method.isEmpty {
            let startDate = Date(timeIntervalSince1970: startInterval)
            let cal = Calendar.current
            let dueDate: Date? = {
                switch durationUnit {
                case "day":   return cal.date(byAdding: .day,        value: durationValue, to: startDate)
                case "week":  return cal.date(byAdding: .weekOfYear, value: durationValue, to: startDate)
                case "month": return cal.date(byAdding: .month,      value: durationValue, to: startDate)
                case "year":  return cal.date(byAdding: .year,       value: durationValue, to: startDate)
                default:      return nil
                }
            }()

            if let due = dueDate {
                let today = cal.startOfDay(for: Date())
                let daysRemaining = cal.dateComponents([.day], from: today, to: due).day ?? Int.max
                // Alert when 30 days or less until due (or already overdue)
                if daysRemaining <= 30 {
                    alerts.append(.contraceptiveDue(
                        name: contraName.isEmpty ? method : contraName,
                        dueDate: due,
                        daysRemaining: daysRemaining
                    ))
                }
            }
        }

        return alerts
    }

    private func isDueToday(schedule: Schedule, weekday: Int) -> Bool {
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
}
