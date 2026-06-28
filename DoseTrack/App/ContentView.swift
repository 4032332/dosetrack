// DoseTrack/App/ContentView.swift
// ContentView is kept for backward compatibility with previews.
// The real app root is RootView via DoseTrackApp.
import SwiftUI

struct ContentView: View {
    var body: some View {
        RootView()
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
        .environmentObject(SubscriptionManager())
        .environmentObject(AuthManager.shared)
}
