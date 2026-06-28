// DoseTrack/ViewModels/TodayViewModel.swift
import CoreData
import Combine

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

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
        refresh()
    }

    // MARK: - Public

    func refresh() {
        let entries = buildTodayEntries()
        doseEntries = entries.sorted { $0.scheduledAt < $1.scheduledAt }
        totalCount = entries.count
        takenCount = entries.filter { $0.status == .taken }.count
    }

    func markTaken(_ entry: DoseEntry) {
        log(entry: entry, status: .taken)
    }

    func markSkipped(_ entry: DoseEntry) {
        log(entry: entry, status: .skipped)
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

    private func log(entry: DoseEntry, status: DoseStatus) {
        if let existing = entry.existingLog {
            existing.status = status.rawValue
            existing.loggedAt = Date()
        } else {
            DoseLog.create(
                in: context,
                medication: entry.medication,
                scheduledAt: entry.scheduledAt,
                status: status
            )
        }
        try? context.save()
        refresh()
    }

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
