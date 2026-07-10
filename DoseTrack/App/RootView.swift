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
    @State private var revocationMessage: String?
    @ObservedObject private var caregiverManager = CaregiverManager.shared

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

    private func dismissSplash() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.4)) { showSplash = false }
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
                ActiveSessionView(activeAccount: activeAccount, ownContext: context)
                    .transition(.opacity)
            }

            // Splash overlay — cold launch ONLY (see note on the removed scenePhase re-show below).
            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: canProceed)

        .animation(.easeInOut(duration: 0.35), value: hasCompletedOnboarding)
        .animation(.easeInOut(duration: 0.5), value: showSplash)
        // Appearance override (light/dark/system) is applied at the UIKit level via
        // `window.overrideUserInterfaceStyle` in SceneDelegate, not here. A `.preferredColorScheme`
        // + `.id(appearanceOverride)` was tried first, but forcing SwiftUI to rebuild this
        // subtree on every change reset the ENTIRE view hierarchy — including whatever
        // navigation stack the user was in (e.g. Settings > Preferences), popping them back
        // to the root the instant they toggled the setting. UIKit's overrideUserInterfaceStyle
        // changes the color scheme without touching SwiftUI's view identity or navigation state.
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
        // NOTE: the splash intentionally does NOT re-show when the app returns to the
        // foreground. It previously did (scenePhase == .active → showSplash = true), which meant
        // a full ~2.6s animation replayed every time you switched apps and came back — genuinely
        // irritating for an app opened many times a day, and against Apple's guidance that launch
        // should feel instant. The splash now shows once, on cold launch only.
        .onChange(of: scenePhase) { _, newPhase in
            // Re-validate caregiver access whenever the app comes to the foreground. If we're
            // currently viewing a patient's account and that relationship has since been revoked
            // (no longer present in `overseenPatients`), fall back to the caregiver's own account
            // and surface a message — rather than silently continuing to show stale patient data.
            if newPhase == .active {
                Task {
                    await caregiverManager.refresh()
                    if let activeAccount, activeAccount.isViewingOtherAccount,
                       !caregiverManager.overseenPatients.contains(where: { $0.patientUserId == activeAccount.activeUserId }) {
                        activeAccount.switchToOwnAccount()
                        revocationMessage = "Your access to that account has ended."
                    }
                }
                // Push any dose logs written while the app was closed (e.g. via the widget's
                // Mark Taken intent) — those only ever land locally otherwise.
                let activeId = ActiveAccountResolver.shared.activeUserId
                let pushContext = activeId == nil ? context : PersistenceController.shared.context(forPatient: activeId!)
                Task {
                    await SupabaseSyncManager.shared.pushUnsyncedLocalChanges(context: pushContext, forUserId: activeId)
                }
                // Also refresh the watch's copy on every foreground — catches doses logged via
                // the widget while the phone app was closed (the watch was never told about
                // those either) and doubles as a retry if the watch wasn't reachable earlier.
                watchManager.syncTodayMedications(context: context)
            }
        }
        .sheet(item: $pendingInviteCode.mappedToIdentifiable()) { wrapped in
            AcceptCaregiverInviteView(code: wrapped.value)
                .environmentObject(CaregiverManager.shared)
        }
        .alert("Access Ended", isPresented: Binding(get: { revocationMessage != nil }, set: { if !$0 { revocationMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(revocationMessage ?? "")
        }
    }
}

// MARK: - Active session host

/// Mounts `MainTabView` and resolves which `NSManagedObjectContext` it reads/writes against.
///
/// This is a separate view (rather than inline in `RootView.body`) specifically so that
/// `activeAccount` can be held as `@ObservedObject` here. `RootView` only holds it as
/// `@State`, which does NOT re-run `RootView.body` when `ActiveAccountContext`'s `@Published
/// activeUserId` changes internally (only reassigning the `@State` var itself would). Views
/// further down that declare `@EnvironmentObject`/`@ObservedObject` for it (like this one, and
/// `MainTabView`'s capsule/switcher) DO get notified and re-render — which is exactly why the
/// switcher's label and checkmark used to update correctly while the actual CoreData context
/// silently stayed pinned to the caregiver's own store: nothing was recomputing it. `@ObservedObject`
/// here is what makes the context (and the Supabase pull below) actually follow the switch.
private struct ActiveSessionView: View {
    @ObservedObject var activeAccount: ActiveAccountContext
    let ownContext: NSManagedObjectContext
    @EnvironmentObject private var watchManager: WatchConnectivityManager

    /// The caregiver's own context when viewing themselves, or a distinct per-patient context
    /// (backed by its own SQLite file — see `PersistenceController.context(forPatient:)`) when
    /// viewing an overseen patient. Keeping these stores physically separate is what prevents
    /// caregiver and patient data from ever blending in one store.
    private var activeContext: NSManagedObjectContext {
        guard activeAccount.isViewingOtherAccount else { return ownContext }
        return PersistenceController.shared.context(forPatient: activeAccount.activeUserId)
    }

    var body: some View {
        MainTabView()
            .environmentObject(activeAccount)
            .environment(\.managedObjectContext, activeContext)
            .onAppear {
                ActiveAccountResolver.shared.set(
                    activeUserId: activeAccount.isViewingOtherAccount ? activeAccount.activeUserId : nil
                )
                // Without this, WatchConnectivityManager's `viewContext` stayed nil forever —
                // configure() was defined but never actually called anywhere — so any dose
                // confirmation logged ON the watch was silently dropped on arrival (the delegate
                // methods guard on `viewContext` being non-nil) and the reachability-triggered
                // re-sync below had no context to sync with either.
                watchManager.configure(context: ownContext)
                watchManager.syncTodayMedications(context: ownContext)
                // Pull all user data from Supabase on first app open after sign-in
                Task { await SupabaseSyncManager.shared.pullAll(context: ownContext) }
            }
            .onChange(of: activeAccount.activeUserId) { _, newUserId in
                let resolvedId: UUID? = (newUserId == activeAccount.ownUserId) ? nil : newUserId
                ActiveAccountResolver.shared.set(activeUserId: resolvedId)
                // Only pulls on an actual account switch (own <-> patient, or patient A -> B),
                // never on redraws, since `onChange` only triggers when the value differs.
                guard newUserId != activeAccount.ownUserId else { return }
                let patientContext = PersistenceController.shared.context(forPatient: newUserId)
                Task {
                    await SupabaseSyncManager.shared.pullAll(context: patientContext, forUserId: newUserId)
                }
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

    // Backdrop glow — gives the canvas depth instead of the mascot floating in a flat void.
    @State private var glowScale: CGFloat = 0.3
    @State private var glowOpacity: Double = 0

    // Hero — pops in with a real bounce (spring overshoot) plus a small settling rotation,
    // rather than a flat scale+fade. This is where the "lustre" was missing: a static
    // scale-up reads as an image appearing, not as a character arriving.
    @State private var heroScale: CGFloat = 0.4
    @State private var heroOpacity: Double = 0
    @State private var heroRotation: Double = -10

    // Small sparkle accents that pop briefly around the hero as it lands, then fade —
    // unlike the old debris (pills hanging static mid-air at rest), these are gone well
    // before the hold frame, so a paused screenshot never shows floating clutter.
    @State private var sparkleScale: CGFloat = 0.2
    @State private var sparkleOpacity: Double = 0

    // Wordmark — pops with a quick overshoot too, and a brand-blue underline draws in
    // beneath it for a more finished, "designed" feel.
    @State private var wordmarkScale: CGFloat = 0.7
    @State private var wordmarkOpacity: Double = 0
    @State private var underlineWidth: CGFloat = 0
    @State private var taglineOpacity: Double = 0

    private let sparkles: [(x: CGFloat, y: CGFloat, delay: Double, size: CGFloat)] = [
        (-96, -70, 0.0,  16), (100, -85, 0.06, 12),
        (-110, 30, 0.10, 11), (108, 40, 0.03, 15),
    ]

    var body: some View {
        ZStack {
            // Soft radial wash — pale brand-blue fading to white, not a flat void and not the
            // old incoherent navy gradient. Gives the canvas depth while staying light and
            // consistent with the app's own palette (Color(hex: "5B8AF0") is the accent used
            // throughout the rest of the product).
            RadialGradient(
                colors: [Color(hex: "EAF1FF"), Color.white],
                center: .center, startRadius: 20, endRadius: 420
            )
            .ignoresSafeArea()

            VStack(spacing: 22) {
                ZStack {
                    // Pulsing glow behind the mascot — an "energy source" the character lands
                    // into, rather than appearing in empty space.
                    Circle()
                        .fill(Color(hex: "5B8AF0").opacity(0.16))
                        .frame(width: 260, height: 260)
                        .scaleEffect(glowScale)
                        .opacity(glowOpacity)
                        .blur(radius: 18)

                    ForEach(Array(sparkles.enumerated()), id: \.offset) { _, s in
                        Image(systemName: "sparkle")
                            .font(.system(size: s.size, weight: .bold))
                            .foregroundStyle(Color(hex: "5B8AF0").opacity(0.7))
                            .offset(x: s.x, y: s.y)
                            .scaleEffect(sparkleScale)
                            .opacity(sparkleOpacity)
                    }

                    Image("SplashHero")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 260, height: 260)
                        .scaleEffect(heroScale)
                        .rotationEffect(.degrees(heroRotation))
                        .opacity(heroOpacity)
                }

                VStack(spacing: 8) {
                    Text("DoseTrack")
                        .font(.system(size: 42, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(hex: "3B5FCC"))
                        .scaleEffect(wordmarkScale)
                        .opacity(wordmarkOpacity)

                    Capsule()
                        .fill(Color(hex: "5B8AF0"))
                        .frame(width: underlineWidth, height: 3)

                    Text("Never miss a dose.")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(hex: "5B8AF0"))
                        .opacity(taglineOpacity)
                        .padding(.top, 2)
                }
            }
            .offset(y: -12)
        }
        .onAppear { runSequence() }
    }

    private func runSequence() {
        // Glow breathes in first, setting the stage (0–0.3s).
        withAnimation(.easeOut(duration: 0.3)) {
            glowScale = 1.0
            glowOpacity = 1
        }

        // Hero pops in with a genuine overshoot bounce + settling rotation (0.05–0.55s) —
        // the low damping fraction is deliberate, it's what makes this read as "arriving"
        // rather than "fading up."
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.58)) {
                heroScale = 1.0
                heroOpacity = 1
                heroRotation = 0
            }
        }

        // Sparkles pop and fade quickly around the landing (0.35–0.75s) — fully gone before
        // the splash holds, so there's never a static frame with floating clutter.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.easeOut(duration: 0.22)) {
                sparkleScale = 1.0
                sparkleOpacity = 1
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.62) {
            withAnimation(.easeIn(duration: 0.3)) {
                sparkleOpacity = 0
                sparkleScale = 1.3
            }
        }

        // Wordmark pops with its own small overshoot (0.5s), underline draws in right after,
        // tagline fades in last.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                wordmarkScale = 1.0
                wordmarkOpacity = 1
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.72) {
            withAnimation(.easeOut(duration: 0.3)) { underlineWidth = 64 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
            withAnimation(.easeOut(duration: 0.35)) { taglineOpacity = 1 }
        }
        // Exit is handled by the parent fading `showSplash` — see RootView.dismissSplash().
    }
}
