// DoseTrackTests/SubscriptionManagerTests.swift
import XCTest
@testable import DoseTrack

/// Note: Full StoreKit 2 purchase-flow testing requires a StoreKit test plan.
/// These tests verify synchronous/cached behaviour that doesn't need the App Store.
@MainActor
final class SubscriptionManagerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.set(false, forKey: Constants.UserDefaultsKeys.isProSubscriber)
    }

    override func tearDown() {
        UserDefaults.standard.set(false, forKey: Constants.UserDefaultsKeys.isProSubscriber)
        super.tearDown()
    }

    func testIsProSubscriber_defaultsToFalse() {
        let manager = SubscriptionManager()
        XCTAssertFalse(manager.isProSubscriber)
    }

    func testIsProSubscriber_respectsCachedTrueValue() {
        UserDefaults.standard.set(true, forKey: Constants.UserDefaultsKeys.isProSubscriber)
        let manager = SubscriptionManager()
        XCTAssertTrue(manager.isProSubscriber)
    }

    func testConstants_productIDs_areCorrect() {
        XCTAssertEqual(Constants.StoreKit.proMonthly, "com.robbrown.dosetrack.pro.monthly")
        XCTAssertEqual(Constants.StoreKit.proAnnual, "com.robbrown.dosetrack.pro.annual")
    }

    func testConstants_freeTier_maxFiveMeds() {
        XCTAssertEqual(Constants.FreeTier.maxMedications, 5)
    }

    func testConstants_appGroup_identifier() {
        XCTAssertEqual(Constants.AppGroup.identifier, "group.com.robbrown.dosetrack")
    }

    func testConstants_notificationActions_areCorrect() {
        XCTAssertEqual(Constants.Notification.categoryMedicationDue, "MEDICATION_DUE")
        XCTAssertEqual(Constants.Notification.actionTakeDose, "TAKE_DOSE")
        XCTAssertEqual(Constants.Notification.actionSkipDose, "SKIP_DOSE")
        XCTAssertEqual(Constants.Notification.actionSnooze30, "SNOOZE_30")
    }
}
