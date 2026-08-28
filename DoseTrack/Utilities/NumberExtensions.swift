// DoseTrack/Utilities/NumberExtensions.swift
import Foundation

extension Double {
    /// Compact display for quantities that support half-units (e.g. half-tablet dosing):
    /// whole numbers print without a decimal ("1", "30"), fractional values keep one decimal
    /// place ("1.5", "0.5").
    var trimmedQuantityString: String {
        truncatingRemainder(dividingBy: 1) == 0 ? String(Int(self)) : String(format: "%.1f", self)
    }
}
