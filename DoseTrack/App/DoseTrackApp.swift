// DoseTrack/App/DoseTrackApp.swift
import SwiftUI

@main
struct DoseTrackApp: App {
    @StateObject private var persistence = PersistenceController.shared
    @StateObject private var subscriptionManager = SubscriptionManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistence.viewContext)
                .environmentObject(subscriptionManager)
                .onChange(of: subscriptionManager.isProSubscriber) { _, isPro in
                    persistence.reconfigure(isPro: isPro)
                }
        }
    }
}
