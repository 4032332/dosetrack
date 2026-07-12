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

    @AppStorage("patientName")           private var patientName: String = ""
    @AppStorage("selectedAvatar")           private var selectedAvatar: String = "milli"
    @AppStorage("customAvatarData")         private var customAvatarDataBase64: String = ""
    private var customPhotoData: Data? {
        customAvatarDataBase64.isEmpty ? nil : Data(base64Encoded: customAvatarDataBase64)
    }

    @State private var showingPaywall = false
    @State private var showingDeleteConfirm = false
    @State private var showingSignUp = false
    @State private var showingEnterInviteCode = false
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

                // MARK: Profile (profile row + current tier + restore)
                Section {
                    NavigationLink {
                        ProfileView()
                            .environmentObject(auth)
                    } label: {
                        HStack(spacing: 12) {
                            AvatarBadge(avatarKey: selectedAvatar,
                                        isPro: subscriptionManager.isProSubscriber,
                                        size: 44,
                                        customImageData: customPhotoData)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(patientName.isEmpty ? "Set up your profile" : patientName)
                                    .font(.body.weight(patientName.isEmpty ? .regular : .medium))
                                    .foregroundStyle(patientName.isEmpty ? .secondary : .primary)
                                if subscriptionManager.isProSubscriber {
                                    PlusBadge()
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

                    // Current tier row
                    if subscriptionManager.isProSubscriber {
                        HStack {
                            SettingsLabel(title: "DoseTrack Plus", systemImage: "star.fill", tint: Color(hex: "#3B5FCC"))
                            Spacer()
                            Text("Active").foregroundStyle(.secondary).font(.subheadline)
                        }
                    } else {
                        Button {
                            showingPaywall = true
                        } label: {
                            HStack {
                                SettingsLabel(title: "Upgrade to DoseTrack Plus", systemImage: "star.fill", tint: Color(hex: "#3B5FCC"))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                    }

                    Button {
                        Task { await subscriptionManager.restorePurchases() }
                    } label: {
                        SettingsLabel(title: "Restore Purchases", systemImage: "arrow.clockwise", tint: .gray)
                    }
                } header: {
                    Text("Profile")
                } footer: {
                    if !subscriptionManager.isProSubscriber {
                        Text("5 medications free forever. DoseTrack Plus unlocks unlimited medications, PDF reports, and caring for a loved one's medications.")
                            .font(.caption)
                    }
                }

                // MARK: Caregiving
                if !auth.isGuest {
                    Section {
                        NavigationLink {
                            CaregiverInviteView()
                        } label: {
                            SettingsLabel(title: "Invite a Caregiver", systemImage: "person.2.fill", tint: .blue)
                        }

                        // Caring for someone else is the PAID capability (DoseTrack Plus): the
                        // caregiver is the one gaining "manage another person's medications," so
                        // they carry the subscription — not the patient. Non-subscribers still
                        // see this row, ghosted, and tapping routes to the paywall.
                        if subscriptionManager.isProSubscriber {
                            Button { showingEnterInviteCode = true } label: {
                                SettingsLabel(title: "Care for Someone", systemImage: "person.badge.shield.checkmark", tint: .teal)
                            }
                        } else {
                            GhostedProRow(isPro: false, onLockedTap: { showingPaywall = true }) {
                                SettingsLabel(title: "Care for Someone", systemImage: "person.badge.shield.checkmark", tint: .teal)
                            }
                        }
                    } header: {
                        Text("Caregiving")
                    } footer: {
                        Text("Inviting a caregiver is free. Caring for someone else's medications is a DoseTrack Plus feature.")
                    }
                }

                // MARK: Preferences (all navigation rows)
                Section("Preferences") {
                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        SettingsLabel(title: "Notifications", systemImage: "bell.badge.fill", tint: .red)
                    }

                    NavigationLink {
                        AppPreferencesView()
                    } label: {
                        SettingsLabel(title: "App Preferences", systemImage: "slider.horizontal.3", tint: .gray)
                    }

                    NavigationLink {
                        MealTimesView()
                    } label: {
                        SettingsLabel(title: "Routine Preferences", systemImage: "sun.max.fill", tint: .orange)
                    }

                    NavigationLink {
                        ColorCodingView()
                    } label: {
                        SettingsLabel(title: "Medication Preferences", systemImage: "paintpalette.fill", tint: .pink)
                    }

                    NavigationLink {
                        WatchSyncView()
                    } label: {
                        SettingsLabel(title: "Apple Watch Sync", systemImage: "applewatch", tint: .blue)
                    }
                }

                // MARK: About
                Section("About") {
                    HStack {
                        SettingsLabel(title: "Version", systemImage: "info.circle.fill", tint: .gray)
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

                    NavigationLink {
                        DisclaimerView()
                    } label: {
                        SettingsLabel(title: "Privacy & Disclaimer", systemImage: "hand.raised.fill", tint: .gray)
                    }

                    Link(destination: Constants.ExternalLinks.privacyPolicy) {
                        SettingsLabel(title: "Privacy Policy", systemImage: "doc.text.fill", tint: .blue)
                    }

                    Button {
                        // Native in-app rating prompt (previously this opened apps.apple.com's
                        // home page, which did nothing useful). Apple rate-limits how often the
                        // prompt actually appears; the write-review deep link is used post-launch
                        // once the App Store ID is known.
                        requestReview()
                    } label: {
                        SettingsLabel(title: "Rate DoseTrack", systemImage: "star.bubble.fill", tint: .yellow)
                    }

                    Button {
                        Task { await auth.signOut() }
                    } label: {
                        SettingsLabel(title: "Sign Out", systemImage: "rectangle.portrait.and.arrow.right", tint: .gray)
                    }

                    Button {
                        showingDeleteConfirm = true
                    } label: {
                        SettingsLabel(title: "Delete All Data", systemImage: "trash.fill", tint: .red, titleColor: .red)
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

// MARK: - Plus tier badge

/// High-contrast chip marking the DoseTrack Plus tier — replaces the old low-contrast gold text
/// (`Text("… Pro ✦").foregroundStyle(.yellow)`) that was hard to read on a white row for low-vision
/// users. A filled brand-blue capsule with white text passes contrast comfortably.
private struct PlusBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill").font(.system(size: 9, weight: .bold))
            Text("PLUS").font(.system(size: 11, weight: .heavy))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color(hex: "#3B5FCC"), in: Capsule())
    }
}

// MARK: - Notifications sub-screen

/// The notification controls, moved out of the main Settings list into a dedicated "Notifications"
/// row's destination so the Preferences section is a clean set of navigation rows.
private struct NotificationSettingsView: View {
    @Environment(\.managedObjectContext) private var context
    @ObservedObject private var notif = NotificationManager.shared
    @AppStorage("defaultSnoozeDuration") private var defaultSnoozeDuration: Int = 30
    @AppStorage("privacyNotifications") private var privacyNotifications: Bool = false
    @AppStorage("stackNotifications") private var stackNotifications: Bool = false
    @State private var testNotificationSent = false

    var body: some View {
        List {
            Section {
                let status = notif.authorizationStatus
                if status == .denied {
                    HStack(spacing: 10) {
                        Image(systemName: "bell.slash.fill").foregroundStyle(.red)
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
                            _ = await NotificationManager.shared.requestAuthorization()
                            NotificationScheduler.shared.refreshAll(context: context)
                        }
                    } label: {
                        SettingsLabel(title: "Enable Notifications", systemImage: "bell.badge.fill", tint: .red, titleColor: Color.accentColor)
                    }
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: "bell.fill").foregroundStyle(.green)
                        Text("Notifications enabled")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }

                Button {
                    sendTestNotification()
                } label: {
                    SettingsLabel(
                        title: testNotificationSent ? "Test Sent ✓ (background the app)" : "Send Test Notification",
                        systemImage: "bell.fill",
                        tint: .red,
                        titleColor: testNotificationSent ? .green : .primary
                    )
                }
                .disabled(notif.authorizationStatus == .denied)

                HStack {
                    SettingsLabel(title: "Default Snooze", systemImage: "clock.fill", tint: .gray)
                    Spacer()
                    Picker("", selection: $defaultSnoozeDuration) {
                        Text("10 min").tag(10)
                        Text("15 min").tag(15)
                        Text("30 min").tag(30)
                        Text("1 hour").tag(60)
                    }
                    .pickerStyle(.menu)
                }

                Button {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    SettingsLabel(title: "iOS Notification Settings", systemImage: "gear", tint: .gray)
                }
            } footer: {
                if notif.authorizationStatus == .authorized {
                    Text("Test notifications appear when the app is in the background.")
                        .font(.caption)
                }
            }

            // MARK: Privacy & grouping
            Section {
                Toggle(isOn: $privacyNotifications) {
                    SettingsLabel(title: "Privacy Focused Notifications", systemImage: "eye.slash.fill", tint: .indigo)
                }
            } footer: {
                Text("Opt to hide the names of medications from iPhone and Watch notifications to protect your medical information. Reminders will simply say to open DoseTrack.")
                    .font(.caption)
            }

            Section {
                Toggle(isOn: $stackNotifications) {
                    SettingsLabel(title: "Group Reminders", systemImage: "square.stack.3d.up.fill", tint: .teal)
                }
            } footer: {
                Text("Opt to receive one reminder for all medications due at the same time or routine. Open DoseTrack to review and take them individually.")
                    .font(.caption)
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        // Rescheduling rebuilds every pending reminder with the new privacy/grouping behaviour, so
        // the change takes effect without waiting for the next app-open refresh.
        .onChange(of: privacyNotifications) { _, _ in NotificationScheduler.shared.refreshAll(context: context) }
        .onChange(of: stackNotifications) { _, _ in NotificationScheduler.shared.refreshAll(context: context) }
    }

    private func sendTestNotification() {
        Task {
            await NotificationManager.shared.sendTestNotification()
            testNotificationSent = true
            try? await Task.sleep(for: .seconds(3))
            testNotificationSent = false
        }
    }
}

// MARK: - Apple Watch sub-screen

/// The Apple Watch connection status + manual sync, moved into the "Apple Watch Sync" row's
/// destination.
private struct WatchSyncView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var watchManager: WatchConnectivityManager
    @State private var watchSyncTriggered = false

    var body: some View {
        List {
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
                    SettingsLabel(
                        title: watchSyncTriggered ? "Sync Sent ✓" : "Sync to Watch",
                        systemImage: "arrow.triangle.2.circlepath",
                        tint: .blue,
                        titleColor: watchSyncTriggered ? .green : .primary
                    )
                }
            } footer: {
                Text("The watch normally updates on its own whenever a dose is logged or a medication changes. Use this if it looks out of date — e.g. right after pairing, or if the watch wasn't in range earlier.")
                    .font(.caption)
            }
        }
        .navigationTitle("Apple Watch")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Settings row label

/// A settings row label with the icon rendered in a uniform tinted squircle — the same
/// treatment Apple's own Settings uses. Replaces the previous mix of plain black glyphs, blue
/// outlines, filled circles, and a bare yellow star that made the list look patched-together.
private struct SettingsLabel: View {
    let title: String
    let systemImage: String
    let tint: Color
    var titleColor: Color = .primary

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(tint)
                .frame(width: 29, height: 29)
                .overlay {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
            Text(title)
                .foregroundStyle(titleColor)
        }
    }
}

/// Wraps a Plus-only settings row so free-tier users see it dimmed with a lock badge instead of
/// it being hidden entirely — showing what they're missing is the point (nudges toward upgrading)
/// rather than pretending the feature doesn't exist. Still fully tappable: `onLockedTap` should
/// present the paywall, since a fully "unusable" (non-interactive) row would bury the exact
/// upsell moment a user tapping out of curiosity is the best time to show.
struct GhostedProRow<Content: View>: View {
    let isPro: Bool
    let onLockedTap: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        if isPro {
            content()
        } else {
            Button(action: onLockedTap) {
                HStack {
                    content()
                        .opacity(0.4)
                    Spacer()
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
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
                Text("All medication data is stored locally on your device. No personal health information is sent to external servers without your explicit consent. Family sharing (a DoseTrack Plus feature) syncs data only with caregivers you explicitly invite.")
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
        .environmentObject(WatchConnectivityManager.shared)
}
