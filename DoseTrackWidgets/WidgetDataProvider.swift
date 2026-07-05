// DoseTrackWidgets/WidgetDataProvider.swift
// Shared data-access layer for all widget types.
// Reads from the App Group CoreData store — same store(s) as the main app.
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

/// A lightweight, Codable snapshot of who the widget can show data for: the signed-in user
/// themselves, or a patient they oversee as a caregiver. The main app writes the current list
/// of overseen patients into shared UserDefaults (see `CaregiverManager.publishOverseenPatientsForWidgets`)
/// since the widget extension has no Supabase session of its own to fetch this live.
struct WidgetAccountOption: Codable, Identifiable, Equatable {
    /// nil represents "the signed-in user's own account".
    let id: String?
    let name: String

    static let ownAccount = WidgetAccountOption(id: nil, name: "You")
}

enum WidgetAccountStore {
    static let userDefaultsKey = "widgetOverseenPatients"
    /// Matches `Constants.AppGroup.identifier` in the main app target. Kept as a local literal
    /// here rather than sharing Constants.swift across targets, to avoid pulling unrelated
    /// main-app-only enums (StoreKit product IDs, contraceptive presets, etc.) into the widget.
    static let appGroupIdentifier = "group.com.robbrown.dosetrack"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    /// Called by the main app whenever the caregiver's list of overseen patients changes.
    static func publish(_ patients: [WidgetAccountOption]) {
        guard let data = try? JSONEncoder().encode(patients) else { return }
        defaults?.set(data, forKey: userDefaultsKey)
    }

    /// Read by the widget extension when building the "which account?" configuration options.
    static func overseenPatients() -> [WidgetAccountOption] {
        guard let data = defaults?.data(forKey: userDefaultsKey),
              let patients = try? JSONDecoder().decode([WidgetAccountOption].self, from: data)
        else { return [] }
        return patients
    }
}

final class WidgetDataProvider {

    static let shared = WidgetDataProvider()
    private init() {}

    /// Loaded once and reused by every container this class creates (the caregiver's own store
    /// AND every per-patient store) — mirrors `PersistenceController.sharedModel` in the main
    /// app for the same reason: multiple distinct model instances describing the same entities
    /// causes Core Data's "Multiple NSEntityDescriptions" runtime confusion.
    private static let sharedModel: NSManagedObjectModel = {
        guard let modelURL = Bundle(for: WidgetDataProvider.self).url(forResource: "DoseTrack", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: modelURL) else {
            fatalError("Widget extension could not locate the DoseTrack Core Data model")
        }
        return model
    }()

    private static func storeURL(filename: String) -> URL {
        let groupURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetAccountStore.appGroupIdentifier)
        return (groupURL ?? URL.documentsDirectory).appendingPathComponent(filename)
    }

    private lazy var ownContainer: NSPersistentContainer = makeContainer(filename: "DoseTrack.sqlite")

    /// One container per overseen-patient id, keyed by the patient's userId string — mirrors
    /// `PersistenceController.context(forPatient:)`'s naming so the widget reads the exact same
    /// file the main app already syncs a caregiver's overseen-patient data into.
    private var patientContainers: [String: NSPersistentContainer] = [:]

    private func makeContainer(filename: String) -> NSPersistentContainer {
        let container = NSPersistentContainer(name: "DoseTrack", managedObjectModel: Self.sharedModel)
        let description = NSPersistentStoreDescription(url: Self.storeURL(filename: filename))
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in
            if let error { print("Widget CoreData error (\(filename)): \(error)") }
        }
        return container
    }

    /// `nil` = the signed-in user's own account. Otherwise, the overseen patient's userId string.
    func context(for accountId: String?) -> NSManagedObjectContext {
        guard let accountId else { return ownContainer.viewContext }
        if let existing = patientContainers[accountId] { return existing.viewContext }
        let container = makeContainer(filename: "DoseTrack-caregiver-\(accountId).sqlite")
        patientContainers[accountId] = container
        return container.viewContext
    }

    /// Convenience accessor used by `MarkDoseTakenIntent`, which always acts on the account the
    /// widget it was tapped from is currently configured to show.
    var context: NSManagedObjectContext { ownContainer.viewContext }

    // MARK: - Queries

    /// All dose entries due today, sorted by scheduled time, for the given account
    /// (`nil` = the signed-in user's own account).
    func todayEntries(for accountId: String? = nil) -> [WidgetDoseEntry] {
        let context = context(for: accountId)
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

    /// Next upcoming dose (first untaken entry after now) for the given account.
    func nextDose(for accountId: String? = nil) -> WidgetDoseEntry? {
        let entries = todayEntries(for: accountId)
        return entries.first { !$0.isTaken && $0.scheduledAt > Date() }
            ?? entries.first { !$0.isTaken }
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
