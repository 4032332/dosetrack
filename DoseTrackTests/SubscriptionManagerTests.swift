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
        XCTAssertEqual(Constants.StoreKit.proMonthly, "com.robbrown.dosetrack.pro.monthly3")
        XCTAssertEqual(Constants.StoreKit.proAnnual, "com.robbrown.dosetrack.pro.annual2")
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

    // MARK: - Promo code

    func testConstants_promoCode_thresholdsAreFinalFiveDays() {
        XCTAssertEqual(Constants.PromoCode.reminderThresholds, [5, 4, 3, 2, 1])
        XCTAssertEqual(Constants.PromoCode.durationDays, 30)
    }

    func testRedeemPromoCode_guest_returnsRequiresAccount() async {
        let manager = SubscriptionManager()
        let outcome = await manager.redeemPromoCode(
            Constants.PromoCode.sharedCode, userId: UUID(), isGuest: true
        )
        guard case .requiresAccount = outcome else {
            return XCTFail("Expected .requiresAccount, got \(outcome)")
        }
    }

    func testRedeemPromoCode_noUserId_returnsRequiresAccount() async {
        let manager = SubscriptionManager()
        let outcome = await manager.redeemPromoCode(
            Constants.PromoCode.sharedCode, userId: nil, isGuest: false
        )
        guard case .requiresAccount = outcome else {
            return XCTFail("Expected .requiresAccount, got \(outcome)")
        }
    }

    func testRedeemPromoCode_wrongCode_returnsInvalidCode_withoutNetworkCall() async {
        // A mismatched code is rejected before any Supabase call is made, so this is safe to
        // run without network access or a real account.
        let manager = SubscriptionManager()
        let outcome = await manager.redeemPromoCode(
            "NOT-THE-REAL-CODE", userId: UUID(), isGuest: false
        )
        guard case .invalidCode = outcome else {
            return XCTFail("Expected .invalidCode, got \(outcome)")
        }
    }

    func testPromoExpiryReminderDaysRemaining_returnsNil_whenNoPromoActive() {
        let manager = SubscriptionManager()
        XCTAssertNil(manager.promoExpiryReminderDaysRemaining())
    }
}
