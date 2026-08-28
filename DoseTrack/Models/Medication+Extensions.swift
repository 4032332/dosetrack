// DoseTrack/Models/Medication+Extensions.swift
import CoreData
import SwiftUI

/// What sort of thing a tracked item is. Everything in the app is stored as a `Medication` row
/// regardless — the distinction is presentational (grouping on the Medications tab) plus one
/// substantive rule: only `.medication` counts toward the headline adherence score. Missing a
/// multivitamin is not the same kind of event as missing a prescription, and conflating them
/// would make the adherence number useless to show a doctor.
enum MedicationKind: String, CaseIterable, Identifiable {
    case medication
    case vitamin
    case supplement

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .medication: return "Medication"
        case .vitamin:    return "Vitamin"
        case .supplement: return "Supplement"
        }
    }

    /// Plural section header used for the collapsible groups on the Medications tab.
    var pluralName: String {
        switch self {
        case .medication: return "Medications"
        case .vitamin:    return "Vitamins"
        case .supplement: return "Supplements"
        }
    }

    var iconName: String {
        switch self {
        case .medication: return "pill.fill"
        case .vitamin:    return "sun.max.fill"
        case .supplement: return "leaf.fill"
        }
    }

    /// Whether missing a dose of this counts against the adherence percentage.
    var affectsAdherence: Bool { self == .medication }
}

extension Medication {

    // MARK: - Factory

    @discardableResult
    static func create(
        in context: NSManagedObjectContext,
        name: String,
        dosage: String,
        unit: String = "pill",
        colorHex: String = "#5B8AF0",
        kind: MedicationKind = .medication
    ) -> Medication {
        let med = Medication(context: context)
        med.id = UUID()
        med.name = name
        med.dosage = dosage
        med.unit = unit
        med.colorHex = colorHex
        med.kind = kind.rawValue
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

    /// Falls back to `.medication` for any row written before `kind` existed, or if the stored
    /// string is ever unrecognised — the conservative default, since treating an unknown item as a
    /// medication keeps it in the adherence score rather than silently dropping it out.
    var medicationKind: MedicationKind {
        MedicationKind(rawValue: kind ?? MedicationKind.medication.rawValue) ?? .medication
    }

    /// An item the user only ever takes ad-hoc: flagged as-needed with no enabled schedule. These
    /// show *only* in Today's "As Needed" section, never in the timed lists.
    var isAsNeededOnly: Bool {
        allowsAsNeeded && schedulesArray.allSatisfy { !$0.isEnabled }
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
        return currentCount <= Double(refillThreshold) || daysOfSupply < 7
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
        let dpd = max(totalDosesPerDay, 1)
        return Int(currentCount / dpd)
    }

    /// Restock urgency colour.
    var restockColor: Color {
        if currentCount < 3 { return .red }
        if daysOfSupply < 5  { return .orange }
        if daysOfSupply < 7  { return .yellow }
        return .green
    }

    /// Units taken per dose (e.g. 2 for two tablets at a time, 0.5 for a half).
    ///
    /// Prefers the stored `storedQuantityPerDose`, falling back to the legacy derivation
    /// (totalDosesPerDay ÷ enabled schedule count) for rows saved before that attribute existed.
    /// The stored value is what makes as-needed items work at all: with no schedules,
    /// `totalDosesPerDay` is 0 and the derivation collapses to a flat 0.5 for everything.
    var quantityPerDose: Double {
        if storedQuantityPerDose > 0 { return storedQuantityPerDose }
        let enabledCount = schedulesArray.filter { $0.isEnabled }.count
        return SupplyMath.quantityPerDose(totalDosesPerDay: totalDosesPerDay, enabledScheduleCount: enabledCount)
    }

    /// What the patient actually takes for one dose — e.g. "2 tablets · 1000mg" for two 500mg
    /// tablets, or just "500mg" when a single unit is taken (skips "1 tablet ·" clutter for the
    /// common case). This is what Today, the Medications list, Restock, and the dose-confirmation
    /// sheet show — `wrappedDosage` alone is only the per-unit strength printed on the bottle
    /// ("500mg") and understates the real dose whenever more than one unit — or a fractional/half
    /// tablet — is taken.
    var doseSummary: String {
        let perDose = quantityPerDose
        guard abs(perDose - 1) > 0.001 else { return wrappedDosage }
        let (amountStr, strengthUnit) = AddEditMedicationViewModel.parseDosage(wrappedDosage)
        guard let amount = Double(amountStr) else { return wrappedDosage }
        let total = amount * perDose
        let unitPlural = wrappedUnit + (perDose > 1 ? "s" : "")
        return "\(perDose.trimmedQuantityString) \(unitPlural) · \(total.trimmedQuantityString)\(strengthUnit)"
    }

    /// `doseSummary`, but for list rows that previously read "<dosage> · <form>" (e.g. "20mg ·
    /// pill") — keeps that familiar form-factor suffix for the common one-unit case, since
    /// `doseSummary` alone drops it there to stay uncluttered.
    var doseSummaryWithForm: String {
        abs(quantityPerDose - 1) > 0.001 ? doseSummary : "\(wrappedDosage) · \(wrappedUnit)"
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
