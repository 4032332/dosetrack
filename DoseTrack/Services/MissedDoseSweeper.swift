// DoseTrack/Services/MissedDoseSweeper.swift
import CoreData

/// Backfills "missed" DoseLog rows for past scheduled doses that were never logged, so History's
/// adherence stats reflect reality instead of silently excluding them. A day with no DoseLog at
/// all previously contributed nothing to the adherence denominator — invisible rather than
/// counted as missed. Only sweeps days strictly before today: today's not-yet-logged doses stay
/// unwritten (TodayViewModel already shows them as a transient "missed" state once overdue,
/// without persisting, so the user still has the rest of the day to log it before it's written to
/// history permanently — a day only "closes" once it's over).
enum MissedDoseSweeper {
    /// How far back to backfill (covers a reasonable "away from the app" gap without walking a
    /// long-running install's entire history on every launch).
    private static let lookbackDays = 90

    static func sweep(context: NSManagedObjectContext, pushUserId: UUID? = nil) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let earliestStart = calendar.date(byAdding: .day, value: -lookbackDays, to: today) else { return }

        let request = NSFetchRequest<Medication>(entityName: "Medication")
        request.predicate = NSPredicate(format: "isActive == YES")
        guard let medications = try? context.fetch(request) else { return }

        var didInsert = false
        var newlyInserted: [DoseLog] = []

        for medication in medications {
            // Never backfill before the medication existed — otherwise a med added yesterday
            // would get 89 days of fabricated "missed" history.
            let lowerBound = max(earliestStart, medication.createdAt.map { calendar.startOfDay(for: $0) } ?? earliestStart)
            guard lowerBound < today else { continue }

            for schedule in medication.schedulesArray where schedule.isEnabled {
                // Interval-based (e.g. contraceptive) schedules aren't "missed" in the same
                // sense — their next due date is derived from the last dose, not a fixed
                // calendar slot — so skip them here, mirroring NotificationScheduler's handling.
                guard !(schedule.wrappedFrequency == "custom" && schedule.intervalDays > 1) else { continue }

                var cursor = lowerBound
                while cursor < today {
                    let weekday = calendar.component(.weekday, from: cursor)
                    if isDue(schedule: schedule, onWeekday: weekday) {
                        var components = calendar.dateComponents([.year, .month, .day], from: cursor)
                        components.hour = Int(schedule.hour)
                        components.minute = Int(schedule.minute)
                        components.second = 0
                        if let scheduledAt = calendar.date(from: components),
                           !alreadyLogged(medication: medication, at: scheduledAt, calendar: calendar) {
                            let log = DoseLog.create(in: context, medication: medication, scheduledAt: scheduledAt, status: .missed)
                            log.updatedAt = Date()
                            didInsert = true
                            newlyInserted.append(log)
                        }
                    }
                    cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? today
                }
            }
        }

        if didInsert {
            context.saveOrReport()
            for log in newlyInserted {
                Task { await SupabaseSyncManager.shared.pushDoseLog(log, forUserId: pushUserId) }
            }
        }
    }

    private static func alreadyLogged(medication: Medication, at scheduledAt: Date, calendar: Calendar) -> Bool {
        medication.doseLogsArray.contains {
            guard let logged = $0.scheduledAt else { return false }
            return calendar.isDate(logged, equalTo: scheduledAt, toGranularity: .minute)
        }
    }

    private static func isDue(schedule: Schedule, onWeekday weekday: Int) -> Bool {
        switch schedule.wrappedFrequency {
        case "daily": return true
        case "weekly", "custom":
            let days = schedule.daysOfWeekArray
            return days.isEmpty || days.contains(weekday)
        default: return true
        }
    }
}
