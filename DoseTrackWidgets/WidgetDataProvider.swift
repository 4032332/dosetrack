// DoseTrackWidgets/WidgetDataProvider.swift
// Shared data-access layer for all widget types.
// Reads from the App Group CoreData store — same store as the main app.
import Foundation
import CoreData

struct WidgetDoseEntry {
    let medicationName: String
    let dosage: String
    let colorHex: String
    let scheduledAt: Date
    let isTaken: Bool
    let medicationId: String
    let scheduleId: String
}

final class WidgetDataProvider {

    static let shared = WidgetDataProvider()
    private init() {}

    private lazy var container: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "DoseTrack")
        guard let groupURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.robbrown.dosetrack")?
            .appendingPathComponent("DoseTrack.sqlite") else {
            fatalError("Cannot locate App Group container")
        }
        let description = NSPersistentStoreDescription(url: groupURL)
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in
            if let error { print("Widget CoreData error: \(error)") }
        }
        return container
    }()

    var context: NSManagedObjectContext { container.viewContext }

    // MARK: - Queries

    /// All dose entries due today, sorted by scheduled time.
    func todayEntries() -> [WidgetDoseEntry] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return [] }
        let weekday = calendar.component(.weekday, from: Date())

        let medRequest = NSFetchRequest<NSManagedObject>(entityName: "Medication")
        medRequest.predicate = NSPredicate(format: "isActive == YES")
        guard let meds = try? context.fetch(medRequest) else { return [] }

        let logRequest = NSFetchRequest<NSManagedObject>(entityName: "DoseLog")
        logRequest.predicate = NSPredicate(
            format: "scheduledAt >= %@ AND scheduledAt < %@",
            today as NSDate, tomorrow as NSDate
        )
        let logs = (try? context.fetch(logRequest)) ?? []

        var entries: [WidgetDoseEntry] = []

        for med in meds {
            guard
                let schedules = med.value(forKey: "schedules") as? Set<NSManagedObject>,
                let medId = (med.value(forKey: "id") as? UUID)?.uuidString,
                let name = med.value(forKey: "name") as? String,
                let dosage = med.value(forKey: "dosage") as? String,
                let colorHex = med.value(forKey: "colorHex") as? String
            else { continue }

            for schedule in schedules {
                guard
                    let isEnabled = schedule.value(forKey: "isEnabled") as? Bool, isEnabled,
                    let schId = (schedule.value(forKey: "id") as? UUID)?.uuidString,
                    let hour = schedule.value(forKey: "hour") as? Int16,
                    let minute = schedule.value(forKey: "minute") as? Int16,
                    let frequency = schedule.value(forKey: "frequency") as? String
                else { continue }

                guard isDue(frequency: frequency, schedule: schedule, weekday: weekday) else { continue }

                var components = calendar.dateComponents([.year, .month, .day], from: Date())
                components.hour = Int(hour)
                components.minute = Int(minute)
                guard let scheduledAt = calendar.date(from: components) else { continue }

                let isTaken = logs.contains { log in
                    guard
                        let logMed = log.value(forKey: "medication") as? NSManagedObject,
                        let status = log.value(forKey: "status") as? String,
                        let logScheduled = log.value(forKey: "scheduledAt") as? Date
                    else { return false }
                    return logMed == med
                        && status == "taken"
                        && calendar.isDate(logScheduled, equalTo: scheduledAt, toGranularity: .minute)
                }

                entries.append(WidgetDoseEntry(
                    medicationName: name,
                    dosage: dosage,
                    colorHex: colorHex,
                    scheduledAt: scheduledAt,
                    isTaken: isTaken,
                    medicationId: medId,
                    scheduleId: schId
                ))
            }
        }

        return entries.sorted { $0.scheduledAt < $1.scheduledAt }
    }

    /// Next upcoming dose (first untaken entry after now).
    func nextDose() -> WidgetDoseEntry? {
        todayEntries().first { !$0.isTaken && $0.scheduledAt > Date() }
            ?? todayEntries().first { !$0.isTaken }
    }

    // MARK: - Private

    private func isDue(frequency: String, schedule: NSManagedObject, weekday: Int) -> Bool {
        switch frequency {
        case "daily": return true
        case "as_needed": return false
        case "weekly", "custom":
            let days = (schedule.value(forKey: "daysOfWeek") as? NSArray)?
                .compactMap { $0 as? Int } ?? []
            return days.isEmpty || days.contains(weekday)
        default: return true
        }
    }
}
