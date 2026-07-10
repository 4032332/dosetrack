// DoseTrack/Views/Settings/SettingsView.swift
import SwiftUI
import CoreData
import UserNotifications
import WidgetKit
import StoreKit

struct SettingsView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.requestReview) private var requestReview
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var caregiverManager: CaregiverManager
    @EnvironmentObject private var watchManager: WatchConnectivityManager

    @AppStorage("patientName")           private var patientName: String = ""
    @AppStorage("selectedAvatar")           private var selectedAvatar: String = "milli"
    @AppStorage("customAvatarData")         private var customAvatarDataBase64: String = ""
    private var customPhotoData: Data? {
        customAvatarDataBase64.isEmpty ? nil : Data(base64Encoded: customAvatarDataBase64)
    }
    @AppStorage("defaultSnoozeDuration") private var defaultSnoozeDuration: Int = 30

    @State private var showingPaywall = false
    @State private var showingDeleteConfirm = false
    @State private var testNotificationSent = false
    @State private var showingSignUp = false
    @State private var showingEnterInviteCode = false
    @State private var watchSyncTriggered = false
    @Binding var showingAccountSwitcher: Bool

    // Hidden Developer Options unlock: tap the version row 7x, then enter the passcode.
    @State private var versionTapCount = 0
    @State private var showingDevPasscodePrompt = false
    @State private var devPasscodeEntry = ""
    @State private var devPasscodeError = false
    @State private var showingDeveloperOptions = false

    init(showingAccountSwitcher: Binding<Bool> = .constant(false)) {
        self._showingAccountSwitcher = showingAccountSwitcher
    }

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

                        Text("5 medications free forever. Milli Pro unlocks unlimited medications, PDF reports, and caring for a loved one's medications.")
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
                                // Result unused deliberately — refreshAll runs regardless, and
                                // NotificationManager's own @Published authorizationStatus is
                                // what this screen observes to reflect granted/denied.
                                _ = await NotificationManager.shared.requestAuthorization()
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

                // MARK: Apple Watch
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: watchManager.isWatchReachable ? "applewatch.radiowaves.left.and.right" : "applewatch.slash")
                            .foregroundStyle(watchManager.isWatchReachable ? .green : .secondary)
                        Text(watchManager.isWatchReachable ? "Watch connected" : "Watch not reachable right now")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)

                    Button {
                        watchManager.syncTodayMedications(context: context)
                        watchSyncTriggered = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { watchSyncTriggered = false }
                    } label: {
                        HStack {
                            Label(
                                watchSyncTriggered ? "Sync Sent ✓" : "Sync to Watch",
                                systemImage: "arrow.triangle.2.circlepath"
                            )
                            .foregroundStyle(watchSyncTriggered ? .green : .primary)
                            Spacer()
                        }
                    }
                } header: {
                    Text("Apple Watch")
                } footer: {
                    Text("The watch normally updates on its own whenever a dose is logged or a medication changes. Use this if it looks out of date — e.g. right after pairing, or if the watch wasn't in range earlier.")
                        .font(.caption)
                }

                // MARK: Preferences
                Section("Preferences") {
                    NavigationLink {
                        AppPreferencesView()
                    } label: {
                        Label("App Preferences", systemImage: "slider.horizontal.3")
                    }

                    NavigationLink {
                        MealTimesView()
                    } label: {
                        Label("Daily Routine Times", systemImage: "sun.max")
                    }

                    NavigationLink {
                        ColorCodingView()
                    } label: {
                        Label("Colour Coding", systemImage: "paintpalette.fill")
                    }
                }

                // MARK: Data & Privacy
                Section {
                    // Being cared for is FREE. The patient is often a child or a person with a
                    // disability who shouldn't have to pay — they just generate an invite for
                    // their caregiver. Hidden for guests, who have no real Supabase account to
                    // attach the relationship to.
                    if !auth.isGuest {
                        NavigationLink {
                            CaregiverInviteView()
                        } label: {
                            Label("Invite a Caregiver", systemImage: "person.2.fill")
                        }

                        // Caring for someone else is the PAID capability (Milli Pro): the
                        // caregiver is the one gaining "manage another person's medications," so
                        // they carry the subscription — not the patient. Non-subscribers still
                        // see this row (for discovery) but are routed to the paywall.
                        Button {
                            if subscriptionManager.isProSubscriber {
                                showingEnterInviteCode = true
                            } else {
                                showingPaywall = true
                            }
                        } label: {
                            HStack {
                                Label("Care for Someone", systemImage: "person.badge.shield.checkmark")
                                    .foregroundStyle(.primary)
                                if !subscriptionManager.isProSubscriber {
                                    Spacer()
                                    Image(systemName: "star.fill")
                                        .font(.caption)
                                        .foregroundStyle(.yellow)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Caregiving")
                } footer: {
                    Text("Inviting a caregiver is free. Caring for someone else's medications is a Milli Pro feature.")
                }

                // MARK: Data & Privacy
                Section("Data & Privacy") {
                    NavigationLink {
                        DisclaimerView()
                    } label: {
                        Label("Privacy & Disclaimer", systemImage: "hand.raised.fill")
                    }

                    Link(destination: Constants.ExternalLinks.privacyPolicy) {
                        Label("Privacy Policy", systemImage: "doc.text.fill")
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
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard BuildEnvironment.isTestFlightOrDebug else { return }
                        versionTapCount += 1
                        if versionTapCount >= Constants.DeveloperOptions.unlockTapCount {
                            versionTapCount = 0
                            devPasscodeEntry = ""
                            devPasscodeError = false
                            showingDevPasscodePrompt = true
                        }
                    }

                    Button {
                        // Native in-app rating prompt (previously this opened apps.apple.com's
                        // home page, which did nothing useful). Apple rate-limits how often the
                        // prompt actually appears; the write-review deep link is used post-launch
                        // once the App Store ID is known.
                        requestReview()
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
            .refreshable { await refresh() }
            .navigationTitle("Settings")
            .toolbar {
                if !caregiverManager.overseenPatients.isEmpty {
                    ToolbarItem(placement: .principal) {
                        AccountSwitcherPill(isPresented: $showingAccountSwitcher)
                    }
                }
            }
            .sheet(isPresented: $showingPaywall) { PaywallView() }
            .sheet(isPresented: $showingSignUp) { AuthView().environmentObject(auth) }
            .sheet(isPresented: $showingEnterInviteCode) {
                EnterInviteCodeView().environmentObject(caregiverManager)
            }
            .navigationDestination(isPresented: $showingDeveloperOptions) {
                DeveloperOptionsView()
                    .environmentObject(subscriptionManager)
                    .environmentObject(caregiverManager)
            }
            .alert("Developer Options", isPresented: $showingDevPasscodePrompt) {
                SecureField("Passcode", text: $devPasscodeEntry)
                Button("Cancel", role: .cancel) {}
                Button("Unlock") {
                    if devPasscodeEntry == Constants.DeveloperOptions.passcode {
                        showingDeveloperOptions = true
                    } else {
                        devPasscodeError = true
                        devPasscodeEntry = ""
                        // Re-present the alert on the next run loop turn so the user can
                        // retry — setting isPresented back to true in the same turn a
                        // SwiftUI alert dismisses from is unreliable.
                        DispatchQueue.main.async { showingDevPasscodePrompt = true }
                    }
                }
            } message: {
                Text(devPasscodeError ? "Incorrect passcode." : "Enter the developer passcode.")
            }
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

    private func refresh() async {
        await SupabaseSyncManager.shared.pullAll(context: context)
        _ = await subscriptionManager.checkEntitlement()
    }

    private func sendTestNotification() {
        Task {
            await NotificationManager.shared.sendTestNotification()
            testNotificationSent = true
            try? await Task.sleep(for: .seconds(3))
            testNotificationSent = false
        }
    }

    private func deleteAllData() {
        // Local batch delete, then merge the changes into the live context so the UI updates
        // without a relaunch (NSBatchDeleteRequest bypasses the context by default).
        for entity in ["DoseLog", "Schedule", "Medication"] {
            let req: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: entity)
            let del = NSBatchDeleteRequest(fetchRequest: req)
            del.resultType = .resultTypeObjectIDs
            if let result = try? context.execute(del) as? NSBatchDeleteResult,
               let ids = result.result as? [NSManagedObjectID] {
                NSManagedObjectContext.mergeChanges(fromRemoteContextSave: [NSDeletedObjectsKey: ids], into: [context])
            }
        }
        try? context.save()

        // Cancel all scheduled reminders and refresh widgets so nothing points at deleted data.
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        WidgetCenter.shared.reloadAllTimelines()

        // Delete the cloud copy too, or the next pullAll restores everything.
        Task { await SupabaseSyncManager.shared.deleteAllRemoteData() }
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
        .environmentObject(CaregiverManager.shared)
}
