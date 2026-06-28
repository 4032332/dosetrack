// DoseTrackWidgets/MarkDoseTakenIntent.swift
import AppIntents
import CoreData
import Foundation

/// AppIntent that lets users mark a dose as taken directly from a widget button.
/// Runs in the widget extension process — writes to the shared App Group CoreData store.
struct MarkDoseTakenIntent: AppIntent {
    static var title: LocalizedStringResource = "Mark Dose Taken"
    static var description = IntentDescription("Marks a medication dose as taken from the widget.")

    @Parameter(title: "Medication ID") var medicationId: String
    @Parameter(title: "Schedule ID") var scheduleId: String
    @Parameter(title: "Scheduled At") var scheduledAt: Date

    init() {}

    init(medicationId: String, scheduleId: String, scheduledAt: Date) {
        self.medicationId = medicationId
        self.scheduleId = scheduleId
        self.scheduledAt = scheduledAt
    }

    func perform() async throws -> some IntentResult {
        let context = WidgetDataProvider.shared.context

        await context.perform {
            // Find the medication
            let medRequest = NSFetchRequest<NSManagedObject>(entityName: "Medication")
            medRequest.predicate = NSPredicate(format: "id == %@", UUID(uuidString: medicationId) as CVarArg? ?? NSNull())
            medRequest.fetchLimit = 1

            guard let med = try? context.fetch(medRequest).first else { return }

            // Upsert the DoseLog
            let logRequest = NSFetchRequest<NSManagedObject>(entityName: "DoseLog")
            logRequest.predicate = NSPredicate(
                format: "medication == %@ AND scheduledAt == %@",
                med, scheduledAt as NSDate
            )
            logRequest.fetchLimit = 1

            if let existing = try? context.fetch(logRequest).first {
                existing.setValue("taken", forKey: "status")
                existing.setValue(Date(), forKey: "loggedAt")
            } else {
                let log = NSEntityDescription.insertNewObject(forEntityName: "DoseLog", into: context)
                log.setValue(UUID(), forKey: "id")
                log.setValue(med, forKey: "medication")
                log.setValue(scheduledAt, forKey: "scheduledAt")
                log.setValue(Date(), forKey: "loggedAt")
                log.setValue("taken", forKey: "status")
            }

            try? context.save()
        }

        return .result()
    }
}
