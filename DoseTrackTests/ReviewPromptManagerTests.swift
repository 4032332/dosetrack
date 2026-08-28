// DoseTrackTests/ReviewPromptManagerTests.swift
import XCTest
@testable import DoseTrack

@MainActor
final class ReviewPromptManagerTests: XCTestCase {

    private var defaults: UserDefaults!
    private var sut: ReviewPromptManager!
    private let suiteName = "ReviewPromptManagerTests"

    override func setUpWithError() throws {
        // Isolated suite: mutating .standard leaks state between tests and into the test host.
        UserDefaults().removePersistentDomain(forName: suiteName)
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        sut = ReviewPromptManager(defaults: defaults)
    }

    override func tearDownWithError() throws {
        UserDefaults().removePersistentDomain(forName: suiteName)
        defaults = nil
        sut = nil
    }

    /// Puts the manager in a state where every condition is satisfied, so individual tests can
    /// break exactly one of them and prove that condition is what's doing the work.
    private func makeEligible(now: Date) {
        let longAgo = now.addingTimeInterval(-Double(ReviewPromptManager.minimumDaysSinceFirstLaunch + 5) * 86400)
        sut.recordLaunchIfNeeded(now: longAgo)
        sut.recordDoseTaken(count: ReviewPromptManager.doseThreshold)
    }

    // MARK: - The happy path

    func testEligible_whenThresholdAndTenureMet() {
        let now = Date()
        makeEligible(now: now)
        XCTAssertTrue(sut.shouldRequestReview(now: now))
    }

    // MARK: - Each guard, in isolation

    func testNotEligible_beforeDoseThreshold() {
        let now = Date()
        makeEligible(now: now)
        // Rebuild with one dose short of the threshold.
        sut.resetForTesting()
        sut.recordLaunchIfNeeded(now: now.addingTimeInterval(-60 * 86400))
        sut.recordDoseTaken(count: ReviewPromptManager.doseThreshold - 1)

        XCTAssertFalse(sut.shouldRequestReview(now: now),
                       "One dose short must not qualify")
    }

    func testNotEligible_whenTooNewDespiteEnoughDoses() {
        let now = Date()
        // Enough doses, but installed only yesterday — a first-day logging burst must not qualify.
        sut.recordLaunchIfNeeded(now: now.addingTimeInterval(-1 * 86400))
        sut.recordDoseTaken(count: ReviewPromptManager.doseThreshold * 2)

        XCTAssertFalse(sut.shouldRequestReview(now: now),
                       "Tenure requirement must hold even with plenty of doses")
    }

    func testNotEligible_whenFirstLaunchWasNeverRecorded() {
        let now = Date()
        sut.recordDoseTaken(count: ReviewPromptManager.doseThreshold)
        // No recordLaunchIfNeeded call at all.
        XCTAssertFalse(sut.shouldRequestReview(now: now),
                       "Missing tenure data must fail closed, not assume a long tenure")
    }

    // MARK: - Cooldown between asks

    func testNotEligible_immediatelyAfterAsking() {
        let now = Date()
        makeEligible(now: now)
        XCTAssertTrue(sut.shouldRequestReview(now: now))

        sut.recordRequestMade(now: now)

        XCTAssertFalse(sut.shouldRequestReview(now: now),
                       "Must not ask twice in a row")
    }

    func testStillNotEligible_partwayThroughCooldown() {
        let now = Date()
        makeEligible(now: now)
        sut.recordRequestMade(now: now)

        let partway = now.addingTimeInterval(Double(ReviewPromptManager.daysBetweenRequests - 1) * 86400)
        XCTAssertFalse(sut.shouldRequestReview(now: partway))
    }

    func testEligibleAgain_onceCooldownElapses() {
        let now = Date()
        makeEligible(now: now)
        sut.recordRequestMade(now: now)

        let afterCooldown = now.addingTimeInterval(Double(ReviewPromptManager.daysBetweenRequests + 1) * 86400)
        XCTAssertTrue(sut.shouldRequestReview(now: afterCooldown),
                      "Someone who skipped the prompt should be asked again eventually")
    }

    // MARK: - Lifetime ceiling

    func testNeverAsksBeyondMaximumRequests() {
        var now = Date()
        makeEligible(now: now)

        for _ in 0..<ReviewPromptManager.maximumRequests {
            XCTAssertTrue(sut.shouldRequestReview(now: now))
            sut.recordRequestMade(now: now)
            now = now.addingTimeInterval(Double(ReviewPromptManager.daysBetweenRequests + 1) * 86400)
        }

        XCTAssertFalse(sut.shouldRequestReview(now: now),
                       "Must stop permanently after the lifetime cap, even once cooldown passes")
        XCTAssertEqual(sut.requestCount, ReviewPromptManager.maximumRequests)
    }

    // MARK: - Opt-out via the Settings link

    func testOptOut_stopsPromptsPermanently() {
        let now = Date()
        makeEligible(now: now)
        XCTAssertTrue(sut.shouldRequestReview(now: now))

        sut.optOutOfAutomaticPrompts()

        XCTAssertFalse(sut.shouldRequestReview(now: now),
                       "Tapping Settings → Rate DoseTrack must stop automatic prompts")
        // And it stays off far into the future.
        let muchLater = now.addingTimeInterval(400 * 86400)
        XCTAssertFalse(sut.shouldRequestReview(now: muchLater))
    }

    // MARK: - Counting

    func testRecordDoseTaken_accumulates() {
        sut.recordDoseTaken()
        sut.recordDoseTaken(count: 4)
        XCTAssertEqual(sut.lifetimeDosesTaken, 5)
    }

    func testRecordLaunch_isIdempotent() {
        let first = Date().addingTimeInterval(-100 * 86400)
        sut.recordLaunchIfNeeded(now: first)
        // A later launch must not overwrite the original date, or tenure would reset every launch
        // and the prompt could never fire.
        sut.recordLaunchIfNeeded(now: Date())

        sut.recordDoseTaken(count: ReviewPromptManager.doseThreshold)
        XCTAssertTrue(sut.shouldRequestReview(now: Date()),
                      "First-launch date must be preserved across launches")
    }
}
