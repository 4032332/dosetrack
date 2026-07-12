// DoseTrackTests/DisclaimerManagerTests.swift
import XCTest
@testable import DoseTrack

@MainActor
final class DisclaimerManagerTests: XCTestCase {

    private let guestKey = "disclaimerAcceptedAt.guest"
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var sut: DisclaimerManager!

    override func setUp() {
        super.setUp()
        // A fresh, isolated UserDefaults suite per test — DisclaimerManager caches acceptance in
        // whatever store it's given, so injecting a throwaway suite keeps every test hermetic
        // (no leakage from other tests, or from the app/test-host's `.standard` domain, which
        // previously made these flaky).
        suiteName = "DisclaimerManagerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        sut = DisclaimerManager(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        sut = nil
        super.tearDown()
    }

    func test_freshGuest_requiresAcceptance() async {
        await sut.evaluate(userId: nil, isGuest: true)
        XCTAssertEqual(sut.status, .required)
    }

    func test_accept_marksAcceptedAndPersistsLocally() async {
        await sut.accept(userId: nil, isGuest: true)
        XCTAssertEqual(sut.status, .accepted)
        XCTAssertNotNil(defaults.object(forKey: guestKey))
    }

    func test_afterAccept_reEvaluationStaysAccepted_viaLocalFlag() async {
        await sut.accept(userId: nil, isGuest: true)
        sut.reset()
        XCTAssertEqual(sut.status, .unknown)

        await sut.evaluate(userId: nil, isGuest: true)
        XCTAssertEqual(sut.status, .accepted,
                       "A previously-accepted identity must not be re-prompted")
    }

    func test_reset_returnsToUnknown() {
        sut.reset()
        XCTAssertEqual(sut.status, .unknown)
    }
}
