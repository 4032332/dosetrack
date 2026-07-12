import Foundation

/// A single user-defined "Daily Routine Time" — a named time-of-day (e.g. "Wake Up", "Bedtime",
/// "After Lunch") that a medication's schedule can be linked to instead of a fixed clock time.
/// Global (app-wide), not per-medication. Hour/minute only, no date component — same convention
/// as `Schedule` and the legacy `MealTime`.
struct Routine: Identifiable, Equatable, Codable {
    var id: UUID
    var name: String
    var hour: Int
    var minute: Int
    /// The two anchor routines (Wake Up, Bedtime) are seeded for every user, cannot be deleted,
    /// and their times feed the notification-copy morning/bedtime gating (see `NotificationCopy`).
    /// User-added routines have `anchor == nil` and are freely editable and deletable.
    var anchor: Anchor?

    enum Anchor: String, Codable, Equatable {
        case wakeUp
        case bedtime
    }

    var isAnchor: Bool { anchor != nil }

    init(id: UUID = UUID(), name: String, hour: Int, minute: Int, anchor: Anchor? = nil) {
        self.id = id
        self.name = name
        self.hour = hour
        self.minute = minute
        self.anchor = anchor
    }
}

/// The app-wide ordered set of Daily Routine Times. A fresh user starts with just the two
/// anchors (Wake Up 06:00, Bedtime 21:00) and adds more via the "+" in Settings. Persisted as
/// JSON under the "routines" key, and synced to Supabase's `user_settings.routines` column.
struct RoutineStore: Equatable, Codable {
    var routines: [Routine]

    init(routines: [Routine]) {
        self.routines = routines
    }

    // MARK: Defaults

    static let defaultWakeUp = Routine(name: "Wake Up", hour: 6, minute: 0, anchor: .wakeUp)
    static let defaultBedtime = Routine(name: "Bedtime", hour: 21, minute: 0, anchor: .bedtime)

    /// A brand-new user: only the two anchors, per the "default to ONLY Wake Up + Bedtime" brief.
    static var `default`: RoutineStore {
        RoutineStore(routines: [defaultWakeUp, defaultBedtime])
    }

    // MARK: Anchors

    var wakeUp: Routine { routines.first { $0.anchor == .wakeUp } ?? Self.defaultWakeUp }
    var bedtime: Routine { routines.first { $0.anchor == .bedtime } ?? Self.defaultBedtime }

    /// Routines sorted chronologically for display/selection. Ties keep a stable order.
    var sorted: [Routine] {
        routines.sorted { ($0.hour, $0.minute, $0.name) < ($1.hour, $1.minute, $1.name) }
    }

    // MARK: Persistence

    static let defaultsKey = "routines"
    private static let legacyMealTimesKey = "mealTimes"

    static func load(from defaults: UserDefaults = .standard) -> RoutineStore {
        if let data = defaults.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(RoutineStore.self, from: data) {
            return decoded.ensuringAnchors()
        }
        // No routines yet: migrate from the legacy `mealTimes` blob if the user had one, so an
        // upgrading user keeps every time they'd configured (not just Wake Up / Bedtime).
        if defaults.data(forKey: legacyMealTimesKey) != nil {
            let migrated = RoutineStore(migratingFrom: MealTimes.load(from: defaults))
            migrated.save(to: defaults)
            return migrated
        }
        return .default
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    // MARK: Legacy bridge (migration + Supabase's still-present per-meal columns)

    /// Ordered legacy meal slots, as (display name, keyPath into `MealTimes`, anchor if it's one
    /// of the two anchors). Used both to migrate a legacy blob into routines and to keep the
    /// legacy Supabase columns populated for clients that haven't moved to the JSON column yet.
    private static let legacySlots: [(name: String, keyPath: WritableKeyPath<MealTimes, MealTime>, anchor: Routine.Anchor?)] = [
        ("Wake Up",        \.wakeUp,        .wakeUp),
        ("Breakfast",      \.breakfast,     nil),
        ("Morning Tea",    \.morningTea,    nil),
        ("Lunch",          \.lunch,         nil),
        ("Afternoon Tea",  \.afternoonTea,  nil),
        ("Dinner",         \.dinner,        nil),
        ("Dessert",        \.dessert,       nil),
        ("Midnight Snack", \.midnightSnack, nil),
        ("Bedtime",        \.bedtime,       .bedtime),
    ]

    /// Build a routine list from a legacy `MealTimes`, preserving every slot's name + time and
    /// marking Wake Up / Bedtime as anchors.
    init(migratingFrom meals: MealTimes) {
        self.routines = Self.legacySlots.map { slot in
            let t = meals[keyPath: slot.keyPath]
            return Routine(name: slot.name, hour: t.hour, minute: t.minute, anchor: slot.anchor)
        }
    }

    /// Project back onto a `MealTimes` for the legacy Supabase columns: anchors come from this
    /// store's anchors; each named meal slot is filled from a routine whose name matches (case-
    /// insensitively), otherwise left at its `MealTimes.default`. Best-effort — the authoritative
    /// representation is the `routines` JSON; this only keeps un-migrated clients roughly correct.
    func asMealTimes() -> MealTimes {
        var meals = MealTimes.default
        for slot in Self.legacySlots {
            if let anchor = slot.anchor, let r = routines.first(where: { $0.anchor == anchor }) {
                meals[keyPath: slot.keyPath] = MealTime(hour: r.hour, minute: r.minute)
            } else if let r = routines.first(where: { $0.name.caseInsensitiveCompare(slot.name) == .orderedSame }) {
                meals[keyPath: slot.keyPath] = MealTime(hour: r.hour, minute: r.minute)
            }
        }
        return meals
    }

    /// Guarantees both anchors are present (a decoded/synced blob from a buggy or partial write
    /// should never leave the user without a Wake Up or Bedtime to gate notifications on).
    func ensuringAnchors() -> RoutineStore {
        var result = routines
        if !result.contains(where: { $0.anchor == .wakeUp }) { result.insert(Self.defaultWakeUp, at: 0) }
        if !result.contains(where: { $0.anchor == .bedtime }) { result.append(Self.defaultBedtime) }
        return RoutineStore(routines: result)
    }
}
