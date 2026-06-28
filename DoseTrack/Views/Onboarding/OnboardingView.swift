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
            // Page indicator
            HStack(spacing: 8) {
                ForEach(0..<3) { i in
                    Capsule()
                        .fill(i == page ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: i == page ? 20 : 8, height: 8)
                        .animation(.spring(response: 0.3), value: page)
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 4)

            TabView(selection: $page) {
                WelcomePage().tag(0)
                NotificationsPage(authRequested: $notificationAuthRequested).tag(1)
                AddFirstMedPage(showingAdd: $showingAddMedication).tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
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
        HStack(spacing: 16) {
            if page > 0 {
                Button("Back") { page -= 1 }
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 60)
            } else {
                Spacer().frame(minWidth: 60)
            }

            Spacer()

            if page < 2 {
                Button("Next") {
                    if page == 1 && !notificationAuthRequested {
                        requestNotifications()
                    } else {
                        withAnimation { page += 1 }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Button("Get Started") {
                    hasCompletedOnboarding = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, max(32, (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.bottom ?? 0)))
        .padding(.top, 12)
        .background(.bar)
    }

    private func requestNotifications() {
        Task {
            await NotificationManager.shared.requestAuthorization()
            notificationAuthRequested = true
            withAnimation { page += 1 }
        }
    }
}

// MARK: - Page 1: Welcome

private struct WelcomePage: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer().frame(height: 24)

                Image(systemName: "pills.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue.gradient)
                    .padding(.bottom, 4)

                VStack(spacing: 8) {
                    Text("DoseTrack")
                        .font(.largeTitle.bold())
                    Text("Never miss a dose.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 20) {
                    FeatureRow(icon: "bell.fill", color: .blue,
                               title: "Reliable reminders",
                               subtitle: "Notifications that actually fire, every time — even on Apple Watch")
                    FeatureRow(icon: "lock.fill", color: .green,
                               title: "Your data, on your device",
                               subtitle: "No account required for core features. Local-first, always")
                    FeatureRow(icon: "heart.fill", color: .red,
                               title: "5 medications free forever",
                               subtitle: "No surprise paywalls on core reminder functionality")
                    FeatureRow(icon: "arrow.trianglehead.2.clockwise", color: .purple,
                               title: "Sync across devices",
                               subtitle: "Pro subscribers get iCloud sync across iPhone, iPad, and Watch")
                }
                .padding(.horizontal, 28)

                Spacer().frame(height: 8)
            }
        }
    }
}

// MARK: - Page 2: Notifications

private struct NotificationsPage: View {
    @Binding var authRequested: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer().frame(height: 24)

                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.orange.gradient)
                    .padding(.bottom, 4)

                VStack(spacing: 8) {
                    Text("Stay on Track")
                        .font(.largeTitle.bold())
                    Text("DoseTrack needs permission to send medication reminders.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }

                VStack(alignment: .leading, spacing: 20) {
                    FeatureRow(icon: "clock.fill", color: .orange,
                               title: "On-time alerts",
                               subtitle: "Reminders arrive exactly when your dose is due")
                    FeatureRow(icon: "applewatch", color: .gray,
                               title: "Apple Watch",
                               subtitle: "Mark doses taken from your wrist with action buttons")
                    FeatureRow(icon: "moon.zzz.fill", color: .purple,
                               title: "Critical alerts (optional)",
                               subtitle: "Medication alerts can break through Do Not Disturb")
                }
                .padding(.horizontal, 28)

                if authRequested {
                    Label("Notifications enabled", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline.weight(.medium))
                        .padding(.top, 4)
                }

                Spacer().frame(height: 8)
            }
        }
    }
}

// MARK: - Page 3: Add First Med

private struct AddFirstMedPage: View {
    @Binding var showingAdd: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer().frame(height: 24)

                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.green.gradient)
                    .padding(.bottom, 4)

                VStack(spacing: 8) {
                    Text("Add Your First\nMedication")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                    Text("Get started now, or skip and add medications from the Medications tab later.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }

                Button {
                    showingAdd = true
                } label: {
                    Label("Add Medication", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 40)

                Text("You can always add more from the Medications tab.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                Spacer().frame(height: 8)
            }
        }
    }
}

// MARK: - Shared Feature Row

struct FeatureRow: View {
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
            VStack(alignment: .leading, spacing: 3) {
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
