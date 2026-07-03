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
}
