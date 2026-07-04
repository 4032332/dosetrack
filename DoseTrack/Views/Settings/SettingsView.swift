// DoseTrack/Views/Settings/SettingsView.swift
import SwiftUI
import CoreData

struct SettingsView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @EnvironmentObject private var auth: AuthManager

    @AppStorage("patientName")           private var patientName: String = ""
    @AppStorage("selectedAvatar")           private var selectedAvatar: String = "milli"
    @AppStorage("customAvatarData")         private var customAvatarDataBase64: String = ""
    private var customPhotoData: Data? {
        customAvatarDataBase64.isEmpty ? nil : Data(base64Encoded: customAvatarDataBase64)
    }
    @AppStorage("defaultSnoozeDuration") private var defaultSnoozeDuration: Int = 30
    @AppStorage("criticalAlertsEnabled") private var criticalAlertsEnabled: Bool = true

    @State private var showingPaywall = false
    @State private var showingDeleteConfirm = false
    @State private var testNotificationSent = false
    @State private var showingSignUp = false

    #if DEBUG
    private enum DebugProOption: Hashable { case real, forceFree, forcePro }

    private var debugProOverrideBinding: Binding<DebugProOption> {
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
    #endif

    var body: some View {
        NavigationStack {
            List {
                // MARK: Guest upgrade prompt
                if auth.isGuest {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("You're using a guest account", systemImage: "person.crop.circle.badge.exclamationmark")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.orange)
                            Text("Create a free account to keep your data if you reinstall or switch devices.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Create Account") { showingSignUp = true }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .padding(.top, 2)
                        }
                        .padding(.vertical, 4)
                    }
                }

                // MARK: Profile & Account (merged)
                Section("Profile") {
                    NavigationLink {
                        ProfileView()
                            .environmentObject(auth)
                    } label: {
                        HStack(spacing: 12) {
                            AvatarBadge(avatarKey: selectedAvatar,
                                        isPro: subscriptionManager.isProSubscriber,
                                        size: 44,
                                        customImageData: customPhotoData)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(patientName.isEmpty ? "Set up your profile" : patientName)
                                    .font(.body.weight(patientName.isEmpty ? .regular : .medium))
                                    .foregroundStyle(patientName.isEmpty ? .secondary : .primary)
                                if subscriptionManager.isProSubscriber {
                                    Text("Milli Pro ✦")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.yellow)
                                } else {
                                    Text(auth.userEmail.isEmpty ? "Guest account" : auth.userEmail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // MARK: Subscription
                Section("Subscription") {
                    if subscriptionManager.isProSubscriber {
                        HStack {
                            Label("Milli Pro", systemImage: "star.fill")
                                .foregroundStyle(.yellow)
                            Spacer()
                            Text("Active ✦")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        }
                        Button {
                            Task { await subscriptionManager.restorePurchases() }
                        } label: {
                            Label("Restore Purchases", systemImage: "arrow.clockwise")
                                .foregroundStyle(.primary)
                        }
                    } else {
                        Button {
                            showingPaywall = true
                        } label: {
                            HStack {
                                Label("Upgrade to Milli Pro", systemImage: "star.fill")
                                    .foregroundStyle(.yellow)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                        .foregroundStyle(.primary)

                        Text("5 medications free forever. Milli Pro unlocks unlimited medications, PDF reports, and family sharing.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // MARK: Notifications
                Section {
                    // Authorization status banner
                    let status = NotificationManager.shared.authorizationStatus
                    if status == .denied {
                        HStack(spacing: 10) {
                            Image(systemName: "bell.slash.fill")
                                .foregroundStyle(.red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Notifications are disabled")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.red)
                                Text("Tap below to enable them in iOS Settings.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    } else if status == .notDetermined {
                        Button {
                            Task {
                                await NotificationManager.shared.requestAuthorization()
                                NotificationScheduler.shared.refreshAll(context: context)
                            }
                        } label: {
                            HStack {
                                Label("Enable Notifications", systemImage: "bell.badge.fill")
                                    .foregroundStyle(Color.accentColor)
                                Spacer()
                            }
                        }
                    } else {
                        HStack(spacing: 10) {
                            Image(systemName: "bell.fill")
                                .foregroundStyle(.green)
                            Text("Notifications enabled")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }

                    Button {
                        sendTestNotification()
                    } label: {
                        HStack {
                            Label(
                                testNotificationSent ? "Test Sent ✓ (background the app)" : "Send Test Notification",
                                systemImage: "bell.fill"
                            )
                            .foregroundStyle(testNotificationSent ? .green : .primary)
                            Spacer()
                        }
                    }
                    .disabled(status == .denied)

                    Toggle(isOn: $criticalAlertsEnabled) {
                        Label("Critical Alerts", systemImage: "exclamationmark.triangle.fill")
                    }
                    .onChange(of: criticalAlertsEnabled) { _, _ in
                        NotificationScheduler.shared.refreshAll(context: context)
                    }

                    HStack {
                        Label("Default Snooze", systemImage: "clock.fill")
                        Spacer()
                        Picker("", selection: $defaultSnoozeDuration) {
                            Text("10 min").tag(10)
                            Text("15 min").tag(15)
                            Text("30 min").tag(30)
                            Text("1 hour").tag(60)
                        }
                        .pickerStyle(.menu)
                    }

                    // Link to iOS notification settings for full control
                    Button {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("iOS Notification Settings", systemImage: "gear.badge")
                            .foregroundStyle(.primary)
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    if NotificationManager.shared.authorizationStatus == .authorized {
                        Text("Test notifications appear when the app is in the background.")
                            .font(.caption)
                    }
                }

                // MARK: Preferences
                Section("Preferences") {
                    NavigationLink {
                        AppPreferencesView()
                    } label: {
                        Label("App Preferences", systemImage: "slider.horizontal.3")
                    }
                }

                // MARK: Data & Privacy
                Section("Data & Privacy") {
                    if subscriptionManager.isProSubscriber {
                        NavigationLink {
                            CaregiverInviteView()
                        } label: {
                            Label("Caregiver", systemImage: "person.2.fill")
                        }
                    }

                    NavigationLink {
                        DisclaimerView()
                    } label: {
                        Label("Privacy & Disclaimer", systemImage: "hand.raised.fill")
                    }
                }

                // MARK: About
                Section("About") {
                    HStack {
                        Label("Version", systemImage: "info.circle.fill")
                        Spacer()
                        Text(Bundle.main.appVersion)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        if let url = URL(string: "https://apps.apple.com/") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Rate DoseTrack", systemImage: "star.bubble.fill")
                            .foregroundStyle(.primary)
                    }

                    Button(role: .destructive) {
                        Task { await auth.signOut() }
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }

                #if DEBUG
                // MARK: Debug (DEBUG builds only — never present in release/TestFlight/App Store)
                Section {
                    Picker("Subscription (debug)", selection: debugProOverrideBinding) {
                        Text("Real StoreKit status").tag(DebugProOption.real)
                        Text("Force Free").tag(DebugProOption.forceFree)
                        Text("Force Pro").tag(DebugProOption.forcePro)
                    }
                } header: {
                    Text("Debug")
                } footer: {
                    Text("Lets you test Pro-gated features without a real purchase. Only compiled into debug builds.")
                }
                #endif

                // MARK: Danger zone
                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Label("Delete All Data", systemImage: "trash.fill")
                    }
                }

                Section {
                    Text("DoseTrack is a reminder tool, not medical advice. Always follow your healthcare provider's instructions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
            }
            .scrollIndicators(.visible)
            .contentMargins(.bottom, 32, for: .scrollContent)
            .navigationTitle("Settings")
            .sheet(isPresented: $showingPaywall) { PaywallView() }
            .sheet(isPresented: $showingSignUp) { AuthView().environmentObject(auth) }
            .confirmationDialog(
                "Delete All Data?",
                isPresented: $showingDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete Everything", role: .destructive) { deleteAllData() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all medications, schedules, and dose history. This cannot be undone.")
            }
        }
    }

    // MARK: - Helpers

    private func sendTestNotification() {
        Task {
            await NotificationManager.shared.sendTestNotification()
            testNotificationSent = true
            try? await Task.sleep(for: .seconds(3))
            testNotificationSent = false
        }
    }

    private func deleteAllData() {
        for entity in ["DoseLog", "Schedule", "Medication"] {
            let req: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: entity)
            try? context.execute(NSBatchDeleteRequest(fetchRequest: req))
        }
        try? context.save()
    }
}

// MARK: - Supporting Types

struct ShareSheetView: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - Disclaimer View

struct DisclaimerView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Medical Disclaimer")
                    .font(.title2.bold())
                Text("DoseTrack is a reminder tool only. It does not provide medical advice, diagnosis, or treatment. Always follow your healthcare provider's instructions regarding medications.")
                Text("Data Privacy")
                    .font(.title2.bold())
                Text("All medication data is stored locally on your device. No personal health information is sent to external servers without your explicit consent. Family sharing (Milli Pro feature) syncs data only with caregivers you explicitly invite.")
                Text("If you have questions about your medications, consult your pharmacist or doctor.")
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Privacy & Disclaimer")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Bundle Extension

private extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

#Preview {
    SettingsView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
        .environmentObject(SubscriptionManager())
        .environmentObject(AuthManager.shared)
}
