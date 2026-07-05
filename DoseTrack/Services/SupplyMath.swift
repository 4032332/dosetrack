// DoseTrack/Services/SupplyMath.swift
import Foundation

enum SupplyMath {
    /// Units consumed by a single dose = daily consumption ÷ how many times a day it's taken.
    /// Never below 1 (a dose always consumes at least one unit).
    static func quantityPerDose(totalDosesPerDay: Int, enabledScheduleCount: Int) -> Int {
        guard enabledScheduleCount > 0 else { return max(totalDosesPerDay, 1) }
        return max(totalDosesPerDay / enabledScheduleCount, 1)
    }

    static func decrementedCount(current: Int, by amount: Int) -> Int {
        max(0, current - amount)
    }
}
