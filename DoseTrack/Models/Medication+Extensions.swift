// DoseTrack/Models/Medication+Extensions.swift
import CoreData
import SwiftUI

extension Medication {

    // MARK: - Factory

    @discardableResult
    static func create(
        in context: NSManagedObjectContext,
        name: String,
        dosage: String,
        unit: String = "pill",
        colorHex: String = "#5B8AF0"
    ) -> Medication {
        let med = Medication(context: context)
        med.id = UUID()
        med.name = name
        med.dosage = dosage
        med.unit = unit
        med.colorHex = colorHex
        med.isActive = true
        med.currentCount = 0
        med.refillThreshold = 7
        med.totalDosesPerDay = 1
        med.sortOrder = 0
        med.createdAt = Date()
        return med
    }

    // MARK: - Computed

    var color: Color {
        Color(hex: colorHex ?? "#5B8AF0")
    }

    var isRefillWarning: Bool {
        // Warn at or below the refill threshold, INCLUDING 0 (out of stock). The previous
        // `currentCount > 0` guard suppressed the warning at exactly 0 — the single most
        // urgent state — so a depleted medication showed no flag at all. Gated on the med
        // actually being consumed on a schedule (totalDosesPerDay > 0) so as-needed items
        // that don't track a running count don't nag.
        totalDosesPerDay > 0 && currentCount <= refillThreshold
    }

    var wrappedName: String { name ?? "" }
    var wrappedDosage: String { dosage ?? "" }
    var wrappedUnit: String { unit ?? "pill" }
    var wrappedColorHex: String { colorHex ?? "#5B8AF0" }
    var wrappedNotes: String { notes ?? "" }

    /// Estimated days of supply remaining based on current count and doses per day.
    var daysOfSupply: Int {
        let dpd = max(Int(totalDosesPerDay), 1)
        return Int(currentCount) / dpd
    }

    /// Restock urgency colour.
    var restockColor: Color {
        if currentCount < 3 { return .red }
        if daysOfSupply < 5  { return .orange }
        if daysOfSupply < 7  { return .yellow }
        return .green
    }

    var schedulesArray: [Schedule] {
        (schedules as? Set<Schedule>)?.sorted { $0.hour < $1.hour } ?? []
    }

    var doseLogsArray: [DoseLog] {
        (doseLogs as? Set<DoseLog>)?.sorted {
            ($0.scheduledAt ?? .distantPast) < ($1.scheduledAt ?? .distantPast)
        } ?? []
    }
}
