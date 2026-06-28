// DoseTrack/App/RootView.swift
// Entry point that gates on auth → onboarding → main app.
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @EnvironmentObject private var watchManager: WatchConnectivityManager
    @Environment(\.managedObjectContext) private var context
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false

    var body: some View {
        Group {
            if !auth.isSignedIn {
                AuthView()
            } else if !hasCompletedOnboarding {
                OnboardingView()
            } else {
                MainTabView()
                    .onAppear {
                        watchManager.syncTodayMedications(context: context)
                    }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: auth.isSignedIn)
        .animation(.easeInOut(duration: 0.3), value: hasCompletedOnboarding)
    }
}
