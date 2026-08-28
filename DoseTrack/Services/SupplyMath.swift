// DoseTrack/Services/SupplyMath.swift
import Foundation

enum SupplyMath {
    /// Units consumed by a single dose = daily consumption ÷ how many times a day it's taken.
    /// Supports fractional (half-tablet) doses. Never below the smallest representable dose.
    static func quantityPerDose(totalDosesPerDay: Double, enabledScheduleCount: Int) -> Double {
        guard enabledScheduleCount > 0 else { return max(totalDosesPerDay, 0.5) }
        return max(totalDosesPerDay / Double(enabledScheduleCount), 0.5)
    }

    static func decrementedCount(current: Double, by amount: Double) -> Double {
        max(0, current - amount)
    }
}
