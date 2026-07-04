import Foundation

/// A single meal's clock time (hour/minute only — no date component, since this
/// represents a daily recurring time-of-day, same convention as `Schedule`).
struct MealTime: Equatable, Codable {
    var hour: Int
    var minute: Int
}

/// The app-wide (not per-medication) set of meal times a user can tie a
/// medication's schedule to. This is intentionally global.
struct MealTimes: Equatable {
    var breakfast: MealTime
    var morningTea: MealTime
    var lunch: MealTime
    var afternoonTea: MealTime
    var dinner: MealTime
    var dessert: MealTime
    var midnightSnack: MealTime

    static let `default` = MealTimes(
        breakfast: MealTime(hour: 7, minute: 30),
        morningTea: MealTime(hour: 10, minute: 0),
        lunch: MealTime(hour: 12, minute: 30),
        afternoonTea: MealTime(hour: 15, minute: 0),
        dinner: MealTime(hour: 18, minute: 30),
        dessert: MealTime(hour: 19, minute: 30),
        midnightSnack: MealTime(hour: 23, minute: 0)
    )

    private static let defaultsKey = "mealTimes"

    static func load(from defaults: UserDefaults = .standard) -> MealTimes {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(MealTimes.self, from: data)
        else { return .default }
        return decoded
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}

extension MealTimes: Codable {}
