// DoseTrackTests/ActiveAccountResolverTests.swift
import XCTest
@testable import DoseTrack

@MainActor
final class ActiveAccountResolverTests: XCTestCase {
    func test_defaultsToNil_meaningOwnAccount() {
        let sut = ActiveAccountResolver()
        XCTAssertNil(sut.activeUserId)
    }

    func test_setAndReadBack() {
        let sut = ActiveAccountResolver()
        let id = UUID()
        sut.set(activeUserId: id)
        XCTAssertEqual(sut.activeUserId, id)
    }

    func test_clearReturnsToOwnAccount() {
        let sut = ActiveAccountResolver()
        sut.set(activeUserId: UUID())
        sut.set(activeUserId: nil)
        XCTAssertNil(sut.activeUserId)
    }
}
