// DoseTrack/App/ContentView.swift
import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @State private var selectedTab: Tab = .today

    enum Tab: Hashable {
        case today, medications, history, settings
    }

    var body: some View {
        if !hasCompletedOnboarding {
            OnboardingView()
        } else {
            TabView(selection: $selectedTab) {
                TodayView()
                    .tabItem { Label("Today", systemImage: "house.fill") }
                    .tag(Tab.today)
                    .accessibilityLabel("Today")

                MedicationsView()
                    .tabItem { Label("Medications", systemImage: "pill.fill") }
                    .tag(Tab.medications)
                    .accessibilityLabel("Medications")

                HistoryView()
                    .tabItem { Label("History", systemImage: "calendar") }
                    .tag(Tab.history)
                    .accessibilityLabel("History")

                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gear") }
                    .tag(Tab.settings)
                    .accessibilityLabel("Settings")
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
        .environmentObject(SubscriptionManager())
}
