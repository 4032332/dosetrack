import Foundation

/// A single meal's clock time (hour/minute only — no date component, since this
/// represents a daily recurring time-of-day, same convention as `Schedule`).
struct MealTime: Equatable, Codable {
    var hour: Int
    var minute: Int
}

/// The app-wide (not per-medication) set of "Daily Routine Times" a user can tie a
/// medication's schedule to — the meals plus Wake up and Bedtime. Intentionally global.
struct MealTimes: Equatable {
    var wakeUp: MealTime
    var breakfast: MealTime
    var morningTea: MealTime
    var lunch: MealTime
    var afternoonTea: MealTime
    var dinner: MealTime
    var dessert: MealTime
    var midnightSnack: MealTime
    var bedtime: MealTime

    static let `default` = MealTimes(
        wakeUp: MealTime(hour: 7, minute: 0),
        breakfast: MealTime(hour: 7, minute: 30),
        morningTea: MealTime(hour: 10, minute: 0),
        lunch: MealTime(hour: 12, minute: 30),
        afternoonTea: MealTime(hour: 15, minute: 0),
        dinner: MealTime(hour: 18, minute: 30),
        dessert: MealTime(hour: 19, minute: 30),
        midnightSnack: MealTime(hour: 23, minute: 0),
        bedtime: MealTime(hour: 22, minute: 0)
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

extension MealTimes: Codable {
    // Custom decode so JSON saved before Wake up / Bedtime existed still loads (keeping the
    // user's customised meal times) instead of failing the decode and resetting everything to
    // .default. Missing routine slots fall back to their default value.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MealTimes.default
        wakeUp        = try c.decodeIfPresent(MealTime.self, forKey: .wakeUp) ?? d.wakeUp
        breakfast     = try c.decodeIfPresent(MealTime.self, forKey: .breakfast) ?? d.breakfast
        morningTea    = try c.decodeIfPresent(MealTime.self, forKey: .morningTea) ?? d.morningTea
        lunch         = try c.decodeIfPresent(MealTime.self, forKey: .lunch) ?? d.lunch
        afternoonTea  = try c.decodeIfPresent(MealTime.self, forKey: .afternoonTea) ?? d.afternoonTea
        dinner        = try c.decodeIfPresent(MealTime.self, forKey: .dinner) ?? d.dinner
        dessert       = try c.decodeIfPresent(MealTime.self, forKey: .dessert) ?? d.dessert
        midnightSnack = try c.decodeIfPresent(MealTime.self, forKey: .midnightSnack) ?? d.midnightSnack
        bedtime       = try c.decodeIfPresent(MealTime.self, forKey: .bedtime) ?? d.bedtime
    }
}
