// DoseTrack/App/DoseTrackApp.swift
import SwiftUI
import GoogleSignIn

@main
struct DoseTrackApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var persistence = PersistenceController.shared
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @StateObject private var watchManager = WatchConnectivityManager.shared
    @StateObject private var auth = AuthManager.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, persistence.viewContext)
                .environmentObject(subscriptionManager)
                .environmentObject(watchManager)
                .environmentObject(auth)
                .onChange(of: subscriptionManager.isProSubscriber) { _, isPro in
                    persistence.reconfigure(isPro: isPro)
                }
                .onAppear {
                    watchManager.configure(context: persistence.viewContext)
                }
                .onOpenURL { url in
                    // Handle Google Sign-In redirect URL
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
