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
        takenCount = entries.filter { $0.status == .taken }.count
        medicationAlerts = buildAlerts()
    }

    func markTaken(_ entry: DoseEntry) {
        log(entry: entry, status: .taken)
    }

    func markSkipped(_ entry: DoseEntry, reason: String? = nil) {
        log(entry: entry, status: .skipped, notes: reason)
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
            dosage: entry.medication.wrappedDosage,
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
                if let log = existing {
                    displayStatus = log.doseStatus
                } else if scheduledAt <= Date() {
                    displayStatus = .missed
                } else {
                    // Future dose — show as "taken" visually so it stands out as upcoming (not missed)
                    displayStatus = .taken
                }

                entries.append(DoseEntry(
                    id: schedule.id ?? UUID(),
                    medication: med,
                    schedule: schedule,
                    scheduledAt: scheduledAt,
                    status: displayStatus,
                    existingLog: existing
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
            // Low refill warning — only show on Today when < 7 days supply remains
            let count = Int(med.currentCount)
            let dpd = max(Int(med.totalDosesPerDay), 1)
            let daysLeft = count / dpd
            if count > 0 && daysLeft < 7 {
                alerts.append(.lowRefill(med, remaining: count))
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
