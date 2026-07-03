// DoseTrack/App/RootView.swift
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var watchManager: WatchConnectivityManager
    @Environment(\.managedObjectContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @AppStorage("guestMode") private var guestMode: Bool = false

    @State private var showSplash: Bool = true
    @State private var pendingInviteCode: String?
    @State private var activeAccount: ActiveAccountContext?

    private var canProceed: Bool { auth.isSignedIn || guestMode }

    /// Builds (or rebuilds) the active-account context from the current session.
    /// Runs after sign-in completes since `ActiveAccountContext` requires a non-optional
    /// user id — guest sessions and signed-out states simply leave this nil, and the
    /// account-switcher UI (which requires `ActiveAccountContext`) is only ever shown
    /// once `overseenPatients` is non-empty, which itself requires a signed-in caregiver.
    private func refreshActiveAccount() {
        guard let userId = auth.session?.user.id else {
            activeAccount = nil
            return
        }
        if activeAccount?.ownUserId != userId {
            activeAccount = ActiveAccountContext(ownUserId: userId, ownDisplayName: auth.displayName)
        }
    }

    private func dismissSplash() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            showSplash = false
        }
    }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            if !canProceed {
                AuthView()
                    .transition(.opacity)
            } else if !hasCompletedOnboarding {
                OnboardingView()
                    .transition(.opacity)
            } else if let activeAccount {
                MainTabView()
                    .environmentObject(activeAccount)
                    .transition(.opacity)
                    .onAppear {
                        watchManager.syncTodayMedications(context: context)
                        // Pull all user data from Supabase on first app open after sign-in
                        Task { await SupabaseSyncManager.shared.pullAll(context: context) }
                    }
            }

            // Splash overlay — shown briefly on every launch
            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: canProceed)

        .animation(.easeInOut(duration: 0.35), value: hasCompletedOnboarding)
        .animation(.easeInOut(duration: 0.5), value: showSplash)
        .onReceive(NotificationCenter.default.publisher(for: .guestModeActivated)) { _ in }
        .onReceive(NotificationCenter.default.publisher(for: .caregiverInviteReceived)) { notification in
            guard let code = notification.object as? String else { return }
            pendingInviteCode = code
        }
        .onAppear {
            dismissSplash()
            refreshActiveAccount()
        }
        .onChange(of: auth.session?.user.id) { _, _ in
            refreshActiveAccount()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && !showSplash {
                showSplash = true
                dismissSplash()
            }
        }
        .sheet(item: $pendingInviteCode.mappedToIdentifiable()) { wrapped in
            AcceptCaregiverInviteView(code: wrapped.value)
                .environmentObject(CaregiverManager.shared)
        }
    }
}

// MARK: - Optional String -> Identifiable helper for .sheet(item:)

private struct IdentifiableString: Identifiable {
    let value: String
    var id: String { value }
}

private extension Binding where Value == String? {
    /// Wraps an optional `String` binding as a `Binding<IdentifiableString?>` so it can be used
    /// with `.sheet(item:)`, which requires an `Identifiable` payload.
    func mappedToIdentifiable() -> Binding<IdentifiableString?> {
        Binding<IdentifiableString?>(
            get: { self.wrappedValue.map(IdentifiableString.init) },
            set: { self.wrappedValue = $0?.value }
        )
    }
}

// MARK: - Splash Screen

private struct SplashView: View {

    // Phase 1 – Milli drops in
    @State private var milliY: CGFloat = -500
    @State private var milliRotation: Double = 0
    @State private var milliScale: CGFloat = 1.0

    // Phase 2 – Rattle (pill-bottle shake)
    @State private var shakeX: CGFloat = 0

    // Phase 3 – Pill burst particles
    @State private var burstProgress: CGFloat = 0
    @State private var burstOpacity: Double = 0

    // Phase 4 – Title + tagline
    @State private var titleScale: CGFloat = 0.6
    @State private var titleOpacity: Double = 0
    @State private var taglineOpacity: Double = 0

    // Exit
    @State private var exitScale: CGFloat = 1.0
    @State private var exitOpacity: Double = 1.0

    private let pillAngles: [Double] = [0, 40, 80, 120, 160, 200, 240, 300, 340]

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [Color(hex: "1A1A2E"), Color(hex: "16213E"), Color(hex: "0F3460")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Pill burst particles
            ZStack {
                ForEach(Array(pillAngles.enumerated()), id: \.offset) { i, angle in
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [pillColor(i).opacity(0.9), pillColor(i).opacity(0.5)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: 22, height: 10)
                        .rotationEffect(.degrees(angle))
                        .offset(
                            x: cos(angle * .pi / 180) * 90 * burstProgress,
                            y: sin(angle * .pi / 180) * 90 * burstProgress
                        )
                        .opacity(burstOpacity * (1 - burstProgress * 0.6))
                        .scaleEffect(0.5 + burstProgress * 0.5)
                }
            }

            VStack(spacing: 18) {
                // Milli
                ZStack {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(.white)
                        .frame(width: 130, height: 130)
                        .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
                    Image("OnboardingWelcome")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 110, height: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .rotationEffect(.degrees(milliRotation))
                .scaleEffect(milliScale)
                .offset(x: shakeX, y: milliY)

                // Title
                VStack(spacing: 6) {
                    Text("DoseTrack")
                        .font(.system(size: 38, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Never miss a dose.")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                        .opacity(taglineOpacity)
                }
                .scaleEffect(titleScale)
                .opacity(titleOpacity)
            }
        }
        .scaleEffect(exitScale)
        .opacity(exitOpacity)
        .onAppear { runSequence() }
    }

    private func pillColor(_ i: Int) -> Color {
        let colors: [Color] = [
            Color(hex: "FF6B6B"), Color(hex: "FFD93D"), Color(hex: "6BCB77"),
            Color(hex: "4D96FF"), Color(hex: "C77DFF"), Color(hex: "FF9F1C"),
            Color(hex: "2EC4B6"), Color(hex: "FF6B6B"), Color(hex: "FFD93D")
        ]
        return colors[i % colors.count]
    }

    private func runSequence() {
        // Phase 1: Milli spins in from top with bounce (0.0–0.6s)
        withAnimation(.spring(response: 0.55, dampingFraction: 0.58)) {
            milliY = 0
            milliRotation = 360
        }

        // Phase 2: Rattle — rapid left-right shake (0.65–1.0s)
        let shakeTimes: [(Double, CGFloat)] = [
            (0.60, -18), (0.68, 18), (0.74, -14), (0.80, 14),
            (0.86, -8),  (0.92, 8),  (0.98, 0)
        ]
        for (delay, x) in shakeTimes {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.interactiveSpring(response: 0.07, dampingFraction: 0.3)) {
                    shakeX = x
                }
            }
        }

        // Also squash/stretch during rattle for extra juice
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.62) {
            withAnimation(.easeInOut(duration: 0.18)) { milliScale = 1.12 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.80) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) { milliScale = 1.0 }
        }

        // Phase 3: Pill burst (1.0–1.4s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.00) {
            burstOpacity = 1
            withAnimation(.easeOut(duration: 0.45)) {
                burstProgress = 1
            }
        }

        // Phase 4: Title snaps up (1.05s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                titleScale = 1.0
                titleOpacity = 1
            }
        }

        // Tagline fades in (1.25s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
            withAnimation(.easeIn(duration: 0.35)) {
                taglineOpacity = 1
            }
        }

        // Exit: zoom out and fade (2.2s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation(.easeIn(duration: 0.35)) {
                exitScale = 1.08
                exitOpacity = 0
            }
        }
    }
}
