// DoseTrack/Models/CaregiverRelationshipRow.swift
// Codable row model mirroring the `caregiver_relationships` Supabase table.
// Display names are denormalized snapshots captured at invite-create/accept time —
// this app has no `profiles` table to join against.

import Foundation

struct CaregiverRelationshipRow: Codable, Identifiable {
    let id: UUID
    let caregiverUserId: UUID?
    let patientUserId: UUID
    let patientDisplayName: String
    let caregiverDisplayName: String?
    let status: String
    let inviteCode: String
    let createdAt: Date
    let expiresAt: Date
    let activatedAt: Date?
    let revokedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, status
        case caregiverUserId = "caregiver_user_id"
        case patientUserId = "patient_user_id"
        case patientDisplayName = "patient_display_name"
        case caregiverDisplayName = "caregiver_display_name"
        case inviteCode = "invite_code"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case activatedAt = "activated_at"
        case revokedAt = "revoked_at"
    }

    var isPending: Bool { status == "pending" }
    var isActive: Bool { status == "active" }
    var isRevoked: Bool { status == "revoked" }
    var isExpired: Bool { expiresAt < Date() }
}
