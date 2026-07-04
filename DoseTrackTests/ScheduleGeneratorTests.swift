import XCTest
@testable import DoseTrack

final class ScheduleGeneratorTests: XCTestCase {
    func test_generatesSequentialTimesWithoutWrapping() {
        let times = ScheduleGenerator.intervalTimes(
            first: MealTime(hour: 6, minute: 0), intervalHours: 4, count: 4
        )
        XCTAssertEqual(times, [
            MealTime(hour: 6, minute: 0),
            MealTime(hour: 10, minute: 0),
            MealTime(hour: 14, minute: 0),
            MealTime(hour: 18, minute: 0),
        ])
    }

    func test_wrapsPastMidnightRatherThanErroring() {
        let times = ScheduleGenerator.intervalTimes(
            first: MealTime(hour: 22, minute: 0), intervalHours: 6, count: 4
        )
        XCTAssertEqual(times, [
            MealTime(hour: 22, minute: 0),
            MealTime(hour: 4, minute: 0),
            MealTime(hour: 10, minute: 0),
            MealTime(hour: 16, minute: 0),
        ])
    }

    func test_countOfOneReturnsJustTheFirstTime() {
        let times = ScheduleGenerator.intervalTimes(
            first: MealTime(hour: 9, minute: 15), intervalHours: 5, count: 1
        )
        XCTAssertEqual(times, [MealTime(hour: 9, minute: 15)])
    }

    func test_largeCountAndIntervalCanProduceDuplicatesWithoutCrashing() {
        let times = ScheduleGenerator.intervalTimes(
            first: MealTime(hour: 0, minute: 0), intervalHours: 24, count: 3
        )
        XCTAssertEqual(times, [
            MealTime(hour: 0, minute: 0),
            MealTime(hour: 0, minute: 0),
            MealTime(hour: 0, minute: 0),
        ])
    }
}
