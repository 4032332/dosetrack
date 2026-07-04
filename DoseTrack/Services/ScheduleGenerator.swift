import Foundation

/// Pure logic for turning the guided schedule flow's answers into concrete
/// clock times. Never divides 24 hours by a dose count — always walks forward
/// from a user-supplied first time by a user-supplied hour interval, since
/// dividing evenly would assume doses are spread across a full day including
/// sleep hours.
enum ScheduleGenerator {
    /// Generates `count` times starting at `first`, each `intervalHours` after
    /// the previous, wrapping past midnight (mod 24) rather than erroring.
    /// `intervalHours` must be >= 1 (enforced by the UI's input control, not
    /// re-validated here). Duplicate times from a wrap are returned as-is, not
    /// deduplicated — the caller (guided flow's Review step) is where a user
    /// notices and fixes an unintended duplicate.
    static func intervalTimes(first: MealTime, intervalHours: Int, count: Int) -> [MealTime] {
        guard count > 0 else { return [] }
        let firstTotalMinutes = first.hour * 60 + first.minute
        return (0..<count).map { i in
            let totalMinutes = (firstTotalMinutes + i * intervalHours * 60).mod(24 * 60)
            return MealTime(hour: totalMinutes / 60, minute: totalMinutes % 60)
        }
    }
}

private extension Int {
    /// True (non-negative) modulo, since Swift's `%` can return negative results
    /// for negative operands — not expected here given non-negative inputs, but
    /// keeps this function correct rather than relying on caller discipline.
    func mod(_ m: Int) -> Int {
        let r = self % m
        return r >= 0 ? r : r + m
    }
}
