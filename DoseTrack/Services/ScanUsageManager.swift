// DoseTrack/Services/ScanUsageManager.swift
// Tracks how many times the free tier has used the medication scanner. The scanner is a DoseTrack
// Plus feature, but free users get a lifetime allowance of 3 successful scans (a scan counts only
// when it actually results in a saved medication) before it's paywalled. Plus subscribers — and
// patients covered by an active caregiver's plan — are never gated.
//
// The count is stored locally and mirrored to the signed-in account (user_settings.scan_count) via
// the normal settings sync, so a reinstall or a second device can't reset the allowance. It
// degrades gracefully if the server column isn't there yet: the local count still gates.

import Foundation

@MainActor
final class ScanUsageManager: ObservableObject {

    static let shared = ScanUsageManager()

    /// Free lifetime scans before the scanner is paywalled.
    static let freeLimit = 3

    private let defaults: UserDefaults
    private static let key = "scanCountUsed"

    @Published private(set) var scanCount: Int

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.scanCount = defaults.integer(forKey: Self.key)
    }

    /// Pure gate: given entitlement inputs, may this user open the scanner? Kept parameterised so
    /// it's unit-testable without the subscription/caregiver singletons.
    static func canScan(count: Int, isPro: Bool, hasActiveCaregiver: Bool) -> Bool {
        isPro || hasActiveCaregiver || count < freeLimit
    }

    /// Convenience gate that reads live entitlement from the shared managers.
    func canScan() -> Bool {
        Self.canScan(
            count: scanCount,
            isPro: SubscriptionManager.shared.isProSubscriber,
            hasActiveCaregiver: CaregiverManager.shared.ownPatientRelationship?.isActive == true
        )
    }

    /// How many free scans remain (for the entry-point hint). Only meaningful for a free user.
    var freeScansRemaining: Int { max(0, Self.freeLimit - scanCount) }

    /// Record that a scan produced a saved medication. No-ops for entitled users (their count
    /// never matters, and not incrementing keeps the number honest if they later downgrade).
    func recordScanSaved() {
        guard !SubscriptionManager.shared.isProSubscriber,
              CaregiverManager.shared.ownPatientRelationship?.isActive != true else { return }
        scanCount += 1
        defaults.set(scanCount, forKey: Self.key)
        Task { await SupabaseSyncManager.shared.pushSettings() }
    }

    /// Apply a value pulled from the server. Never decreases the local count — the allowance is a
    /// lifetime cap, so the highest seen across devices wins (a stale/zero server row can't reset it).
    func applyRemote(_ remote: Int) {
        guard remote > scanCount else { return }
        scanCount = remote
        defaults.set(scanCount, forKey: Self.key)
    }
}
