// DoseTrack/App/AppDelegate.swift
import UIKit
import UserNotifications
import CoreData
import BackgroundTasks

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        NotificationManager.shared.registerCategories()
        UNUserNotificationCenter.current().delegate = self
        registerBackgroundTasks()
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        NotificationManager.shared.clearBadge()
        Task {
            await NotificationManager.shared.refreshStatus()
            NotificationScheduler.shared.refreshAll(
                context: PersistenceController.shared.viewContext
            )
        }
    }

    // MARK: - Background Task Registration

    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.robbrown.dosetrack.refresh",
            using: nil
        ) { task in
            self.handleNotificationRefresh(task: task as! BGAppRefreshTask)
        }
    }

    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.robbrown.dosetrack.refresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60) // 1 hour
        try? BGTaskScheduler.shared.submit(request)
    }

    private func handleNotificationRefresh(task: BGAppRefreshTask) {
        scheduleBackgroundRefresh() // Reschedule for next time

        let context = PersistenceController.shared.viewContext
        NotificationScheduler.shared.refreshAll(context: context)
        task.setTaskCompleted(success: true)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {

    /// Show notifications even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    /// Handle action button taps (Taken / Skip / Snooze) without opening the app
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let context = PersistenceController.shared.viewContext

        guard
            let medIdStr = userInfo["medicationId"] as? String,
            let medId = UUID(uuidString: medIdStr),
            let scheduledAtTs = userInfo["scheduledAt"] as? TimeInterval
        else {
            completionHandler()
            return
        }

        let scheduledAt = Date(timeIntervalSince1970: scheduledAtTs)

        switch response.actionIdentifier {
        case Constants.Notification.actionTakeDose:
            logDose(medicationId: medId, scheduledAt: scheduledAt, status: "taken", context: context)

        case Constants.Notification.actionSkipDose:
            logDose(medicationId: medId, scheduledAt: scheduledAt, status: "skipped", context: context)

        case Constants.Notification.actionSnooze30:
            snooze(userInfo: userInfo, minutes: 30)

        default:
            break
        }

        completionHandler()
    }

    // MARK: - Helpers

    private func logDose(
        medicationId: UUID,
        scheduledAt: Date,
        status: String,
        context: NSManagedObjectContext
    ) {
        context.perform {
            let medRequest = NSFetchRequest<Medication>(entityName: "Medication")
            medRequest.predicate = NSPredicate(format: "id == %@", medicationId as CVarArg)
            medRequest.fetchLimit = 1

            guard let medication = try? context.fetch(medRequest).first else { return }

            // Check for an existing log for this scheduled slot to avoid duplicates
            let logRequest = NSFetchRequest<DoseLog>(entityName: "DoseLog")
            logRequest.predicate = NSPredicate(
                format: "medication == %@ AND scheduledAt == %@",
                medication,
                scheduledAt as NSDate
            )
            logRequest.fetchLimit = 1

            if let existing = try? context.fetch(logRequest).first {
                existing.status = status
                existing.loggedAt = Date()
            } else {
                let log = DoseLog(context: context)
                log.id = UUID()
                log.medication = medication
                log.scheduledAt = scheduledAt
                log.loggedAt = Date()
                log.status = status
            }

            try? context.save()
        }
    }

    private func snooze(userInfo: [AnyHashable: Any], minutes: Int) {
        guard
            let medIdStr = userInfo["medicationId"] as? String,
            let schIdStr = userInfo["scheduleId"] as? String,
            let scheduledAtTs = userInfo["scheduledAt"] as? TimeInterval
        else { return }

        // Fetch medication name for the snooze notification content
        let context = PersistenceController.shared.viewContext
        context.perform {
            let request = NSFetchRequest<Medication>(entityName: "Medication")
            request.predicate = NSPredicate(format: "id == %@", UUID(uuidString: medIdStr) as CVarArg? ?? NSNull())
            request.fetchLimit = 1

            let med = try? context.fetch(request).first
            let name = med?.wrappedName ?? "Medication"
            let dosage = med?.wrappedDosage ?? ""

            NotificationScheduler.shared.scheduleSnooze(
                medicationId: medIdStr,
                medicationName: name,
                dosage: dosage,
                scheduleId: schIdStr,
                scheduledAt: Date(timeIntervalSince1970: scheduledAtTs),
                minutes: minutes
            )
        }
    }
}
