// DoseTrack/App/ContentView.swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        Text("DoseTrack — Phase 1 complete")
            .padding()
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
