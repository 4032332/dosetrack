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
        #if DEBUG
        ScreenshotSeeder.seedIfRequested()
        ScreenshotSeeder.selectTabIfRequested()
        #endif
        NotificationManager.shared.registerCategories()
        UNUserNotificationCenter.current().delegate = self
        registerBackgroundTasks()
        // Without this, the task was registered but never actually submitted, so background
        // refresh silently never ran.
        scheduleBackgroundRefresh()
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
        // Under XCTest, the host app still receives UIApplication lifecycle events (e.g. when
        // the simulator regains focus mid test-run). Refreshing here would race unit tests'
        // own `NotificationScheduler.shared.refreshAll` calls against the same real,
        // process-wide `UNUserNotificationCenter`, and would fault in `PersistenceController
        // .shared`'s objects (from `Bundle.main`'s model) interleaved with test-owned
        // in-memory contexts.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

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
        scheduleBackgroundRefresh() // re-arm for next time regardless of this run's outcome

        var didComplete = false
        task.expirationHandler = {
            // The OS reclaimed our time before refreshAll's completion fired. Report failure
            // rather than leaving the task hanging (which the OS would otherwise flag).
            guard !didComplete else { return }
            didComplete = true
            task.setTaskCompleted(success: false)
        }

        let context = PersistenceController.shared.container.newBackgroundContext()
        context.perform {
            NotificationScheduler.shared.refreshAll(context: context) {
                guard !didComplete else { return }
                didComplete = true
                task.setTaskCompleted(success: true)
            }
        }
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

        guard
            let medIdStr = userInfo["medicationId"] as? String,
            let medId = UUID(uuidString: medIdStr),
            let scheduledAtTs = userInfo["scheduledAt"] as? TimeInterval
        else { completionHandler(); return }

        let scheduledAt = Date(timeIntervalSince1970: scheduledAtTs)

        switch response.actionIdentifier {
        case Constants.Notification.actionTakeDose:
            logDose(medicationId: medId, scheduledAt: scheduledAt, status: .taken)
        case Constants.Notification.actionSkipDose:
            logDose(medicationId: medId, scheduledAt: scheduledAt, status: .skipped)
        case Constants.Notification.actionSnooze30:
            snooze(userInfo: userInfo, minutes: 30)
        default: break
        }

        completionHandler()
    }

    /// Delegates to DoseLoggingService (same write path as the Today screen and the widget)
    /// so a dose logged from a notification action gets identical side effects: supply
    /// decrement, Supabase push under the correct account, widget reload. Resolves the
    /// active account itself via ActiveAccountResolver since this handler runs outside
    /// SwiftUI and has no environment to read ActiveAccountContext from.
    private func logDose(medicationId: UUID, scheduledAt: Date, status: DoseStatus) {
        Task { @MainActor in
            let activeId = ActiveAccountResolver.shared.activeUserId
            let context = activeId == nil
                ? PersistenceController.shared.viewContext
                : PersistenceController.shared.context(forPatient: activeId!)

            let req = NSFetchRequest<Medication>(entityName: "Medication")
            req.predicate = NSPredicate(format: "id == %@", medicationId as CVarArg)
            req.fetchLimit = 1
            guard let medication = try? context.fetch(req).first else { return }

            let logReq = NSFetchRequest<DoseLog>(entityName: "DoseLog")
            logReq.predicate = NSPredicate(format: "medication == %@ AND scheduledAt == %@",
                                           medication, scheduledAt as NSDate)
            logReq.fetchLimit = 1
            let existing = try? context.fetch(logReq).first

            guard let schedule = medication.schedulesArray.first(where: { $0.isEnabled }) ?? medication.schedulesArray.first
            else { return }

            DoseLoggingService.shared.log(
                medication: medication, schedule: schedule, scheduledAt: scheduledAt,
                status: status, existingLog: existing, notes: nil,
                context: context, pushUserId: activeId
            )
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
