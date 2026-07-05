// DoseTrack/App/MainTabView.swift
import SwiftUI

struct MainTabView: View {
    @StateObject private var navigator = TabNavigator.shared
    @EnvironmentObject private var activeAccount: ActiveAccountContext
    @EnvironmentObject private var caregiverManager: CaregiverManager
    @State private var showingAccountSwitcher = false

    enum Tab: Hashable {
        case today, medications, restock, history, settings
    }

    var body: some View {
        TabView(selection: $navigator.selectedTab) {
            TodayView(showingAccountSwitcher: $showingAccountSwitcher)
                .tabItem { Label("Today", systemImage: "house.fill") }
                .tag(Tab.today)

            MedicationsView(showingAccountSwitcher: $showingAccountSwitcher)
                .tabItem { Label("Medications", systemImage: "pill.fill") }
                .tag(Tab.medications)

            RestockView(showingAccountSwitcher: $showingAccountSwitcher)
                .tabItem { Label("Restock", systemImage: "cart.fill") }
                .tag(Tab.restock)

            HistoryView(showingAccountSwitcher: $showingAccountSwitcher)
                .tabItem { Label("History", systemImage: "calendar") }
                .tag(Tab.history)

            SettingsView(showingAccountSwitcher: $showingAccountSwitcher)
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(Tab.settings)
        }
        .environmentObject(navigator)
        .sheet(isPresented: $showingAccountSwitcher) {
            AccountSwitcherView()
                .environmentObject(activeAccount)
                .environmentObject(caregiverManager)
        }
    }
}

#Preview {
    MainTabView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
        .environmentObject(SubscriptionManager())
        .environmentObject(AuthManager.shared)
        .environmentObject(ActiveAccountContext(ownUserId: UUID(), ownDisplayName: "Preview User"))
        .environmentObject(CaregiverManager.shared)
}
