// DoseTrack/Views/Onboarding/OnboardingView.swift
import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @State private var page: Int = 0
    @State private var notificationAuthRequested = false
    @State private var showingAddMedication = false
    @Environment(\.managedObjectContext) private var context

    private let totalPages = 4

    var body: some View {
        VStack(spacing: 0) {
            // Page indicator
            HStack(spacing: 8) {
                ForEach(0..<totalPages) { i in
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
                ProfileSetupPage().tag(2)
                AddFirstMedPage(showingAdd: $showingAddMedication).tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: page)

            bottomControls
        }
        .background(Color(.systemBackground))
        .sheet(isPresented: $showingAddMedication) {
            AddEditMedicationView(
                viewModel: AddEditMedicationViewModel(context: context),
                onSave: { _ in
                    showingAddMedication = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        hasCompletedOnboarding = true
                    }
                }
            )
        }
    }

    private var bottomControls: some View {
        HStack(spacing: 16) {
            if page > 0 {
                Button("Back") { withAnimation { page -= 1 } }
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 60)
            } else {
                Spacer().frame(minWidth: 60)
            }

            Spacer()

            if page < totalPages - 1 {
                Button(page == 2 ? "Continue" : "Next") {
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

                Image("OnboardingWelcome")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .padding(.bottom, 4)

                VStack(spacing: 6) {
                    Text("Meet Milli! 💊")
                        .font(.title2.bold())
                        .foregroundStyle(.blue)
                    Text("DoseTrack")
                        .font(.largeTitle.bold())
                    Text("Never miss a dose.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Your friendly pill bottle pal, here to keep you on track.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
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
                    FeatureRow(icon: "person.2.fill", color: .purple,
                               title: "Caregiver sharing",
                               subtitle: "Pro subscribers can invite a caregiver to help manage medications")
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

                Image("OnboardingNotification")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180, height: 180)
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

// MARK: - Page 3: Profile Setup

private struct ProfileSetupPage: View {
    @AppStorage("patientName")   private var patientName: String = ""
    @AppStorage("patientGender") private var patientGender: String = ""
    @EnvironmentObject private var auth: AuthManager

    private let genders = ["Female", "Male", "Non-binary", "Other", "Prefer not to say"]

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer().frame(height: 24)

                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 100, height: 100)
                    Image(systemName: "person.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(spacing: 8) {
                    Text("Tell Us About You")
                        .font(.largeTitle.bold())
                    Text("This helps us personalise your experience. You can update it anytime in Settings.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }

                VStack(spacing: 14) {
                    // Name
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your name")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                        TextField("First name or nickname", text: $patientName)
                            .textContentType(.givenName)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 14)
                            .padding(.vertical, 13)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    // Gender
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Gender (optional)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(genders, id: \.self) { g in
                                Button {
                                    patientGender = patientGender == g ? "" : g
                                } label: {
                                    Text(g)
                                        .font(.subheadline)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(
                                            patientGender == g
                                                ? Color.accentColor
                                                : Color(.secondarySystemBackground),
                                            in: RoundedRectangle(cornerRadius: 10)
                                        )
                                        .foregroundStyle(patientGender == g ? .white : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 28)

                Text("You can skip this step — tap Continue below.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)

                Spacer().frame(height: 8)
            }
        }
        .onAppear {
            // Pre-fill name from auth if available
            if patientName.isEmpty {
                patientName = auth.displayName == "Guest" ? "" : auth.displayName
            }
        }
    }
}

// MARK: - Page 4: Add First Med

private struct AddFirstMedPage: View {
    @Binding var showingAdd: Bool
    @AppStorage("patientGender") private var patientGender: String = ""
    @AppStorage("contraceptiveMethod") private var contraceptiveMethod: String = ""

    private var showContraceptivePrompt: Bool {
        ["Female", "Other", "Prefer not to say"].contains(patientGender)
        && contraceptiveMethod.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer().frame(height: 24)

                Image("OnboardingWelcome")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 160, height: 160)

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

                if showContraceptivePrompt {
                    NavigationLink(destination: ContraceptiveTrackerView()) {
                        HStack(spacing: 10) {
                            Image(systemName: "calendar.badge.clock")
                                .foregroundStyle(.purple)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Add a birth control reminder")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                Text("Track implants, IUDs, pills & more")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .background(.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal, 28)
                }

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
