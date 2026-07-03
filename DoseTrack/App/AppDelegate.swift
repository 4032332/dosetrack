// DoseTrack/App/AppDelegate.swift
import UIKit
import UserNotifications
import CoreData
import BackgroundTasks
import GoogleSignIn

@objc(AppDelegate)
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

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }

    func application(_ app: UIApplication, open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        NotificationManager.shared.clearBadge()
        Task {
            await NotificationManager.shared.refreshStatus()
            NotificationScheduler.shared.refreshAll(
                context: PersistenceController.shared.viewContext
            )
            // Local reminder authorization already succeeded if we get an
            // .authorized status here. Registering for remote notifications is
            // a separate, additive step needed for caregiver push alerts —
            // it does not affect local medication reminders.
            if NotificationManager.shared.authorizationStatus == .authorized {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
        NotificationCenter.default.post(name: .appDidBecomeActive, object: nil)
    }

    // MARK: - Remote (APNs) Push Registration

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task {
            await PushTokenManager.shared.uploadToken(deviceToken: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("Failed to register for remote notifications: \(error)")
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
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func handleNotificationRefresh(task: BGAppRefreshTask) {
        scheduleBackgroundRefresh()
        let context = PersistenceController.shared.viewContext
        NotificationScheduler.shared.refreshAll(context: context)
        task.setTaskCompleted(success: true)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

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
        else { completionHandler(); return }

        let scheduledAt = Date(timeIntervalSince1970: scheduledAtTs)

        switch response.actionIdentifier {
        case Constants.Notification.actionTakeDose:
            logDose(medicationId: medId, scheduledAt: scheduledAt, status: "taken", context: context)
        case Constants.Notification.actionSkipDose:
            logDose(medicationId: medId, scheduledAt: scheduledAt, status: "skipped", context: context)
        case Constants.Notification.actionSnooze30:
            snooze(userInfo: userInfo, minutes: 30)
        default: break
        }

        completionHandler()
    }

    private func logDose(medicationId: UUID, scheduledAt: Date, status: String, context: NSManagedObjectContext) {
        context.perform {
            let req = NSFetchRequest<Medication>(entityName: "Medication")
            req.predicate = NSPredicate(format: "id == %@", medicationId as CVarArg)
            req.fetchLimit = 1
            guard let medication = try? context.fetch(req).first else { return }

            let logReq = NSFetchRequest<DoseLog>(entityName: "DoseLog")
            logReq.predicate = NSPredicate(format: "medication == %@ AND scheduledAt == %@",
                                           medication, scheduledAt as NSDate)
            logReq.fetchLimit = 1

            if let existing = try? context.fetch(logReq).first {
                existing.status = status; existing.loggedAt = Date()
            } else {
                let log = DoseLog(context: context)
                log.id = UUID(); log.medication = medication
                log.scheduledAt = scheduledAt; log.loggedAt = Date(); log.status = status
            }
            try? context.save()
        }
    }

    private func snooze(userInfo: [AnyHashable: Any], minutes: Int) {
        guard let medIdStr = userInfo["medicationId"] as? String,
              let schIdStr = userInfo["scheduleId"] as? String,
              let ts = userInfo["scheduledAt"] as? TimeInterval else { return }
        let context = PersistenceController.shared.viewContext
        context.perform {
            let req = NSFetchRequest<Medication>(entityName: "Medication")
            req.predicate = NSPredicate(format: "id == %@", UUID(uuidString: medIdStr) as CVarArg? ?? NSNull())
            req.fetchLimit = 1
            let med = try? context.fetch(req).first
            NotificationScheduler.shared.scheduleSnooze(
                medicationId: medIdStr, medicationName: med?.wrappedName ?? "Medication",
                dosage: med?.wrappedDosage ?? "", scheduleId: schIdStr,
                scheduledAt: Date(timeIntervalSince1970: ts), minutes: minutes)
        }
    }
}
