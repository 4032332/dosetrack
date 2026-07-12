// DoseTrackTests/RoutineStoreTests.swift
import XCTest
@testable import DoseTrack

final class RoutineStoreTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "RoutineStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - Defaults

    func test_freshUser_getsOnlyTwoAnchors() {
        let store = RoutineStore.load(from: defaults)
        XCTAssertEqual(store.routines.count, 2)
        XCTAssertEqual(store.wakeUp.hour, 6)
        XCTAssertEqual(store.wakeUp.minute, 0)
        XCTAssertEqual(store.bedtime.hour, 21)
        XCTAssertEqual(store.bedtime.minute, 0)
        XCTAssertTrue(store.routines.allSatisfy { $0.isAnchor })
    }

    // MARK: - Persistence round-trip

    func test_saveThenLoad_preservesUserAddedRoutine() {
        var store = RoutineStore.default
        store.routines.append(Routine(name: "After Lunch", hour: 13, minute: 30))
        store.save(to: defaults)

        let reloaded = RoutineStore.load(from: defaults)
        XCTAssertEqual(reloaded.routines.count, 3)
        XCTAssertTrue(reloaded.routines.contains { $0.name == "After Lunch" && $0.hour == 13 && $0.minute == 30 })
    }

    // MARK: - Legacy migration

    func test_load_migratesLegacyMealTimes_preservingAllSlots() {
        // Simulate an upgrading user who has a legacy `mealTimes` blob but no `routines` yet.
        var meals = MealTimes.default
        meals.lunch = MealTime(hour: 12, minute: 45)
        meals.wakeUp = MealTime(hour: 5, minute: 15)
        meals.save(to: defaults)

        let store = RoutineStore.load(from: defaults)
        // All nine legacy slots become routines (the "migrate all set times" choice).
        XCTAssertEqual(store.routines.count, 9)
        // Anchors keep their customised times and anchor identity.
        XCTAssertEqual(store.wakeUp.hour, 5)
        XCTAssertEqual(store.wakeUp.minute, 15)
        XCTAssertEqual(store.wakeUp.anchor, .wakeUp)
        XCTAssertEqual(store.bedtime.anchor, .bedtime)
        // A non-anchor slot carries across too.
        XCTAssertTrue(store.routines.contains { $0.name == "Lunch" && $0.hour == 12 && $0.minute == 45 && !$0.isAnchor })
        // The migrated blob is written to `routines` so subsequent loads don't re-migrate.
        XCTAssertNotNil(defaults.data(forKey: RoutineStore.defaultsKey))
    }

    func test_load_prefersRoutinesOverLegacyMealTimes() {
        // Both present: `routines` wins.
        MealTimes.default.save(to: defaults)
        var store = RoutineStore.default
        store.routines.append(Routine(name: "Snack", hour: 16, minute: 0))
        store.save(to: defaults)

        let loaded = RoutineStore.load(from: defaults)
        XCTAssertEqual(loaded.routines.count, 3)
        XCTAssertTrue(loaded.routines.contains { $0.name == "Snack" })
    }

    // MARK: - ensuringAnchors

    func test_ensuringAnchors_reinsertsMissingAnchors() {
        let store = RoutineStore(routines: [Routine(name: "Only Custom", hour: 10, minute: 0)])
        let fixed = store.ensuringAnchors()
        XCTAssertTrue(fixed.routines.contains { $0.anchor == .wakeUp })
        XCTAssertTrue(fixed.routines.contains { $0.anchor == .bedtime })
        XCTAssertTrue(fixed.routines.contains { $0.name == "Only Custom" })
    }

    // MARK: - Legacy bridge back to MealTimes

    func test_asMealTimes_mapsAnchorsAndNamedSlots() {
        var store = RoutineStore.default
        if let i = store.routines.firstIndex(where: { $0.anchor == .wakeUp }) {
            store.routines[i].hour = 5; store.routines[i].minute = 45
        }
        store.routines.append(Routine(name: "Dinner", hour: 19, minute: 0))

        let meals = store.asMealTimes()
        XCTAssertEqual(meals.wakeUp.hour, 5)
        XCTAssertEqual(meals.wakeUp.minute, 45)
        XCTAssertEqual(meals.dinner.hour, 19)
        XCTAssertEqual(meals.dinner.minute, 0)
    }
}
