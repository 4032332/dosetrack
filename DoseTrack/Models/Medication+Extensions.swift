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

    /// The strength actually taken in one dose, e.g. "4mg" for a medication whose `dosage` is
    /// the per-tablet strength "2mg" but where 2 tablets are taken per dose. `dosage` only ever
    /// stores the per-unit strength (see AddEditMedicationViewModel.save) — how many units make
    /// up one dose is derived from `totalDosesPerDay ÷ enabled schedule count`, the same maths
    /// SupplyMath already uses for refill tracking. Notifications previously showed the raw
    /// per-unit `dosage` regardless of quantity, so "2 tablets of Melatonin 2mg" read as "Time
    /// to take 2mg" instead of the correct 4mg actually taken.
    var totalDoseText: String {
        let (amountString, unit) = Self.parseDosage(wrappedDosage)
        guard let perUnitAmount = Double(amountString) else { return wrappedDosage }

        let enabledScheduleCount = schedulesArray.filter { $0.isEnabled }.count
        let quantityPerDose = SupplyMath.quantityPerDose(
            totalDosesPerDay: Int(totalDosesPerDay),
            enabledScheduleCount: enabledScheduleCount
        )
        guard quantityPerDose > 1 else { return wrappedDosage }

        let total = perUnitAmount * Double(quantityPerDose)
        let totalString = total.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", total)
            : String(total)
        return "\(totalString)\(unit)"
    }

    /// Splits a dosage string like "500mg" into its numeric amount and unit. Mirrors
    /// AddEditMedicationViewModel.parseDosage (which builds the form fields from this same
    /// string) — kept here too since that one is private to the view model.
    private static func parseDosage(_ dosage: String) -> (amount: String, unit: String) {
        let str = dosage.trimmingCharacters(in: .whitespaces)
        var idx = str.startIndex
        while idx < str.endIndex {
            let ch = str[idx]
            if !ch.isNumber && ch != "." { break }
            idx = str.index(after: idx)
        }
        let amount = String(str[str.startIndex..<idx])
        let unit = String(str[idx...]).trimmingCharacters(in: .whitespaces)
        if amount.isEmpty { return (str, "mg") }
        return (amount, unit.isEmpty ? "mg" : unit)
    }
}
