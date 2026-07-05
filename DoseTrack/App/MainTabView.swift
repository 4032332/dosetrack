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
        .zIndex(0)
        .safeAreaInset(edge: .top) {
            if !caregiverManager.overseenPatients.isEmpty {
                Button {
                    showingAccountSwitcher = true
                } label: {
                    HStack(spacing: 6) {
                        Text(activeAccount.activeDisplayName)
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
                }
                .padding(.top, 4)
                .frame(maxWidth: .infinity)
                .background(.bar)
                // Explicitly behind the TabView's own content (zIndex 0 above), so that a
                // screen's own toolbar menus (e.g. History's Export CSV/PDF menu) always
                // composite in front of this bar instead of appearing clipped/hidden behind
                // it — this safeAreaInset bar sits with zero clearance above each screen's
                // nav bar, and without this the two competed for the same layer.
                .zIndex(-1)
            }
        }
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
