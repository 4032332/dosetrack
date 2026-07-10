// DoseTrack/Services/DisclaimerManager.swift
// Decides whether the current user must accept the medical disclaimer / terms before reaching the
// app, and records their acceptance. Acceptance is stored on the user's Supabase profile
// (user_settings.disclaimer_accepted_at) and cached locally per-identity so returning users are
// never re-prompted and don't pay a server round-trip on every launch.

import Foundation

@MainActor
final class DisclaimerManager: ObservableObject {

    static let shared = DisclaimerManager()
    private init() {}

    enum Status: Equatable {
        case unknown   // not yet resolved for the current identity (don't show the app yet)
        case required  // must be accepted before proceeding
        case accepted
    }

    @Published var status: Status = .unknown

    private static let localKeyPrefix = "disclaimerAcceptedAt."
    private func localKey(for identity: String) -> String { Self.localKeyPrefix + identity }

    /// A stable string identifying who we're deciding for. Guests / session-less fallback users
    /// share the plain "guest" bucket since they have no server profile.
    private func identity(userId: UUID?, isGuest: Bool) -> String {
        (isGuest ? nil : userId?.uuidString) ?? "guest"
    }

    /// Resolve whether this identity still needs to accept. Fast path is a local flag (set once
    /// on this device on acceptance, or cached after a server confirmation); only a real,
    /// non-guest account with no local record hits the server.
    func evaluate(userId: UUID?, isGuest: Bool) async {
        let id = identity(userId: userId, isGuest: isGuest)

        if UserDefaults.standard.object(forKey: localKey(for: id)) != nil {
            status = .accepted
            return
        }

        // Guests and the session-less guest fallback have no server profile — decide locally.
        guard let userId, !isGuest else {
            status = .required
            return
        }

        // Real account with no local record (fresh account, or a reinstall): ask the server.
        if await SupabaseSyncManager.shared.hasAcceptedDisclaimer(userId: userId) {
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: localKey(for: id))
            status = .accepted
        } else {
            status = .required
        }
    }

    /// Record acceptance for the current identity: cache locally (so it's instant and survives
    /// offline) and, for a real account, persist to the Supabase profile.
    func accept(userId: UUID?, isGuest: Bool) async {
        let id = identity(userId: userId, isGuest: isGuest)
        // Record locally and proceed IMMEDIATELY — the local flag makes acceptance durable, so
        // the user never waits on (or gets trapped by) a slow/failed server write. The Supabase
        // record is then best-effort in the background.
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: localKey(for: id))
        status = .accepted
        if let userId, !isGuest {
            await SupabaseSyncManager.shared.recordDisclaimerAcceptance(userId: userId)
        }
    }

    /// Called on sign-out so the next user's identity is re-evaluated from scratch.
    func reset() {
        status = .unknown
    }
}
