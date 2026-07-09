// DoseTrack/Views/Settings/DeveloperOptionsView.swift
// Hidden screen for testing Pro/caregiver-gated features on TestFlight without a real
// purchase or a second Supabase account. Reached only by tapping the version number in
// Settings > About seven times, then entering a passcode (see SettingsView). The
// underlying toggles no-op automatically on a real App Store build — see
// BuildEnvironment.isTestFlightOrDebug — so this screen is safe to ship permanently
// rather than needing to be stripped out before submission.
import SwiftUI

struct DeveloperOptionsView: View {
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @EnvironmentObject private var caregiverManager: CaregiverManager

    private enum ProOption: Hashable { case real, forceFree, forcePro }

    private var proOverrideBinding: Binding<ProOption> {
        Binding(
            get: {
                switch subscriptionManager.debugForceProOverride {
                case .some(true):  return .forcePro
                case .some(false): return .forceFree
                case .none:        return .real
                }
            },
            set: { option in
                switch option {
                case .real:      subscriptionManager.debugForceProOverride = nil
                case .forceFree: subscriptionManager.debugForceProOverride = false
                case .forcePro:  subscriptionManager.debugForceProOverride = true
                }
            }
        )
    }

    var body: some View {
        List {
            Section {
                Picker("Subscription", selection: proOverrideBinding) {
                    Text("Real StoreKit status").tag(ProOption.real)
                    Text("Force Free").tag(ProOption.forceFree)
                    Text("Force Pro").tag(ProOption.forcePro)
                }

                Toggle("Caregiver Mode Preview", isOn: Binding(
                    get: { caregiverManager.isDebugCaregiverModeActive },
                    set: { caregiverManager.setDebugCaregiverModeActive($0) }
                ))
            } header: {
                Text("Testing Overrides")
            } footer: {
                Text("Subscription override lets you test Pro-gated features without a real purchase. Caregiver Mode Preview adds a fake \"Test Patient\" to the account switcher so you can see the caregiver interface without a second account. These only work in TestFlight/Xcode builds — they automatically no-op on a real App Store build.")
            }
        }
        .navigationTitle("Developer Options")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        DeveloperOptionsView()
            .environmentObject(SubscriptionManager())
            .environmentObject(CaregiverManager.shared)
    }
}
