import XCTest
@testable import DoseTrack

final class CaregiverManagerTests: XCTestCase {
    func test_relationshipDisplaysAsPendingBeforeActivation() {
        let row = CaregiverRelationshipRow(
            id: UUID(), caregiverUserId: nil, patientUserId: UUID(),
            patientDisplayName: "Mom", caregiverDisplayName: nil,
            status: "pending", inviteCode: "ABC123", createdAt: Date(),
            expiresAt: Date().addingTimeInterval(86_400), activatedAt: nil, revokedAt: nil
        )
        XCTAssertTrue(row.isPending)
        XCTAssertFalse(row.isActive)
        XCTAssertFalse(row.isExpired)
    }

    func test_relationshipIsExpiredPastExpiresAt() {
        let row = CaregiverRelationshipRow(
            id: UUID(), caregiverUserId: nil, patientUserId: UUID(),
            patientDisplayName: "Mom", caregiverDisplayName: nil,
            status: "pending", inviteCode: "ABC123", createdAt: Date().addingTimeInterval(-90_000),
            expiresAt: Date().addingTimeInterval(-3_600), activatedAt: nil, revokedAt: nil
        )
        XCTAssertTrue(row.isExpired)
    }
}
