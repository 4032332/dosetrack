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
