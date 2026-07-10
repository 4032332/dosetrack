// DoseTrackWatch Watch App/DoseTrackWatchApp.swift
import SwiftUI
import UserNotifications

@main
struct DoseTrackWatchApp: App {

    @StateObject private var connectivityManager = WatchConnectivityReceiver.shared
    @WKApplicationDelegateAdaptor var appDelegate: WatchAppDelegate

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(connectivityManager)
        }
    }
}

class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        registerNotificationCategories()
        // Without setting the delegate, the category/actions below register fine (the
        // Taken/Skip/Snooze buttons DO appear on a notification mirrored to the watch), but
        // tapping them silently did nothing at all — didReceive(response:) below was never
        // being called without this. The watch had no notification-action handling whatsoever;
        // this was the actual gap, not the category registration (which was already correct).
        UNUserNotificationCenter.current().delegate = self
    }

    private func registerNotificationCategories() {
        let takeDose = UNNotificationAction(
            identifier: "TAKE_DOSE",
            title: "Taken ✓",
            options: []
        )
        let skipDose = UNNotificationAction(
            identifier: "SKIP_DOSE",
            title: "Skip",
            options: []
        )
        let snooze = UNNotificationAction(
            identifier: "SNOOZE_30",
            title: "Snooze 30 min",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: "MEDICATION_DUE",
            actions: [takeDose, skipDose, snooze],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension WatchAppDelegate: UNUserNotificationCenterDelegate {

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Handles a Taken/Skip/Snooze tap made directly on a watch notification — previously
    /// nothing on the watch side ever called this, so those taps had no effect (see comment on
    /// applicationDidFinishLaunching). Taken/Skip go through the same
    /// WatchConnectivityReceiver.confirmDose(...) path the in-app dose rows already use, so the
    /// phone gets the confirmation exactly the same way. Snooze re-schedules a local watch
    /// notification 30 minutes out, mirroring NotificationScheduler.scheduleSnooze on iOS —
    /// there's no WCSession round-trip needed for a snooze since nothing is being logged yet.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        defer { completionHandler() }

        guard
            let medicationId = userInfo["medicationId"] as? String,
            let scheduleId = userInfo["scheduleId"] as? String,
            let scheduledAtTs = userInfo["scheduledAt"] as? TimeInterval
        else { return }

        let scheduledAt = Date(timeIntervalSince1970: scheduledAtTs)

        switch response.actionIdentifier {
        case "TAKE_DOSE":
            Task { @MainActor in
                WatchConnectivityReceiver.shared.confirmDose(
                    medicationId: medicationId, scheduleId: scheduleId,
                    scheduledAt: scheduledAt, status: "taken"
                )
            }
        case "SKIP_DOSE":
            Task { @MainActor in
                WatchConnectivityReceiver.shared.confirmDose(
                    medicationId: medicationId, scheduleId: scheduleId,
                    scheduledAt: scheduledAt, status: "skipped"
                )
            }
        case "SNOOZE_30":
            scheduleSnooze(content: response.notification.request.content, minutes: 30)
        default:
            break
        }
    }

    private func scheduleSnooze(content: UNNotificationContent, minutes: Int) {
        guard let mutable = content.mutableCopy() as? UNMutableNotificationContent else { return }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: Double(minutes * 60), repeats: false)
        let request = UNNotificationRequest(
            identifier: "watch.snooze.\(UUID().uuidString)",
            content: mutable,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }
}
