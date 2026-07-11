// DoseTrack/Models/Schedule+Extensions.swift
import CoreData

extension Schedule {

    // MARK: - Factory

    @discardableResult
    static func create(
        in context: NSManagedObjectContext,
        medication: Medication,
        hour: Int16 = 8,
        minute: Int16 = 0,
        frequency: String = "daily"
    ) -> Schedule {
        let schedule = Schedule(context: context)
        schedule.id = UUID()
        schedule.hour = hour
        schedule.minute = minute
        schedule.frequency = frequency
        schedule.intervalDays = 1
        schedule.isEnabled = true
        schedule.medication = medication
        return schedule
    }

    // MARK: - Computed

    /// Decoded days of week. Empty means every day.
    var daysOfWeekArray: [Int] {
        get { (daysOfWeek as? [NSNumber])?.map { $0.intValue } ?? [] }
        set { daysOfWeek = newValue.map { NSNumber(value: $0) } as NSArray }
    }

    var notificationIdsArray: [String] {
        get { (notificationIds as? [NSString])?.map { $0 as String } ?? [] }
        set { notificationIds = newValue as NSArray }
    }

    var timeDescription: String {
        let h = Int(hour)
        let m = Int(minute)
        let components = DateComponents(hour: h, minute: m)
        let date = Calendar.current.date(from: components) ?? Date()
        return date.appFormattedTime
    }

    var wrappedFrequency: String { frequency ?? "daily" }

    /// The Daily Routine Time this schedule was linked to (e.g. "Bedtime", "Wake Up"), if any —
    /// set only when created via GuidedScheduleView's "Link to routine" path. `nil` for schedules
    /// on a manually-chosen or interval-generated time, since those aren't tied to a routine that
    /// could move independently of the schedule's own hour/minute.
    var wrappedRoutineLabel: String? { routineLabel }
}
