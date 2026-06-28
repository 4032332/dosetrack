// DoseTrack/Views/Onboarding/OnboardingView.swift
import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @State private var page: Int = 0
    @State private var notificationAuthRequested = false
    @State private var showingAddMedication = false
    @Environment(\.managedObjectContext) private var context

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                WelcomePage().tag(0)
                NotificationsPage(authRequested: $notificationAuthRequested).tag(1)
                AddFirstMedPage(showingAdd: $showingAddMedication).tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .animation(.easeInOut, value: page)

            bottomControls
        }
        .background(Color(.systemBackground))
        .sheet(isPresented: $showingAddMedication) {
            AddEditMedicationView(
                viewModel: AddEditMedicationViewModel(context: context),
                onSave: { _ in showingAddMedication = false }
            )
        }
    }

    private var bottomControls: some View {
        HStack {
            if page > 0 {
                Button("Back") { page -= 1 }
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if page < 2 {
                Button("Next") {
                    if page == 1 && !notificationAuthRequested {
                        requestNotifications()
                    } else {
                        page += 1
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Get Started") {
                    hasCompletedOnboarding = true
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 40)
        .padding(.top, 12)
    }

    private func requestNotifications() {
        Task {
            await NotificationManager.shared.requestAuthorization()
            notificationAuthRequested = true
            page += 1
        }
    }
}

// MARK: - Page 1: Welcome

private struct WelcomePage: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "pills.fill")
                .font(.system(size: 72))
                .foregroundStyle(.blue.gradient)

            VStack(spacing: 8) {
                Text("DoseTrack")
                    .font(.largeTitle.bold())
                Text("Never miss a dose.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(icon: "bell.fill", color: .blue,
                           title: "Reliable reminders",
                           subtitle: "Notifications that actually fire, every time")
                FeatureRow(icon: "lock.fill", color: .green,
                           title: "Your data, on your device",
                           subtitle: "No account required. Local-first, always")
                FeatureRow(icon: "heart.fill", color: .red,
                           title: "5 medications free forever",
                           subtitle: "No surprise paywalls on core features")
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }
}

// MARK: - Page 2: Notifications

private struct NotificationsPage: View {
    @Binding var authRequested: Bool

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "bell.badge.fill")
                .font(.system(size: 72))
                .foregroundStyle(.orange.gradient)

            VStack(spacing: 8) {
                Text("Stay on Track")
                    .font(.largeTitle.bold())
                Text("DoseTrack needs permission to send you medication reminders.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(icon: "clock.fill", color: .orange,
                           title: "On-time alerts",
                           subtitle: "Reminders arrive exactly when your dose is due")
                FeatureRow(icon: "applewatch", color: .gray,
                           title: "Apple Watch support",
                           subtitle: "Mark doses taken from your wrist")
                FeatureRow(icon: "moon.zzz.fill", color: .purple,
                           title: "Critical alerts",
                           subtitle: "Alerts that break through Do Not Disturb (optional)")
            }
            .padding(.horizontal, 24)

            if authRequested {
                Label("Notifications enabled", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline.weight(.medium))
            }

            Spacer()
        }
    }
}

// MARK: - Page 3: Add First Med

private struct AddFirstMedPage: View {
    @Binding var showingAdd: Bool

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "plus.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green.gradient)

            VStack(spacing: 8) {
                Text("Add Your First Medication")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("Add a medication now, or skip and do it later from the Medications tab.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Button {
                showingAdd = true
            } label: {
                Label("Add Medication", systemImage: "plus")
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 40)

            Spacer()
        }
    }
}

// MARK: - Shared Feature Row

private struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    OnboardingView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
