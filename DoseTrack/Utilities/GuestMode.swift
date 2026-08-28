// DoseTrack/Utilities/GuestMode.swift
import Foundation

/// Ownership of the `guestMode` flag and the rule for turning auth state into an active account.
///
/// Both exist because of one bug. `AuthManager.continueAsGuest()`'s fallback path writes the
/// flag and posts `.guestModeActivated` in the same tick, and `RootView` handles that
/// notification synchronously. The handler used to read SwiftUI's `@AppStorage` mirror of the
/// flag, which had not yet observed the write — so it read `false`, decided the user was signed
/// out, and cleared `activeAccount`. Nothing recovered (`session` goes nil -> nil so `.onChange`
/// never fires, and `.onAppear` had already run), leaving `RootView` with no branch to render:
/// a permanent blank screen.
///
/// The fix is structural rather than a re-ordering or a dispatch hop: read the authoritative
/// store, and keep the decision pure so it can be tested. See `ActiveAccountDecisionTests`.

enum GuestMode {

    /// Single home for the key, which was previously repeated as a string literal in
    /// `AuthManager` (twice), `RootView` and `ScreenshotSeeder`.
    static let defaultsKey = "guestMode"

    /// Authoritative read. Anything reacting to `.guestModeActivated` MUST use this rather than
    /// an `@AppStorage` property — the notification is posted in the same tick as the write, and
    /// only UserDefaults is guaranteed to reflect it by then.
    static func isActive(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: defaultsKey)
    }

    static func activate(in defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: defaultsKey)
    }

    static func deactivate(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }
}

/// Which account the app should be showing, derived purely from auth state.
///
/// Extracted from `RootView.refreshActiveAccount()` so the rule is testable on its own. The view
/// keeps the state assignment; this owns the decision.
enum ActiveAccountDecision: Equatable {

    /// A real Supabase account, or a guest whose anonymous sign-in succeeded.
    case signedIn(userId: UUID)

    /// The session-less guest fallback: no Supabase user exists, so a stable local id stands in.
    case guest(userId: UUID)

    /// No session and no guest flag — show the auth screen.
    case signedOut

    /// - Parameter localGuestId: called only on the guest branch. It generates and persists an id
    ///   on first use, so the other branches must not invoke it as a side effect.
    static func resolve(
        sessionUserId: UUID?,
        isGuestModeActive: Bool,
        localGuestId: () -> UUID
    ) -> ActiveAccountDecision {
        // A real session always wins, even if a stale guest flag survived from an earlier
        // session — otherwise a signed-in user could be silently downgraded to a guest.
        if let sessionUserId { return .signedIn(userId: sessionUserId) }
        guard isGuestModeActive else { return .signedOut }
        return .guest(userId: localGuestId())
    }
}
