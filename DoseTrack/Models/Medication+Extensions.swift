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

    /// SF Symbol used to represent this medication's form, in the tinted tile shown on both the
    /// Medications and Restock lists (kept here as the single source of truth so those two
    /// screens can't drift apart on iconography).
    var unitIconName: String {
        switch wrappedUnit {
        case "injection", "contraceptive": return "syringe.fill"
        case "ml":         return "drop.fill"
        case "spray":      return "aqi.medium"
        case "inhaler":    return "wind"
        case "supplement": return "leaf.fill"
        default:           return "pill.fill"
        }
    }

    /// Canonical "needs restock soon" signal — the single source of truth used everywhere a
    /// low-supply warning is shown (Medications list icon, Today's alerts box, Restock urgency
    /// colouring). Previously each of those three places had its OWN slightly different
    /// definition (one keyed off `currentCount <= refillThreshold`, another off `daysOfSupply <
    /// 7` with a hardcoded "7" instead of the user's threshold, a third off raw count bands) —
    /// so a medication could show a warning in one place and not another (e.g. Restavit at 0
    /// supply missing from Today's alerts; Clonidine with 8 tablets but only 2 days left,
    /// because it's taken more than once a day, missing from the Medications list icon).
    /// Warn when either the raw count is at/below the user's threshold, OR days-of-supply is
    /// under a week — matching the two urgency signals already described in the Refill Tracking
    /// footer ("<3 doses, <5 days, and <7 days remaining"). Gated on the med actually being
    /// consumed on a schedule (totalDosesPerDay > 0) so as-needed items that don't track a
    /// running count don't nag.
    var isRefillWarning: Bool {
        guard totalDosesPerDay > 0 else { return false }
        return currentCount <= refillThreshold || daysOfSupply < 7
    }

    /// True once supply has been sitting at exactly 0 for more than a full day — the trigger for
    /// the Medications tab's "remove it or update your supply?" nudge. `updatedAt` is used as the
    /// "since when" marker: `DoseLoggingService` only touches it as part of decrementing supply
    /// (and stops touching it once supply reaches 0, since the decrement is guarded on
    /// `currentCount > 0`), so for a medication that's been sitting at 0 it reflects the moment
    /// it ran out. The one inexactness: editing an unrelated field (name, colour) while at 0
    /// supply also bumps `updatedAt` and delays the nudge by another day — an acceptable
    /// approximation rather than adding a dedicated "ran out at" timestamp for this alone.
    var isOutOfStockOverADay: Bool {
        guard totalDosesPerDay > 0, currentCount == 0 else { return false }
        guard let updatedAt else { return false }
        return updatedAt.timeIntervalSinceNow < -86400
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
