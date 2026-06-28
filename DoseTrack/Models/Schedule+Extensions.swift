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
        return date.formatted(date: .omitted, time: .shortened)
    }

    var wrappedFrequency: String { frequency ?? "daily" }
}
