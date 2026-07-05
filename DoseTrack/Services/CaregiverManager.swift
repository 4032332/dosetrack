// DoseTrack/Services/CaregiverManager.swift
// Manages caregiver-relationship CRUD and invite generate/accept against Supabase.

import Foundation
import Supabase

@MainActor
final class CaregiverManager: ObservableObject {
    static let shared = CaregiverManager()
    private init() {}

    private var client: SupabaseClient { AuthManager.shared.client }

    @Published var myRelationships: [CaregiverRelationshipRow] = []

    /// Relationships where the signed-in user is the caregiver (active only) — drives the account switcher.
    var overseenPatients: [CaregiverRelationshipRow] {
        myRelationships.filter { $0.isActive && $0.caregiverUserId == AuthManager.shared.session?.user.id }
    }

    /// The signed-in user's own relationship as a patient, if any (pending or active) — drives Settings display.
    var ownPatientRelationship: CaregiverRelationshipRow? {
        myRelationships.first { $0.patientUserId == AuthManager.shared.session?.user.id && !$0.isRevoked }
    }

    func refresh() async {
        guard let userId = AuthManager.shared.session?.user.id else { return }
        do {
            let response: [CaregiverRelationshipRow] = try await client
                .from("caregiver_relationships")
                .select()
                .or("caregiver_user_id.eq.\(userId),patient_user_id.eq.\(userId)")
                .execute()
                .value
            myRelationships = response
        } catch {
            print("CaregiverManager refresh error: \(error)")
        }
    }

    struct InviteResponse: Decodable { let code: String; let link: String }

    func createInvite() async throws -> InviteResponse {
        let response: InviteResponse = try await client.functions
            .invoke("create-caregiver-invite", options: .init(body: [String: String]()))
        await refresh()
        return response
    }

    struct AcceptResponse: Decodable { let patientUserId: UUID }

    func acceptInvite(code: String) async throws -> AcceptResponse {
        let response: AcceptResponse = try await client.functions
            .invoke("accept-caregiver-invite", options: .init(body: ["code": code]))
        await refresh()
        return response
    }

    func revoke(relationshipId: UUID) async throws {
        try await client.from("caregiver_relationships")
            .update(["status": "revoked", "revoked_at": ISO8601DateFormatter().string(from: Date())])
            .eq("id", value: relationshipId.uuidString)
            .execute()
        await refresh()
    }

    #if DEBUG
    // MARK: - Debug-only caregiver mode preview
    //
    // Lets a developer preview the caregiver-side UI (account switcher, "viewing
    // another account" capsule, empty-patient-store screens) without a second
    // Supabase account and a real invite/accept round-trip. The fake patient id
    // is deliberately DIFFERENT from the developer's own user id — `RootView`
    // only swaps to the separate per-patient CoreData store (and only shows a
    // single checkmark in the switcher) when `activeUserId != ownUserId`. Using
    // the same id here silently no-ops the switch (same store, same data, both
    // rows checked) — a bug caught during manual testing. Because this fake id
    // has no real Supabase-side data, switching to it correctly lands on an
    // empty patient store; that's the honest state for a fabricated
    // relationship, not a bug. Never present in release builds (#if DEBUG).

    private static let debugRelationshipId = UUID(uuidString: "00000000-0000-0000-0000-00000000DEBB")!
    private static let debugPatientId = UUID(uuidString: "00000000-0000-0000-0000-0000000DEB17")!

    var isDebugCaregiverModeActive: Bool {
        myRelationships.contains { $0.id == Self.debugRelationshipId }
    }

    func setDebugCaregiverModeActive(_ active: Bool) {
        if active {
            guard let userId = AuthManager.shared.session?.user.id, !isDebugCaregiverModeActive else { return }
            let fake = CaregiverRelationshipRow(
                id: Self.debugRelationshipId,
                caregiverUserId: userId,
                patientUserId: Self.debugPatientId,
                patientDisplayName: "Test Patient (Debug)",
                caregiverDisplayName: nil,
                status: "active",
                inviteCode: "DEBUG",
                createdAt: Date(),
                expiresAt: Date.distantFuture,
                activatedAt: Date(),
                revokedAt: nil
            )
            myRelationships.append(fake)
        } else {
            myRelationships.removeAll { $0.id == Self.debugRelationshipId }
        }
    }
    #endif
}
