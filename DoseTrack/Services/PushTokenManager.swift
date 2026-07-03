// DoseTrack/Services/PushTokenManager.swift
// Registers this device for remote (APNs) push notifications and uploads the
// resulting device token to Supabase so caregiver alerts can be delivered
// server-side (e.g. missed-dose notifications to a linked caregiver).
//
// Local medication reminders use UNCalendarNotificationTrigger and never need
// a device token — this is purely for caregiver-facing remote push.

import Foundation
import Supabase

@MainActor
final class PushTokenManager {

    static let shared = PushTokenManager()
    private init() {}

    private var client: SupabaseClient { AuthManager.shared.client }

    /// Uploads the APNs device token for the currently signed-in user.
    /// No-ops silently if there's no signed-in user (e.g. guest mode) —
    /// there is nowhere to attribute the token and no caregiver relationship
    /// can exist without an account.
    func uploadToken(deviceToken: Data) async {
        guard let userId = AuthManager.shared.session?.user.id else { return }
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        let row = DevicePushTokenRow(userId: userId, apnsToken: tokenString)
        do {
            try await client.from("device_push_tokens").upsert(row).execute()
        } catch {
            print("Failed to upload push token: \(error)")
        }
    }
}

// MARK: - Codable row type (matches Supabase column names exactly)

/// Mirrors the live `device_push_tokens` table: user_id, apns_token, updated_at.
/// `updated_at` is left to the database default/trigger where possible, but we
/// set it explicitly here to match the upsert pattern used by other Row types
/// in SupabaseSyncManager.swift (e.g. MedicationRow, ScheduleRow).
struct DevicePushTokenRow: Codable {
    var userId: String
    var apnsToken: String
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case apnsToken = "apns_token"
        case updatedAt = "updated_at"
    }

    init(userId: UUID, apnsToken: String) {
        self.userId = userId.uuidString
        self.apnsToken = apnsToken
        self.updatedAt = Date()
    }
}
