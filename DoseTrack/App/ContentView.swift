// DoseTrack/App/ContentView.swift
import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @State private var selectedTab: Tab = .today

    enum Tab: Hashable {
        case today, medications, history, settings
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "house.fill") }
                .tag(Tab.today)

            MedicationsView()
                .tabItem { Label("Medications", systemImage: "pill.fill") }
                .tag(Tab.medications)

            HistoryPlaceholderView()
                .tabItem { Label("History", systemImage: "calendar") }
                .tag(Tab.history)

            SettingsPlaceholderView()
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(Tab.settings)
        }
    }
}

// Temporary placeholder views until Phase 4
private struct HistoryPlaceholderView: View {
    var body: some View {
        NavigationStack {
            Text("History — coming in Phase 4")
                .navigationTitle("History")
        }
    }
}

private struct SettingsPlaceholderView: View {
    var body: some View {
        NavigationStack {
            Text("Settings — coming in Phase 4")
                .navigationTitle("Settings")
        }
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
        .environmentObject(SubscriptionManager())
}
