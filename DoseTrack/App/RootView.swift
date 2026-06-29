// DoseTrack/App/RootView.swift
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var watchManager: WatchConnectivityManager
    @Environment(\.managedObjectContext) private var context
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @AppStorage("guestMode") private var guestMode: Bool = false

    // Treat as signed-in if Supabase session exists OR guest mode is active
    private var canProceed: Bool { auth.isSignedIn || guestMode }

    var body: some View {
        Group {
            if !canProceed {
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
        .animation(.easeInOut(duration: 0.25), value: canProceed)
        .animation(.easeInOut(duration: 0.25), value: hasCompletedOnboarding)
        // Listen for anonymous sign-in fallback when Supabase anon auth is disabled
        .onReceive(NotificationCenter.default.publisher(for: .guestModeActivated)) { _ in
            // guestMode AppStorage will trigger re-render automatically
        }
    }
}
