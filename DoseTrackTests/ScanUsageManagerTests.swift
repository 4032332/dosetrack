// DoseTrackTests/ScanUsageManagerTests.swift
import XCTest
@testable import DoseTrack

@MainActor
final class ScanUsageManagerTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var sut: ScanUsageManager!

    override func setUp() {
        super.setUp()
        suiteName = "ScanUsageManagerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        sut = ScanUsageManager(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Pure gate

    func test_freeUser_allowedUntilLimit_thenBlocked() {
        XCTAssertTrue(ScanUsageManager.canScan(count: 0, isPro: false, hasActiveCaregiver: false))
        XCTAssertTrue(ScanUsageManager.canScan(count: 2, isPro: false, hasActiveCaregiver: false))
        XCTAssertFalse(ScanUsageManager.canScan(count: 3, isPro: false, hasActiveCaregiver: false),
                       "The 4th scan (count already at the 3 limit) must be blocked")
        XCTAssertFalse(ScanUsageManager.canScan(count: 99, isPro: false, hasActiveCaregiver: false))
    }

    func test_proAndCaregiverCovered_neverBlocked() {
        XCTAssertTrue(ScanUsageManager.canScan(count: 100, isPro: true, hasActiveCaregiver: false))
        XCTAssertTrue(ScanUsageManager.canScan(count: 100, isPro: false, hasActiveCaregiver: true))
    }

    // MARK: - Persistence / remote reconciliation

    func test_loadsPersistedCount() {
        defaults.set(2, forKey: "scanCountUsed")
        let reloaded = ScanUsageManager(defaults: defaults)
        XCTAssertEqual(reloaded.scanCount, 2)
        XCTAssertEqual(reloaded.freeScansRemaining, 1)
    }

    func test_applyRemote_neverDecreasesCount() {
        defaults.set(2, forKey: "scanCountUsed")
        let m = ScanUsageManager(defaults: defaults)
        m.applyRemote(1)   // stale/lower server value
        XCTAssertEqual(m.scanCount, 2, "A lower server value must not hand back free scans")
        m.applyRemote(5)   // higher (scanned more on another device)
        XCTAssertEqual(m.scanCount, 5)
    }

    func test_freeScansRemaining_flooring() {
        defaults.set(10, forKey: "scanCountUsed")
        let m = ScanUsageManager(defaults: defaults)
        XCTAssertEqual(m.freeScansRemaining, 0, "Never negative")
    }
}
