// DoseTrack/App/DoseTrackApp.swift
import SwiftUI

@main
struct DoseTrackApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var persistence = PersistenceController.shared
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @StateObject private var watchManager = WatchConnectivityManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistence.viewContext)
                .environmentObject(subscriptionManager)
                .environmentObject(watchManager)
                .onChange(of: subscriptionManager.isProSubscriber) { _, isPro in
                    persistence.reconfigure(isPro: isPro)
                }
                .onAppear {
                    watchManager.configure(context: persistence.viewContext)
                    watchManager.syncTodayMedications(context: persistence.viewContext)
                }
        }
    }
}
