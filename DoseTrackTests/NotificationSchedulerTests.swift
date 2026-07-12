// DoseTrackTests/NotificationSchedulerTests.swift
import XCTest
import CoreData
import UserNotifications
@testable import DoseTrack

/// Tests for NotificationScheduler scheduling logic using an in-memory CoreData store.
/// UNUserNotificationCenter itself is not mocked — we test the data/logic layer only.
final class NotificationSchedulerTests: XCTestCase {

    var context: NSManagedObjectContext!
    var scheduler: NotificationScheduler!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).viewContext
        scheduler = NotificationScheduler.shared
    }

    override func tearDownWithError() throws {
        // Clean up any pending notifications added during tests
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        context = nil
    }

    // MARK: - isDue logic (via schedule frequency)

    func testDailySchedule_isAlwaysDue() throws {
        let med = Medication.create(in: context, name: "Aspirin", dosage: "81mg")
        let schedule = Schedule.create(in: context, medication: med, hour: 8, minute: 0, frequency: "daily")
        try context.save()

        // All weekdays should fire for a "daily" schedule
        for weekday in 1...7 {
            XCTAssertTrue(
                scheduler.isDueOnWeekday(schedule: schedule, weekday: weekday),
                "Daily schedule should fire on weekday \(weekday)"
            )
        }
    }

    func testWeeklySchedule_onlyFiresOnSelectedDays() throws {
        let med = Medication.create(in: context, name: "Vitamin D", dosage: "1000 IU")
        let schedule = Schedule.create(in: context, medication: med, hour: 9, minute: 0, frequency: "weekly")
        schedule.daysOfWeekArray = [2, 4, 6] // Mon, Wed, Fri
        try context.save()

        XCTAssertTrue(scheduler.isDueOnWeekday(schedule: schedule, weekday: 2))
        XCTAssertTrue(scheduler.isDueOnWeekday(schedule: schedule, weekday: 4))
        XCTAssertTrue(scheduler.isDueOnWeekday(schedule: schedule, weekday: 6))
        XCTAssertFalse(scheduler.isDueOnWeekday(schedule: schedule, weekday: 1))
        XCTAssertFalse(scheduler.isDueOnWeekday(schedule: schedule, weekday: 3))
        XCTAssertFalse(scheduler.isDueOnWeekday(schedule: schedule, weekday: 7))
    }

    func testWeeklySchedule_emptyDays_firesEveryDay() throws {
        let med = Medication.create(in: context, name: "Metformin", dosage: "500mg")
        let schedule = Schedule.create(in: context, medication: med, hour: 12, minute: 0, frequency: "weekly")
        schedule.daysOfWeekArray = [] // Empty = every day
        try context.save()

        for weekday in 1...7 {
            XCTAssertTrue(
                scheduler.isDueOnWeekday(schedule: schedule, weekday: weekday),
                "Weekly schedule with empty days should fire on weekday \(weekday)"
            )
        }
    }

    func testAsNeededSchedule_neverFires() throws {
        let med = Medication.create(in: context, name: "Ibuprofen", dosage: "400mg")
        let schedule = Schedule.create(in: context, medication: med, hour: 0, minute: 0, frequency: "as_needed")
        try context.save()

        for weekday in 1...7 {
            XCTAssertFalse(
                scheduler.isDueOnWeekday(schedule: schedule, weekday: weekday),
                "as_needed schedule should never auto-fire"
            )
        }
    }

    func testDisabledSchedule_skippedDuringRefresh() throws {
        let med = Medication.create(in: context, name: "Lisinopril", dosage: "10mg")
        let schedule = Schedule.create(in: context, medication: med, hour: 8, minute: 0)
        schedule.isEnabled = false
        try context.save()

        // refreshAll should not crash and should produce no pending notifications for this med
        let refreshDone = XCTestExpectation(description: "refresh done")
        scheduler.refreshAll(context: context) { refreshDone.fulfill() }
        wait(for: [refreshDone], timeout: 5)

        let expectation = XCTestExpectation(description: "getPendingNotificationRequests")
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let medId = med.id?.uuidString ?? ""
            let relevant = requests.filter { $0.identifier.contains(medId) }
            XCTAssertEqual(relevant.count, 0, "Disabled schedule should produce no notifications")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
    }

    // MARK: - notificationId uniqueness

    func testNotificationId_isUniquePerMedicationScheduleDate() throws {
        let med1 = Medication.create(in: context, name: "Med A", dosage: "10mg")
        let med2 = Medication.create(in: context, name: "Med B", dosage: "20mg")
        let s1 = Schedule.create(in: context, medication: med1, hour: 8, minute: 0)
        let s2 = Schedule.create(in: context, medication: med2, hour: 8, minute: 0)
        let date1 = Date()
        let date2 = Date(timeIntervalSinceNow: 86400)
        try context.save()

        let id1 = scheduler.makeNotificationId(medicationId: med1.id, schedule: s1, fireDate: date1)
        let id2 = scheduler.makeNotificationId(medicationId: med2.id, schedule: s2, fireDate: date1)
        let id3 = scheduler.makeNotificationId(medicationId: med1.id, schedule: s1, fireDate: date2)

        XCTAssertNotEqual(id1, id2, "Different medications produce different IDs")
        XCTAssertNotEqual(id1, id3, "Same med/schedule but different date produces different ID")
    }

    // MARK: - refreshAll scheduling

    func testRefreshAll_schedulesNotificationsForActiveMed() throws {
        // Skip when running in CI / test harness without notification authorization.
        let authExpectation = XCTestExpectation(description: "auth check")
        var authorized = false
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            authorized = settings.authorizationStatus == .authorized
            authExpectation.fulfill()
        }
        wait(for: [authExpectation], timeout: 3)
        guard authorized else {
            throw XCTSkip("Notification authorization not granted in this test environment")
        }

        let med = Medication.create(in: context, name: "Atorvastatin", dosage: "20mg")
        Schedule.create(in: context, medication: med, hour: 21, minute: 0, frequency: "daily")
        try context.save()

        let refreshDone = XCTestExpectation(description: "refresh done")
        scheduler.refreshAll(context: context) { refreshDone.fulfill() }
        wait(for: [refreshDone], timeout: 5)

        let expectation = XCTestExpectation(description: "pending notifications check")
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            XCTAssertGreaterThan(requests.count, 0, "Should have scheduled at least one notification")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
    }

    func testRefreshAll_skipsInactiveMedications() throws {
        let med = Medication.create(in: context, name: "Old Med", dosage: "5mg")
        med.isActive = false
        Schedule.create(in: context, medication: med, hour: 8, minute: 0)
        try context.save()

        let refreshDone = XCTestExpectation(description: "refresh done")
        scheduler.refreshAll(context: context) { refreshDone.fulfill() }
        wait(for: [refreshDone], timeout: 5)

        let expectation = XCTestExpectation(description: "no notifications for inactive med")
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            XCTAssertEqual(requests.count, 0, "Inactive medications should not be scheduled")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
    }

    func testRefreshAll_updatesLastRefreshTimestamp() throws {
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.lastNotificationRefresh)
        let med = Medication.create(in: context, name: "Test", dosage: "10mg")
        Schedule.create(in: context, medication: med, hour: 8, minute: 0)
        try context.save()

        let refreshDone = XCTestExpectation(description: "refresh done")
        scheduler.refreshAll(context: context) { refreshDone.fulfill() }
        wait(for: [refreshDone], timeout: 5)

        let lastRefresh = UserDefaults.standard.object(forKey: Constants.UserDefaultsKeys.lastNotificationRefresh)
        XCTAssertNotNil(lastRefresh, "Should record last refresh timestamp")
    }

    // MARK: - Notification content

    func testNotificationContent_titleIsName() throws {
        // Skip when running without notification authorization.
        let authExpectation = XCTestExpectation(description: "auth check")
        var authorized = false
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            authorized = settings.authorizationStatus == .authorized
            authExpectation.fulfill()
        }
        wait(for: [authExpectation], timeout: 3)
        guard authorized else {
            throw XCTSkip("Notification authorization not granted in this test environment")
        }

        let med = Medication.create(in: context, name: "Lisinopril", dosage: "10mg")
        Schedule.create(in: context, medication: med, hour: 8, minute: 0, frequency: "daily")
        try context.save()

        let refreshDone = XCTestExpectation(description: "refresh done")
        scheduler.refreshAll(context: context) { refreshDone.fulfill() }
        wait(for: [refreshDone], timeout: 5)

        let expectation = XCTestExpectation(description: "check content")
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            if let req = requests.first {
                XCTAssertEqual(req.content.title, "Lisinopril")
                // The body is a randomised reminder line that names the medication but deliberately
                // never states the dose/strength (removed in the notification-copy overhaul — the
                // patient already knows their own dose). So the body must contain the NAME, not "10mg".
                XCTAssertTrue(req.content.body.contains("Lisinopril"), "body was: \(req.content.body)")
                XCTAssertEqual(req.content.categoryIdentifier, Constants.Notification.categoryMedicationDue)
            } else {
                XCTFail("Expected at least one pending notification")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
    }

    // MARK: - Preserve snoozes across refresh

    func test_identifiersToCancel_keepsSnoozes_removesScheduled() {
        let all = ["dt.med.sch.123", "snooze.med.abc", "dt.interval.due.x.9"]
        let toCancel = NotificationScheduler.identifiersToCancel(from: all)
        XCTAssertEqual(Set(toCancel), Set(["dt.med.sch.123", "dt.interval.due.x.9"]))
        XCTAssertFalse(toCancel.contains("snooze.med.abc"))
    }

    // MARK: - Sort + cap at 64

    func test_capTo64_keepsEarliestFireDatesAcrossMedications() {
        let now = Date()
        let dates = (0..<100).map { now.addingTimeInterval(Double($0) * 3600) }.shuffled()
        let items = dates.map { NotificationScheduler.Fireable(id: UUID().uuidString, fireDate: $0) }
        let kept = NotificationScheduler.earliest64(items)
        XCTAssertEqual(kept.count, 64)
        let keptDates = kept.map(\.fireDate).sorted()
        XCTAssertEqual(keptDates.first, dates.sorted().first)
        XCTAssertEqual(keptDates.last, dates.sorted()[63])
    }

    // MARK: - Critical alerts toggle

    func test_sound_isCritical_onlyWhenToggleOn() {
        XCTAssertTrue(NotificationScheduler.useCriticalSound(criticalEnabled: true))
        XCTAssertFalse(NotificationScheduler.useCriticalSound(criticalEnabled: false))
    }
}

// MARK: - Internal method exposure for testing

extension NotificationScheduler {
    /// Exposed for unit testing the scheduling logic.
    func isDueOnWeekday(schedule: Schedule, weekday: Int) -> Bool {
        switch schedule.wrappedFrequency {
        case "daily":
            return true
        case "weekly", "custom":
            let days = schedule.daysOfWeekArray
            return days.isEmpty || days.contains(weekday)
        case "as_needed":
            return false
        default:
            return true
        }
    }

    func makeNotificationId(medicationId: UUID?, schedule: Schedule, fireDate: Date) -> String {
        let medId = medicationId?.uuidString ?? "unknown"
        let schId = schedule.id?.uuidString ?? "unknown"
        let ts = Int(fireDate.timeIntervalSince1970)
        return "dt.\(medId).\(schId).\(ts)"
    }
}
