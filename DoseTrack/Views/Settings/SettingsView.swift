// DoseTrack/Views/Settings/SettingsView.swift
import SwiftUI
import CoreData

struct SettingsView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @EnvironmentObject private var auth: AuthManager
    @AppStorage("patientName") private var patientName: String = ""
    @AppStorage("defaultSnoozeDuration") private var defaultSnoozeDuration: Int = 30
    @AppStorage("criticalAlertsEnabled") private var criticalAlertsEnabled: Bool = true

    @State private var showingPaywall = false
    @State private var showingDeleteConfirm = false
    @State private var showingExportSheet = false
    @State private var exportItem: ExportActivityItem? = nil
    @State private var testNotificationSent = false

    @State private var showingSignUp = false

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
                            Text("Create a free account to keep your data if you reinstall the app or switch devices.")
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

                // MARK: Account / Pro
                Section("Subscription") {
                    if subscriptionManager.isProSubscriber {
                        HStack {
                            Label("DoseTrack Pro", systemImage: "star.fill")
                                .foregroundStyle(.yellow)
                            Spacer()
                            Text("Active")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        }
                    } else {
                        Button {
                            showingPaywall = true
                        } label: {
                            HStack {
                                Label("Upgrade to Pro", systemImage: "star.fill")
                                    .foregroundStyle(.yellow)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                        .foregroundStyle(.primary)

                        Text("5 medications free forever. Pro unlocks unlimited medications, iCloud sync, PDF reports, and family sharing.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // MARK: Profile
                Section("Profile") {
                    HStack {
                        Label("Your Name", systemImage: "person.fill")
                        Spacer()
                        TextField("Optional", text: $patientName)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Your name for doctor reports")
                    }
                }

                // MARK: Notifications
                Section("Notifications") {
                    Button {
                        sendTestNotification()
                    } label: {
                        HStack {
                            Label(
                                testNotificationSent ? "Test Sent ✓" : "Send Test Notification",
                                systemImage: "bell.fill"
                            )
                            .foregroundStyle(testNotificationSent ? .green : .primary)
                            Spacer()
                        }
                    }

                    Toggle(isOn: $criticalAlertsEnabled) {
                        Label("Critical Alerts", systemImage: "exclamationmark.triangle.fill")
                    }
                    .onChange(of: criticalAlertsEnabled) { _, _ in
                        // NotificationScheduler will pick this up on next refresh
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
                }

                // MARK: Data
                Section("Data & Privacy") {
                    Button {
                        exportCSV()
                    } label: {
                        Label("Export to CSV", systemImage: "square.and.arrow.up")
                            .foregroundStyle(.primary)
                    }

                    if subscriptionManager.isProSubscriber {
                        NavigationLink {
                            FamilySharingView()
                        } label: {
                            Label("Family Sharing", systemImage: "person.2.fill")
                        }

                        Toggle(isOn: .constant(false)) {
                            Label("iCloud Sync", systemImage: "icloud.fill")
                        }
                        .disabled(true)
                        // CloudKit sync toggle — full implementation after Apple Team ID set up
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

                    NavigationLink {
                        DisclaimerView()
                    } label: {
                        Label("Privacy & Disclaimer", systemImage: "hand.raised.fill")
                    }

                    Button {
                        if let url = URL(string: "https://apps.apple.com/") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Rate DoseTrack", systemImage: "star.bubble.fill")
                            .foregroundStyle(.primary)
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

                // Account
                Section("Account") {
                    HStack {
                        Label(auth.userEmail, systemImage: "person.circle.fill")
                            .lineLimit(1)
                        Spacer()
                    }
                    Button(role: .destructive) {
                        Task { await auth.signOut() }
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }

                // Disclaimer footer
                Section {
                    Text("DoseTrack is a reminder tool, not medical advice. Always follow your healthcare provider's instructions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $showingSignUp) {
                AuthView().environmentObject(auth)
            }
            .sheet(item: $exportItem) { item in
                ShareSheetView(activityItems: [item.data as Any])
            }
            .confirmationDialog(
                "Delete All Data?",
                isPresented: $showingDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete Everything", role: .destructive) {
                    deleteAllData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all medications, schedules, and dose history. This cannot be undone.")
            }
        }
    }

    // MARK: - Actions

    private func sendTestNotification() {
        Task {
            await NotificationManager.shared.sendTestNotification()
            testNotificationSent = true
            try? await Task.sleep(for: .seconds(3))
            testNotificationSent = false
        }
    }

    private func exportCSV() {
        let manager = ExportManager.shared
        let range = DateInterval(start: .distantPast, end: Date())
        let allLogs = manager.fetchAllLogs(context: context, in: range)
        let data = manager.generateCSV(from: allLogs, dateRange: range)
        exportItem = ExportActivityItem(data: data)
    }

    private func deleteAllData() {
        let entities = ["DoseLog", "Schedule", "Medication"]
        for entity in entities {
            let req: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: entity)
            let deleteReq = NSBatchDeleteRequest(fetchRequest: req)
            try? context.execute(deleteReq)
        }
        try? context.save()
    }
}

// MARK: - Supporting Types

private struct ExportActivityItem: Identifiable {
    let id = UUID()
    let data: Data
}

private struct ShareSheetView: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - Family Sharing Stub

struct FamilySharingView: View {
    var body: some View {
        List {
            Section {
                Text("Family sharing lets caregivers monitor medication adherence for family members.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Label("Coming Soon", systemImage: "clock.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Family Sharing")
    }
}

// MARK: - Disclaimer View

struct DisclaimerView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Medical Disclaimer")
                    .font(.title2.bold())

                Text("DoseTrack is a reminder tool only. It does not provide medical advice, diagnosis, or treatment. Always follow your healthcare provider's instructions regarding medications.")
                    .font(.body)

                Text("Data Privacy")
                    .font(.title2.bold())

                Text("All medication data is stored locally on your device. No personal health information is sent to external servers without your explicit consent. iCloud sync (Pro feature) uses your private iCloud account, not our servers.")
                    .font(.body)

                Text("If you have questions about your medications, consult your pharmacist or doctor.")
                    .font(.body)
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
}
