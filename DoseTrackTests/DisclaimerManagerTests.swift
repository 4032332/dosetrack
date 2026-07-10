// DoseTrackTests/DisclaimerManagerTests.swift
import XCTest
@testable import DoseTrack

@MainActor
final class DisclaimerManagerTests: XCTestCase {

    private let guestKey = "disclaimerAcceptedAt.guest"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: guestKey)
        DisclaimerManager.shared.reset()
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: guestKey)
        super.tearDown()
    }

    func test_freshGuest_requiresAcceptance() async {
        await DisclaimerManager.shared.evaluate(userId: nil, isGuest: true)
        XCTAssertEqual(DisclaimerManager.shared.status, .required)
    }

    func test_accept_marksAcceptedAndPersistsLocally() async {
        await DisclaimerManager.shared.accept(userId: nil, isGuest: true)
        XCTAssertEqual(DisclaimerManager.shared.status, .accepted)
        XCTAssertNotNil(UserDefaults.standard.object(forKey: guestKey))
    }

    func test_afterAccept_reEvaluationStaysAccepted_viaLocalFlag() async {
        await DisclaimerManager.shared.accept(userId: nil, isGuest: true)
        DisclaimerManager.shared.reset()
        XCTAssertEqual(DisclaimerManager.shared.status, .unknown)

        await DisclaimerManager.shared.evaluate(userId: nil, isGuest: true)
        XCTAssertEqual(DisclaimerManager.shared.status, .accepted,
                       "A previously-accepted identity must not be re-prompted")
    }

    func test_reset_returnsToUnknown() {
        DisclaimerManager.shared.reset()
        XCTAssertEqual(DisclaimerManager.shared.status, .unknown)
    }
}
