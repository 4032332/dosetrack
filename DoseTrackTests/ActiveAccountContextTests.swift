import XCTest
@testable import DoseTrack

@MainActor
final class ActiveAccountContextTests: XCTestCase {
    func test_defaultsToSignedInUser() {
        let ownId = UUID()
        let ctx = ActiveAccountContext(ownUserId: ownId, ownDisplayName: "Me")
        XCTAssertEqual(ctx.activeUserId, ownId)
        XCTAssertFalse(ctx.isViewingOtherAccount)
    }

    func test_switchingToPatientUpdatesActiveUserId() {
        let ownId = UUID()
        let patientId = UUID()
        let ctx = ActiveAccountContext(ownUserId: ownId, ownDisplayName: "Me")
        ctx.switchTo(userId: patientId, displayName: "Mom")
        XCTAssertEqual(ctx.activeUserId, patientId)
        XCTAssertTrue(ctx.isViewingOtherAccount)
    }

    func test_switchingBackToOwnAccount() {
        let ownId = UUID()
        let ctx = ActiveAccountContext(ownUserId: ownId, ownDisplayName: "Me")
        ctx.switchTo(userId: UUID(), displayName: "Mom")
        ctx.switchToOwnAccount()
        XCTAssertEqual(ctx.activeUserId, ownId)
        XCTAssertFalse(ctx.isViewingOtherAccount)
    }
}
