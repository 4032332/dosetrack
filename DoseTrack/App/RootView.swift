// DoseTrack/App/RootView.swift
import SwiftUI
import CoreData

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

    /// Key used to persist a stable local identifier for guest-mode users whose
    /// Supabase session is nil (anonymous auth disabled/failed fallback — see
    /// `AuthManager.continueAsGuest()`). Generated once and reused across launches
    /// so `ActiveAccountContext.ownUserId` stays consistent for a given guest.
    private static let localGuestIdKey = "localGuestAccountId"

    /// Returns a stable local-only UUID for a session-less guest, generating and
    /// persisting one on first use.
    private func localGuestId() -> UUID {
        if let stored = UserDefaults.standard.string(forKey: Self.localGuestIdKey),
           let uuid = UUID(uuidString: stored) {
            return uuid
        }
        let newId = UUID()
        UserDefaults.standard.set(newId.uuidString, forKey: Self.localGuestIdKey)
        return newId
    }

    /// Builds (or rebuilds) the active-account context from the current session.
    ///
    /// Two cases produce a real, signed-in `ActiveAccountContext`:
    ///  - a full account session (`auth.session != nil`)
    ///  - guest mode where anonymous Supabase sign-in succeeded (session set, `isGuest == true`)
    ///
    /// A third case — `AuthManager.continueAsGuest()`'s fallback path, where anonymous auth is
    /// disabled/fails and only `UserDefaults["guestMode"]` is set with `session` staying nil —
    /// has no Supabase user id at all. Without a fallback here, `activeAccount` would stay
    /// permanently nil and the user would be stuck past onboarding with no way to reach
    /// `MainTabView` (regression from commit 2123217). We synthesize a stable local-only id
    /// for that case; the guest has no caregiver relationships, so the account-switcher UI
    /// (gated on `overseenPatients` being non-empty) never appears for them regardless.
    private func refreshActiveAccount() {
        guard let userId = auth.session?.user.id else {
            if guestMode {
                let guestId = localGuestId()
                if activeAccount?.ownUserId != guestId {
                    activeAccount = ActiveAccountContext(ownUserId: guestId, ownDisplayName: "You")
                }
            } else {
                activeAccount = nil
            }
            return
        }
        if activeAccount?.ownUserId != userId {
            activeAccount = ActiveAccountContext(ownUserId: userId, ownDisplayName: auth.displayName)
        }
    }

    /// Resolves which `NSManagedObjectContext` the main app UI should read/write against for
    /// the currently active account: the caregiver's own context (injected by SceneDelegate,
    /// captured in `context` above) when viewing themselves, or a distinct per-patient context
    /// (backed by its own SQLite file — see `PersistenceController.context(forPatient:)`) when
    /// a caregiver has switched to viewing an overseen patient. Keeping these stores physically
    /// separate is what prevents caregiver and patient data from ever blending in one store.
    private func activeContext(for account: ActiveAccountContext) -> NSManagedObjectContext {
        guard account.isViewingOtherAccount else { return context }
        return PersistenceController.shared.context(forPatient: account.activeUserId)
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
                    .environment(\.managedObjectContext, activeContext(for: activeAccount))
                    .transition(.opacity)
                    .onAppear {
                        watchManager.syncTodayMedications(context: context)
                        // Pull all user data from Supabase on first app open after sign-in
                        Task { await SupabaseSyncManager.shared.pullAll(context: context) }
                    }
                    .onChange(of: activeAccount.activeUserId) { _, newUserId in
                        // Only fires on an actual account switch (own <-> patient, or patient A -> B),
                        // never on redraws, since `onChange` only triggers when the value differs.
                        guard newUserId != activeAccount.ownUserId else { return }
                        let patientContext = PersistenceController.shared.context(forPatient: newUserId)
                        Task {
                            await SupabaseSyncManager.shared.pullAll(context: patientContext, forUserId: newUserId)
                        }
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
        .onReceive(NotificationCenter.default.publisher(for: .guestModeActivated)) { _ in
            // Guest fallback path (anonymous Supabase auth disabled/failed): session stays nil,
            // so `onChange(of: auth.session?.user.id)` never fires. Refresh explicitly here so
            // `activeAccount` gets a synthetic local id and the user can reach MainTabView.
            refreshActiveAccount()
        }
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
