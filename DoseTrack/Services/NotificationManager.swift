// DoseTrack/Services/NotificationManager.swift
import UserNotifications
import UIKit

@MainActor
final class NotificationManager: NSObject, ObservableObject {

    static let shared = NotificationManager()

    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private override init() {}

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge, .criticalAlert])
            await refreshStatus()
            return granted
        } catch {
            return false
        }
    }

    func refreshStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    // MARK: - Category Registration

    func registerCategories() {
        let takeDose = UNNotificationAction(
            identifier: Constants.Notification.actionTakeDose,
            title: "Taken ✓",
            options: []
        )
        let skipDose = UNNotificationAction(
            identifier: Constants.Notification.actionSkipDose,
            title: "Skip",
            options: []
        )
        let snooze30 = UNNotificationAction(
            identifier: Constants.Notification.actionSnooze30,
            title: "Snooze 30 min",
            options: []
        )

        let category = UNNotificationCategory(
            identifier: Constants.Notification.categoryMedicationDue,
            actions: [takeDose, skipDose, snooze30],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // MARK: - Test Notification

    func sendTestNotification() async {
        let content = UNMutableNotificationContent()
        content.title = "DoseTrack Test"
        content.body = "Notifications are working correctly."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        let request = UNNotificationRequest(
            identifier: "com.robbrown.dosetrack.test",
            content: content,
            trigger: trigger
        )

        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Badge

    func clearBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
    }
}
