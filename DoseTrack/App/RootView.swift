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
    @ObservedObject private var disclaimer = DisclaimerManager.shared

    private var canProceed: Bool { auth.isSignedIn || guestMode }

    // MARK: - Disclaimer identity

    /// Who the one-time medical disclaimer is being decided for. A real account uses its Supabase
    /// user id; guests (anonymous or the session-less fallback) have no server profile and share
    /// the local "guest" bucket.
    private var disclaimerUserId: UUID? {
        auth.session?.user.id ?? (guestMode ? localGuestId() : nil)
    }
    private var disclaimerIsGuest: Bool { auth.isGuest || guestMode }

    /// Changes whenever the signed-in identity does, so the `.task` below re-evaluates acceptance
    /// on login/logout/account switch.
    private var disclaimerIdentityKey: String {
        "\(canProceed)-\(disclaimerUserId?.uuidString ?? "none")-\(disclaimerIsGuest)"
    }

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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeInOut(duration: 0.4)) { showSplash = false }
        }
    }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            if !canProceed {
                AuthView()
                    .transition(.opacity)
            } else if disclaimer.status == .required {
                // Gate a newly-created account on accepting the medical disclaimer / terms before
                // reaching onboarding or the app. Declining signs out.
                DisclaimerConsentView(
                    onAccept: {
                        Task { await disclaimer.accept(userId: disclaimerUserId, isGuest: disclaimerIsGuest) }
                    },
                    onDecline: {
                        Task { await auth.signOut() }
                    }
                )
                .transition(.opacity)
            } else if disclaimer.status == .unknown {
                // Still resolving whether acceptance is needed — don't flash onboarding/app. On a
                // cold launch the splash overlay covers this; the check is a fast local lookup
                // (or a quick server read) so it resolves almost immediately.
                Color(.systemBackground).ignoresSafeArea()
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
        .animation(.easeInOut(duration: 0.35), value: disclaimer.status)
        // Re-evaluate whether the one-time medical disclaimer must be shown whenever the signed-in
        // identity changes (login, logout, guest, account switch).
        .task(id: disclaimerIdentityKey) {
            if canProceed {
                await disclaimer.evaluate(userId: disclaimerUserId, isGuest: disclaimerIsGuest)
            } else {
                disclaimer.reset()
            }
        }
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

    // Confetti burst — a single 0→1 progress value drives every piece (position, gravity,
    // spin, fade are all derived from it), so the whole party-popper effect is one cheap
    // animated value rather than dozens of independent timers. This is the "oomph" the
    // previous fade-up sparkles lacked.
    @State private var burst: CGFloat = 0

    // Wordmark — pops with a quick overshoot too, and a brand-blue underline draws in
    // beneath it for a more finished, "designed" feel.
    @State private var wordmarkScale: CGFloat = 0.7
    @State private var wordmarkOpacity: Double = 0
    @State private var underlineWidth: CGFloat = 0
    @State private var taglineOpacity: Double = 0

    private let confetti = ConfettiPiece.burst(count: 40)

    var body: some View {
        ZStack {
            // Soft radial wash — pale brand-blue fading to white. Kept light so the colourful
            // (now transparent-cut-out) mascot and confetti pop against it. Consistent with the
            // app's own accent, Color(hex: "5B8AF0").
            RadialGradient(
                colors: [Color(hex: "E4EDFF"), Color.white],
                center: .center, startRadius: 10, endRadius: 460
            )
            .ignoresSafeArea()

            VStack(spacing: 22) {
                ZStack {
                    // Pulsing glow behind the mascot — an "energy source" the character lands
                    // into, rather than appearing in empty space.
                    Circle()
                        .fill(Color(hex: "5B8AF0").opacity(0.18))
                        .frame(width: 260, height: 260)
                        .scaleEffect(glowScale)
                        .opacity(glowOpacity)
                        .blur(radius: 20)

                    // Confetti erupts from behind the mascot and rains outward past its edges.
                    // Driven by an Animatable modifier (see ConfettiEffect) so SwiftUI interpolates
                    // `burst` frame-by-frame — feeding it straight into .offset/.opacity instead
                    // makes SwiftUI animate only the end values, which for opacity is 0→0 (the
                    // burst is invisible at both ends), so the whole flight would be skipped.
                    ForEach(confetti) { piece in
                        piece.shape
                            .fill(piece.color)
                            .frame(width: piece.size.width, height: piece.size.height)
                            .modifier(ConfettiEffect(progress: burst, piece: piece))
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
            withAnimation(.spring(response: 0.42, dampingFraction: 0.52)) {
                heroScale = 1.0
                heroOpacity = 1
                heroRotation = 0
            }
        }

        // Confetti fires right as the hero lands (0.22s) and plays out over ~1.1s: pieces
        // shoot outward, arc down under gravity, spin, and fade — an easeOut so they burst
        // fast then settle. Timed to be mostly gone by the 1.5s hold, leaving a clean frame.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            withAnimation(.easeOut(duration: 1.3)) { burst = 1 }
        }

        // Wordmark pops with its own small overshoot (0.5s), underline draws in right after,
        // tagline fades in last.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.62)) {
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

// MARK: - Confetti

/// One confetti piece. Every animated property is a pure function of a single 0→1 `progress`
/// value so the whole burst is driven by one `withAnimation` on `SplashView.burst`, keeping it
/// cheap and perfectly in sync. Launch direction, travel distance, spin and colour are fixed at
/// creation (seeded, so the spread is deterministic and art-directed rather than random noise).
private struct ConfettiPiece: Identifiable {
    let id: Int
    let angle: Double        // launch direction, radians
    let distance: CGFloat    // outward travel radius at full progress
    let color: Color
    let size: CGSize
    let rotation: Double     // spin magnitude
    let isCapsule: Bool
    let launchScale: CGFloat // per-piece easing skew so pieces don't move in lockstep

    var shape: AnyShapeView {
        isCapsule ? AnyShapeView(Capsule()) : AnyShapeView(RoundedRectangle(cornerRadius: 2))
    }

    /// Position: outward travel (eased) plus a gravity arc that pulls pieces downward over time.
    func offset(at progress: CGFloat) -> CGSize {
        let p = min(1, progress * launchScale)
        let eased = 1 - pow(1 - p, 2)               // easeOut on outward travel
        // Pieces start ~120pt out (at the mascot's edge) so they're never hidden behind the
        // character, then travel the rest of the way toward the screen edges.
        let travel = 120 + distance * eased
        let gravity = 130 * progress * progress     // accelerating downward drift
        return CGSize(width: cos(angle) * travel,
                      height: sin(angle) * travel + gravity)
    }

    /// Fade: snap in over the first 12%, hold, then fade out across the final 45%.
    func opacity(at progress: CGFloat) -> Double {
        let p = Double(progress)
        if p < 0.10 { return p / 0.10 }
        if p > 0.62 { return max(0, 1 - (p - 0.62) / 0.38) }
        return 1
    }

    /// Deterministic, art-directed spread — brand + pill palette, biased to launch upward and
    /// outward from behind the mascot like a popper.
    static func burst(count: Int) -> [ConfettiPiece] {
        let palette: [Color] = [
            Color(hex: "5B8AF0"), Color(hex: "F27A9B"), Color(hex: "FFB443"),
            Color(hex: "5FCB7E"), Color(hex: "FFD23F"), Color(hex: "A78BFA"),
            Color(hex: "56C2E6"),
        ]
        var rng = SeededGenerator(seed: 20260710)
        return (0..<count).map { i in
            // Bias angles toward the upper hemisphere (−π…0 is upward in screen space) so the
            // burst reads as erupting up-and-out rather than sinking.
            let spread = Double.random(in: -Double.pi ... 0.35 * Double.pi, using: &rng)
            return ConfettiPiece(
                id: i,
                angle: spread,
                distance: CGFloat.random(in: 80...240, using: &rng),
                color: palette[Int.random(in: 0..<palette.count, using: &rng)],
                size: {
                    let cap = Bool.random(using: &rng)
                    return cap ? CGSize(width: 8, height: 18) : CGSize(width: 11, height: 11)
                }(),
                rotation: Double.random(in: 90...360, using: &rng) * (Bool.random(using: &rng) ? 1 : -1),
                isCapsule: Bool.random(using: &rng),
                launchScale: CGFloat.random(in: 0.85...1.15, using: &rng)
            )
        }
    }
}

/// Animates one confetti piece. `animatableData` IS the burst progress, so SwiftUI interpolates
/// it frame-by-frame and re-invokes `body` at each step — the only way to get the full outward
/// flight when the piece is invisible (opacity 0) at both progress 0 and 1. Reading `burst`
/// directly in `.offset`/`.opacity` back in the view body would let SwiftUI animate just the end
/// values (0→0 opacity) and skip the visible middle entirely.
private struct ConfettiEffect: ViewModifier, Animatable {
    var progress: CGFloat
    let piece: ConfettiPiece

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(piece.rotation * Double(progress) * 3))
            .offset(piece.offset(at: progress))
            .opacity(piece.opacity(at: progress))
    }
}

/// Type-erased Shape wrapper so a piece can hold either a Capsule or a RoundedRectangle.
private struct AnyShapeView: Shape {
    private let pathBuilder: (CGRect) -> Path
    init<S: Shape>(_ shape: S) { pathBuilder = { shape.path(in: $0) } }
    func path(in rect: CGRect) -> Path { pathBuilder(rect) }
}

/// Tiny seedable RNG (SplitMix64) so the confetti spread is identical every launch — an
/// art-directed layout, not random noise that occasionally clumps badly.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
