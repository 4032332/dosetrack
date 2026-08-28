// DoseTrackTests/MissedDoseSweeperTests.swift
import XCTest
import CoreData
@testable import DoseTrack

final class MissedDoseSweeperTests: XCTestCase {

    var context: NSManagedObjectContext!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).viewContext
    }
    override func tearDownWithError() throws { context = nil }

    func test_sweep_backfillsUnloggedPastDayAsMissed() throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today)!

        let med = Medication.create(in: context, name: "Metformin", dosage: "500mg")
        med.createdAt = calendar.date(byAdding: .day, value: -10, to: today)
        let sched = Schedule.create(in: context, medication: med, hour: 8, minute: 0)
        sched.frequency = "daily"
        try context.save()

        MissedDoseSweeper.sweep(context: context)

        let request = DoseLog.fetchRequest()
        let logs = try context.fetch(request)
        let backfilled = logs.first { calendar.isDate($0.scheduledAt!, inSameDayAs: twoDaysAgo) }
        XCTAssertNotNil(backfilled, "A past day with no log should be backfilled as missed")
        XCTAssertEqual(backfilled?.doseStatus, .missed)
    }

    func test_sweep_doesNotTouchToday() throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let med = Medication.create(in: context, name: "Metformin", dosage: "500mg")
        med.createdAt = calendar.date(byAdding: .day, value: -10, to: today)
        let sched = Schedule.create(in: context, medication: med, hour: 8, minute: 0)
        sched.frequency = "daily"
        try context.save()

        MissedDoseSweeper.sweep(context: context)

        let request = DoseLog.fetchRequest()
        let logs = try context.fetch(request)
        let todaysLog = logs.first { calendar.isDate($0.scheduledAt!, inSameDayAs: today) }
        XCTAssertNil(todaysLog, "Today's not-yet-logged dose must not be backfilled — the day isn't over yet")
    }

    func test_sweep_doesNotDuplicateAlreadyLoggedDose() throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let scheduledAt = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: yesterday)!

        let med = Medication.create(in: context, name: "Metformin", dosage: "500mg")
        med.createdAt = calendar.date(byAdding: .day, value: -10, to: today)
        let sched = Schedule.create(in: context, medication: med, hour: 8, minute: 0)
        sched.frequency = "daily"
        DoseLog.create(in: context, medication: med, scheduledAt: scheduledAt, status: .taken)
        try context.save()

        MissedDoseSweeper.sweep(context: context)

        let request = DoseLog.fetchRequest()
        let logs = try context.fetch(request)
        let yesterdaysLogs = logs.filter { calendar.isDate($0.scheduledAt!, inSameDayAs: yesterday) }
        XCTAssertEqual(yesterdaysLogs.count, 1, "An already-logged dose must not get a duplicate missed row")
        XCTAssertEqual(yesterdaysLogs.first?.doseStatus, .taken)
    }

    func test_sweep_respectsDaysOfWeek() throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let yesterdayWeekday = calendar.component(.weekday, from: yesterday)
        // A weekly schedule that explicitly excludes yesterday's weekday.
        let otherWeekday = yesterdayWeekday == 1 ? 2 : 1

        let med = Medication.create(in: context, name: "Metformin", dosage: "500mg")
        med.createdAt = calendar.date(byAdding: .day, value: -10, to: today)
        let sched = Schedule.create(in: context, medication: med, hour: 8, minute: 0)
        sched.frequency = "weekly"
        sched.daysOfWeekArray = [otherWeekday]
        try context.save()

        MissedDoseSweeper.sweep(context: context)

        let request = DoseLog.fetchRequest()
        let logs = try context.fetch(request)
        let yesterdaysLog = logs.first { calendar.isDate($0.scheduledAt!, inSameDayAs: yesterday) }
        XCTAssertNil(yesterdaysLog, "A day not in the schedule's daysOfWeek should not be backfilled")
    }

    func test_sweep_skipsIntervalBasedSchedules() throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let med = Medication.create(in: context, name: "Contraceptive", dosage: "1", unit: "contraceptive")
        med.createdAt = calendar.date(byAdding: .day, value: -30, to: today)
        let sched = Schedule.create(in: context, medication: med, hour: 9, minute: 0)
        sched.frequency = "custom"
        sched.intervalDays = 12
        try context.save()

        MissedDoseSweeper.sweep(context: context)

        let request = DoseLog.fetchRequest()
        let logs = try context.fetch(request)
        XCTAssertTrue(logs.isEmpty, "Interval-based schedules should not be swept — their due date depends on the last dose, not a fixed calendar slot")
    }

    func test_sweep_doesNotBackfillBeforeMedicationCreated() throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let createdAt = calendar.date(byAdding: .day, value: -1, to: today)!
        let fiveDaysAgo = calendar.date(byAdding: .day, value: -5, to: today)!

        let med = Medication.create(in: context, name: "Metformin", dosage: "500mg")
        med.createdAt = createdAt
        let sched = Schedule.create(in: context, medication: med, hour: 8, minute: 0)
        sched.frequency = "daily"
        try context.save()

        MissedDoseSweeper.sweep(context: context)

        let request = DoseLog.fetchRequest()
        let logs = try context.fetch(request)
        let tooEarly = logs.first { calendar.isDate($0.scheduledAt!, inSameDayAs: fiveDaysAgo) }
        XCTAssertNil(tooEarly, "Must not fabricate missed history from before the medication existed")
    }
}
