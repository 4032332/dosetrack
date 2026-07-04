import XCTest
@testable import DoseTrack

final class MealTimesTests: XCTestCase {
    func test_defaultsMatchSpec() {
        let times = MealTimes.default
        XCTAssertEqual(times.breakfast, MealTime(hour: 7, minute: 30))
        XCTAssertEqual(times.morningTea, MealTime(hour: 10, minute: 0))
        XCTAssertEqual(times.lunch, MealTime(hour: 12, minute: 30))
        XCTAssertEqual(times.afternoonTea, MealTime(hour: 15, minute: 0))
        XCTAssertEqual(times.dinner, MealTime(hour: 18, minute: 30))
        XCTAssertEqual(times.dessert, MealTime(hour: 19, minute: 30))
        XCTAssertEqual(times.midnightSnack, MealTime(hour: 23, minute: 0))
    }

    func test_loadFallsBackToDefaultsWhenUnset() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let times = MealTimes.load(from: defaults)
        XCTAssertEqual(times, MealTimes.default)
    }

    func test_saveThenLoadRoundTrips() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        var times = MealTimes.default
        times.lunch = MealTime(hour: 13, minute: 15)
        times.save(to: defaults)
        let loaded = MealTimes.load(from: defaults)
        XCTAssertEqual(loaded.lunch, MealTime(hour: 13, minute: 15))
        XCTAssertEqual(loaded.breakfast, MealTimes.default.breakfast)
    }
}
