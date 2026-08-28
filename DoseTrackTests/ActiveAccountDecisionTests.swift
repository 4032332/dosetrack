// DoseTrackTests/ActiveAccountDecisionTests.swift
import XCTest
@testable import DoseTrack

/// Regression coverage for the blank-screen bug.
///
/// `AuthManager.continueAsGuest()`'s fallback writes `guestMode` to UserDefaults and posts
/// `.guestModeActivated` in the SAME tick. `RootView.onReceive` handles that notification
/// synchronously and rebuilds the active account — but it used to read SwiftUI's `@AppStorage`
/// cached copy of `guestMode`, which had not yet observed the write. It therefore read `false`,
/// concluded the user was signed out, and set `activeAccount = nil`.
///
/// Nothing recovered from that: `session` goes nil -> nil so `.onChange` never fires, and
/// `.onAppear` had already run. `activeAccount` stayed nil forever, `RootView` fell off the end
/// of its if/else chain, and the app rendered a bare background — a permanent blank screen.
///
/// A unit test cannot reproduce SwiftUI's propagation delay itself. What it CAN do is pin the
/// contract that makes the race impossible by construction: the decision is a pure function of
/// UserDefaults (the authoritative store that was already written), never of a cached mirror.
final class ActiveAccountDecisionTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "ActiveAccountDecisionTests"
    private let guestId = UUID(uuidString: "DA33E223-00B4-4CF8-80BD-D03AC3670A89")!
    private let accountId = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    override func setUpWithError() throws {
        UserDefaults().removePersistentDomain(forName: suiteName)
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        UserDefaults().removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    // MARK: - The regression

    /// THE bug. A session-less guest must resolve to a usable guest context. Resolving to
    /// `.signedOut` here is what produced the blank screen.
    func testResolve_sessionlessGuest_resolvesToGuestNotSignedOut() {
        let decision = ActiveAccountDecision.resolve(
            sessionUserId: nil,
            isGuestModeActive: true,
            localGuestId: { self.guestId }
        )
        XCTAssertEqual(decision, .guest(userId: guestId))
        XCTAssertNotEqual(decision, .signedOut, "A guest with guestMode set must never resolve to signed out")
    }

    /// The race, expressed as the ordering contract it depends on: the moment guest mode is
    /// activated, an immediate read must already see it. `@AppStorage` could not promise this;
    /// UserDefaults can.
    func testGuestModeFlag_isVisibleImmediatelyAfterActivation() {
        XCTAssertFalse(GuestMode.isActive(in: defaults))

        GuestMode.activate(in: defaults)

        // No await, no run-loop turn — exactly what the synchronous notification handler does.
        XCTAssertTrue(GuestMode.isActive(in: defaults),
                      "guestMode must be readable in the same tick it is written, since "
                      + ".guestModeActivated is posted synchronously right after the write")
    }

    /// Signing out must actually clear the flag, or the next launch would resurrect guest mode.
    func testGuestModeFlag_deactivateClearsIt() {
        GuestMode.activate(in: defaults)
        GuestMode.deactivate(in: defaults)
        XCTAssertFalse(GuestMode.isActive(in: defaults))
    }

    // MARK: - The other branches

    func testResolve_noSessionAndNoGuestMode_isSignedOut() {
        let decision = ActiveAccountDecision.resolve(
            sessionUserId: nil,
            isGuestModeActive: false,
            localGuestId: { self.guestId }
        )
        XCTAssertEqual(decision, .signedOut)
    }

    func testResolve_realSession_isSignedIn() {
        let decision = ActiveAccountDecision.resolve(
            sessionUserId: accountId,
            isGuestModeActive: false,
            localGuestId: { self.guestId }
        )
        XCTAssertEqual(decision, .signedIn(userId: accountId))
    }

    /// A stale `guestMode` flag left over from a previous guest session must never downgrade a
    /// real signed-in account to a guest — the real session always wins.
    func testResolve_realSessionWithStaleGuestFlag_stillSignedIn() {
        let decision = ActiveAccountDecision.resolve(
            sessionUserId: accountId,
            isGuestModeActive: true,
            localGuestId: { self.guestId }
        )
        XCTAssertEqual(decision, .signedIn(userId: accountId))
    }

    /// The guest id is only needed on the guest branch; resolving a signed-in or signed-out user
    /// must not generate (and therefore persist) a local guest id as a side effect.
    func testResolve_doesNotGenerateGuestIdUnlessGuest() {
        var generated = false
        let makeId: () -> UUID = { generated = true; return self.guestId }

        _ = ActiveAccountDecision.resolve(sessionUserId: accountId, isGuestModeActive: false, localGuestId: makeId)
        XCTAssertFalse(generated, "signed-in resolution must not touch the guest id")

        _ = ActiveAccountDecision.resolve(sessionUserId: nil, isGuestModeActive: false, localGuestId: makeId)
        XCTAssertFalse(generated, "signed-out resolution must not touch the guest id")

        _ = ActiveAccountDecision.resolve(sessionUserId: nil, isGuestModeActive: true, localGuestId: makeId)
        XCTAssertTrue(generated, "guest resolution needs the guest id")
    }
}
