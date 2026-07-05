// DoseTrack/Views/Settings/AppPreferencesView.swift
import SwiftUI

// MARK: - Preferences View

struct AppPreferencesView: View {
    @AppStorage("timeFormat")        private var timeFormat: String = "system"
    @AppStorage("hapticsEnabled")    private var hapticsEnabled: Bool = true
    @AppStorage("showDoseBadge")     private var showDoseBadge: Bool = true
    @AppStorage("compactRows")       private var compactRows: Bool = false
    @AppStorage("healthKitEnabled")  private var healthKitEnabled: Bool = false

    @AppStorage("appearanceOverride") private var appearanceOverride: String = "system"
    @StateObject private var healthKit = HealthKitManager.shared

    var body: some View {
        List {
            // MARK: Appearance
            Section {
                Picker("Appearance", selection: $appearanceOverride) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            } header: {
                Text("Appearance")
            }

            // MARK: Time Format
            Section("Time Format") {
                Picker("Time Format", selection: $timeFormat) {
                    Text("System Default").tag("system")
                    Text("12-hour (1:30 PM)").tag("12h")
                    Text("24-hour (13:30)").tag("24h")
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            // MARK: General
            Section("General") {
                Toggle(isOn: $hapticsEnabled) {
                    Label("Haptic Feedback", systemImage: "iphone.radiowaves.left.and.right")
                }

                Toggle(isOn: $showDoseBadge) {
                    Label("App Badge (pending doses)", systemImage: "app.badge.fill")
                }

                Toggle(isOn: $compactRows) {
                    Label("Compact Dose Rows", systemImage: "list.dash")
                }
            }

            // MARK: Apple Health
            if healthKit.isAvailable {
                Section {
                    Toggle(isOn: $healthKitEnabled) {
                        Label("Sync to Apple Health", systemImage: "heart.fill")
                    }
                    .onChange(of: healthKitEnabled) { _, enabled in
                        if enabled && !healthKit.isAuthorized {
                            Task { await healthKit.requestAuthorization() }
                        }
                    }
                } header: {
                    Text("Apple Health")
                } footer: {
                    Text("When enabled, each dose you mark as taken is logged to Apple Health as a mindfulness session tagged with the medication name.")
                        .font(.caption)
                }
            }
        }
        .scrollIndicators(.visible)
        .navigationTitle("Preferences")
        .navigationBarTitleDisplayMode(.inline)
        // Every preference here is also mirrored to Supabase's user_settings row so it survives
        // reinstalls/other devices (see UserSettingsRow). Without pushing on change, a signed-in
        // (non-guest) user's toggle would appear to work locally but get silently overwritten
        // back to its old value the next time pullAll() ran on launch, since the remote row was
        // never updated to match — this was a real bug caught in manual testing.
        .onChange(of: appearanceOverride) { _, _ in pushSettings() }
        .onChange(of: timeFormat) { _, _ in pushSettings() }
        .onChange(of: hapticsEnabled) { _, _ in pushSettings() }
        .onChange(of: showDoseBadge) { _, _ in pushSettings() }
        .onChange(of: compactRows) { _, _ in pushSettings() }
    }

    private func pushSettings() {
        Task { await SupabaseSyncManager.shared.pushSettings() }
    }
}

#Preview {
    NavigationStack { AppPreferencesView() }
}
