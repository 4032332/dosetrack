// DoseTrack/App/MainTabView.swift
import SwiftUI

struct MainTabView: View {
    @StateObject private var navigator = TabNavigator.shared
    @AppStorage("colorTheme") private var colorTheme: String = AppColorTheme.oceanBlue.rawValue
    @AppStorage("appearanceOverride") private var appearanceOverride: String = "system"

    private var activeTheme: AppColorTheme {
        AppColorTheme(rawValue: colorTheme) ?? .oceanBlue
    }

    enum Tab: Hashable {
        case today, medications, restock, history, settings
    }

    var body: some View {
        TabView(selection: $navigator.selectedTab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "house.fill") }
                .tag(Tab.today)

            MedicationsView()
                .tabItem { Label("Medications", systemImage: "pill.fill") }
                .tag(Tab.medications)

            RestockView()
                .tabItem { Label("Restock", systemImage: "cart.fill") }
                .tag(Tab.restock)

            HistoryView()
                .tabItem { Label("History", systemImage: "calendar") }
                .tag(Tab.history)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(Tab.settings)
        }
        .environmentObject(navigator)
        .tint(activeTheme.primary)
        .preferredColorScheme(
            appearanceOverride == "light" ? .light :
            appearanceOverride == "dark"  ? .dark  : nil
        )
    }
}

#Preview {
    MainTabView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
        .environmentObject(SubscriptionManager())
        .environmentObject(AuthManager.shared)
}
