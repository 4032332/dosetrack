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
            let now = Date()

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

            let existing = try? context.fetch(logRequest).first
            let wasAlreadyTaken = (existing?.value(forKey: "status") as? String) == "taken"

            if let existing {
                existing.setValue("taken", forKey: "status")
                existing.setValue(now, forKey: "loggedAt")
                // Stamp updatedAt so the main app's foreground push (pushUnsyncedLocalChanges,
                // keyed on updatedAt) syncs this to Supabase, and so the "newer wins" pull
                // merge doesn't silently revert it. Its absence was the core widget bug.
                existing.setValue(now, forKey: "updatedAt")
            } else {
                let log = NSEntityDescription.insertNewObject(forEntityName: "DoseLog", into: context)
                log.setValue(UUID(), forKey: "id")
                log.setValue(med, forKey: "medication")
                log.setValue(scheduledAt, forKey: "scheduledAt")
                log.setValue(now, forKey: "loggedAt")
                log.setValue("taken", forKey: "status")
                log.setValue(now, forKey: "updatedAt")
            }

            // Decrement supply identically to DoseLoggingService so a dose taken from the
            // widget keeps the pill count in step with the in-app flow. Only on a real
            // taken transition (not re-tapping an already-taken dose) and only if there's
            // supply to decrement. Stamping the medication's updatedAt also protects the
            // decrement from being clobbered by the "newer wins" pull merge.
            let currentCount = Int((med.value(forKey: "currentCount") as? Int32) ?? 0)
            if !wasAlreadyTaken && currentCount > 0 {
                let schedules = (med.value(forKey: "schedules") as? Set<NSManagedObject>) ?? []
                let enabledCount = schedules.filter { ($0.value(forKey: "isEnabled") as? Bool) == true }.count
                let dpd = Int((med.value(forKey: "totalDosesPerDay") as? Int32) ?? 1)
                let perDose = SupplyMath.quantityPerDose(totalDosesPerDay: dpd, enabledScheduleCount: enabledCount)
                let newCount = SupplyMath.decrementedCount(current: currentCount, by: perDose)
                med.setValue(Int32(newCount), forKey: "currentCount")
                med.setValue(now, forKey: "updatedAt")
            }

            try? context.save()
        }

        return .result()
    }
}
