// DoseTrack/ViewModels/AddEditMedicationViewModel.swift
import CoreData
import SwiftUI
import WidgetKit

struct ScheduleDraft: Identifiable {
    var id = UUID()
    var hour: Int = 8
    var minute: Int = 0
    var frequency: String = "daily"
    var daysOfWeek: [Int] = []
    var isEnabled: Bool = true
    var intervalDays: Int = 1
    /// Set when this draft was generated from "Link to routine" (e.g. "Bedtime") — Today then
    /// shows the routine name instead of a clock time. Cleared whenever the user hand-edits the
    /// time directly, since it may no longer match the routine's own time.
    var routineLabel: String? = nil
}

@MainActor
final class AddEditMedicationViewModel: ObservableObject {

    // MARK: - Form state

    @Published var name: String = ""
    /// Whether this is a medication, vitamin or supplement. Changeable at any time from the picker
    /// at the top of the form — including on an existing item — so someone can reclassify a
    /// supplement as a vitamin later without re-entering everything. Because all three share this
    /// one form, switching carries every populated field across for free.
    @Published var kind: MedicationKind = .medication
    /// Whether this item can also be taken ad-hoc. Independent of `schedules`: an item can be
    /// scheduled, as-needed, or both.
    @Published var allowsAsNeeded: Bool = false
    /// Numeric part of the dose, e.g. "500"
    @Published var doseAmount: String = ""
    /// Strength unit, e.g. "mg"
    @Published var doseUnit: String = "mg"
    /// How many units per dose, e.g. 1 (supports halves, e.g. 0.5 for a half tablet)
    @Published var quantityAmount: Double = 1
    /// Form factor, e.g. "tablet"
    @Published var quantityUnit: String = "tablet"
    @Published var colorHex: String = "#5B8AF0"
    @Published var notes: String = ""
    @Published var currentCount: Double = 0
    @Published var refillThreshold: Int = 7
    @Published var schedules: [ScheduleDraft] = [ScheduleDraft()]
    @Published var photoData: Data? = nil
    @Published var escriptData: Data? = nil

    // MARK: - Contraceptive tracking
    @Published var isContraceptive: Bool = false
    @Published var selectedPreset: Constants.Contraceptive.Preset? = nil
    @Published var lastAdministeredDate: Date = Date()

    // MARK: - Validation
    @Published var nameError: String? = nil
    @Published var doseError: String? = nil

    /// Only the name is required. Strength is deliberately optional: it's often genuinely absent
    /// from the packaging (a scoop of protein powder, a multivitamin listing 19 ingredients and no
    /// single strength), and forcing a number there would push people into inventing one — worse
    /// than leaving it blank on a medical record.
    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Metadata
    let isEditing: Bool
    private let medication: Medication?
    private let context: NSManagedObjectContext

    // Dose strength units (what's in each unit)
    static let doseUnitOptions = ["mg", "ml", "IU", "mcg", "g", "µg", "%", "mmol", "mEq"]
    // Form factor (how it's taken). One shared list across medications, vitamins and supplements:
    // the powder/gummy/spoon forms below are typical of supplements but not exclusive to them (a
    // powdered laxative is a medication measured in scoops), and a single list means converting an
    // item between kinds can never leave it holding a unit its new picker doesn't offer.
    static let quantityUnitOptions = ["tablet", "capsule", "pill", "oral syringe", "injection", "inhaler", "spray", "patch", "drop", "sachet", "suppository", "lozenge", "scoop", "gummy", "teaspoon", "tablespoon"]
    // Shared with the Colour Coding preferences screen so a tag assigned there (e.g. "Morning
    // Batch") labels the same swatch here.
    static let colorOptions = Constants.MedicationColors.palette

    // MARK: - Init

    /// - Parameter initialKind: what the form opens as when adding something new (set by the type
    ///   chooser on the Medications tab). Ignored when editing, where the item's own stored kind
    ///   wins — otherwise opening an existing supplement would silently reset it to a medication.
    init(context: NSManagedObjectContext, medication: Medication? = nil, initialKind: MedicationKind = .medication) {
        self.context = context
        self.medication = medication
        self.isEditing = medication != nil
        self.kind = initialKind

        if let med = medication {
            name = med.wrappedName
            kind = med.medicationKind
            allowsAsNeeded = med.allowsAsNeeded
            colorHex = med.wrappedColorHex
            notes = med.wrappedNotes
            currentCount = med.currentCount
            refillThreshold = Int(med.refillThreshold)
            photoData = med.photoData
            escriptData = med.escriptData
            quantityUnit = med.wrappedUnit

            // Parse dosage string like "500mg" or "10ml" into amount + unit
            let (amount, unit) = Self.parseDosage(med.wrappedDosage)
            doseAmount = amount
            doseUnit = unit

            isContraceptive = med.wrappedUnit == "contraceptive"
            schedules = med.schedulesArray.map { s in
                ScheduleDraft(
                    id: s.id ?? UUID(),
                    hour: Int(s.hour),
                    minute: Int(s.minute),
                    frequency: s.wrappedFrequency,
                    daysOfWeek: s.daysOfWeekArray,
                    isEnabled: s.isEnabled,
                    intervalDays: Int(s.intervalDays),
                    routineLabel: s.wrappedRoutineLabel
                )
            }
            if schedules.isEmpty { schedules = [ScheduleDraft()] }

            // Per-dose quantity. Now read through `Medication.quantityPerDose`, which prefers the
            // stored value and only falls back to the old totalDosesPerDay ÷ scheduleCount
            // derivation for rows predating that attribute. The derivation alone used to reset this
            // stepper to 1 on every edit, and saving again then wrote totalDosesPerDay =
            // 1 × scheduleCount — silently dropping "2 tablets per dose" and corrupting the
            // supply/days-left maths. It also can't work for as-needed-only items, which have no
            // schedules to divide by.
            quantityAmount = med.quantityPerDose

            if isContraceptive, let lastLog = med.doseLogsArray.last {
                lastAdministeredDate = lastLog.loggedAt ?? Date()
            }
        }
    }

    // MARK: - Contraceptive preset

    func applyPreset(_ preset: Constants.Contraceptive.Preset) {
        selectedPreset = preset
        name = preset.name
        doseAmount = "1"
        doseUnit = "dose"
        quantityUnit = "injection"
        colorHex = preset.colorHex
        isContraceptive = true
        schedules = [ScheduleDraft(hour: 9, minute: 0, frequency: "custom", intervalDays: preset.intervalDays)]
    }

    // MARK: - Actions

    func addSchedule() { schedules.append(ScheduleDraft()) }

    func removeSchedule(at offsets: IndexSet) {
        schedules.remove(atOffsets: offsets)
        if schedules.isEmpty { schedules = [ScheduleDraft()] }
    }

    func validate() -> Bool {
        nameError = name.trimmingCharacters(in: .whitespaces).isEmpty ? "Name is required" : nil
        // No doseError: strength is optional (see `isValid`).
        doseError = nil
        return nameError == nil
    }

    @discardableResult
    func save() -> Medication? {
        guard validate() else { return nil }

        let med: Medication
        if let existing = medication {
            med = existing
        } else {
            med = Medication(context: context)
            med.id = UUID()
            med.createdAt = Date()
            med.isActive = true
        }

        med.name = name.trimmingCharacters(in: .whitespaces)
        // Build dosage string: "500mg". Strength is optional, and a blank amount must produce a
        // genuinely empty dosage — concatenating unconditionally would store a bare unit ("mg"),
        // which then renders as a nonsense strength everywhere the dose summary is shown.
        let trimmedAmount = doseAmount.trimmingCharacters(in: .whitespaces)
        med.dosage = trimmedAmount.isEmpty ? "" : "\(trimmedAmount)\(doseUnit)"
        med.kind = kind.rawValue
        med.allowsAsNeeded = allowsAsNeeded
        med.unit = isContraceptive ? "contraceptive" : quantityUnit
        med.colorHex = colorHex
        med.notes = notes.trimmingCharacters(in: .whitespaces)
        med.currentCount = currentCount
        med.refillThreshold = Int32(refillThreshold)
        med.photoData = photoData
        med.escriptData = escriptData
        // Daily consumption = quantity per dose × how many times a day the schedule fires —
        // schedule count alone undercounts whenever a dose is more than one unit (e.g. "2
        // tablets, twice daily" is 4/day, not 2).
        med.totalDosesPerDay = isContraceptive ? 0 : quantityAmount * Double(schedules.filter { $0.isEnabled }.count)
        // Stored independently of totalDosesPerDay so an as-needed-only item (zero schedules, and
        // therefore a totalDosesPerDay of 0) still knows how much one dose consumes.
        med.storedQuantityPerDose = isContraceptive ? 1 : max(quantityAmount, 0)
        med.updatedAt = Date()

        for old in med.schedulesArray { context.delete(old) }
        for draft in schedules {
            let s = Schedule(context: context)
            s.id = UUID()
            s.hour = Int16(draft.hour)
            s.minute = Int16(draft.minute)
            s.frequency = draft.frequency
            s.daysOfWeekArray = draft.daysOfWeek
            s.isEnabled = draft.isEnabled
            s.intervalDays = Int16(min(draft.intervalDays, Int(Int16.max)))
            s.routineLabel = draft.routineLabel
            s.medication = med
            s.updatedAt = Date()
        }

        if isContraceptive && !isEditing {
            let log = DoseLog(context: context)
            log.id = UUID()
            log.medication = med
            log.scheduledAt = lastAdministeredDate
            log.loggedAt = lastAdministeredDate
            log.status = "taken"
            log.updatedAt = Date()
        }

        context.saveOrReport()
        WidgetCenter.shared.reloadAllTimelines()
        // Keep the watch's copy current the moment a medication/schedule changes, not just when
        // a dose gets logged. Only for the signed-in user's own account — the watch always
        // mirrors `ownContext` (see RootView), never whichever patient a caregiver might
        // currently be viewing, so pushing here when editing a patient's medication would leak
        // that patient's data onto the caregiver's own watch.
        if ActiveAccountResolver.shared.activeUserId == nil {
            WatchConnectivityManager.shared.syncTodayMedications(context: context)
        }
        // Rebuild the notification queue immediately so any schedule/time change takes effect
        // now. Previously save() never touched notifications, so an edited dose time only
        // applied after the next app launch (when refreshAll runs on foreground) — meanwhile
        // the OLD time's already-scheduled reminders kept firing. This was the root cause of
        // reminders arriving at a stale time (e.g. 08:00) despite the schedule showing a new
        // one. refreshAll cancels all dt.* pending requests and rebuilds from current data.
        NotificationScheduler.shared.refreshAll(context: context)
        // Push to Supabase — photos uploaded separately if present
        let medCopy = med
        let pushUserId = ActiveAccountResolver.shared.activeUserId
        Task {
            await SupabaseSyncManager.shared.pushMedication(medCopy, forUserId: pushUserId)
            // Upload photos to storage if they exist
            if let photoData = medCopy.photoData, let medId = medCopy.id,
               let path = await SupabaseSyncManager.shared.uploadPhoto(
                   photoData, forMedicationId: medId, type: .bottle) {
                // Store path on row (fire-and-forget; not critical path)
                _ = path
            }
            if let escriptData = medCopy.escriptData, let medId = medCopy.id,
               let path = await SupabaseSyncManager.shared.uploadPhoto(
                   escriptData, forMedicationId: medId, type: .escript) {
                _ = path
            }
        }
        return med
    }

    // MARK: - Helpers

    /// Splits "500mg" → ("500", "mg"). Falls back gracefully.
    nonisolated static func parseDosage(_ dosage: String) -> (amount: String, unit: String) {
        let str = dosage.trimmingCharacters(in: .whitespaces)
        // Find first non-digit, non-dot character
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

    private func nextDueDescription(intervalDays: Int) -> String {
        switch intervalDays {
        case 1..<14:   return "Every \(intervalDays) days"
        case 14..<60:  return "Every \(intervalDays / 7) weeks"
        case 60..<365: return "Every ~\(intervalDays / 30) months"
        default:       return "Every \(intervalDays / 365) year\(intervalDays >= 730 ? "s" : "")"
        }
    }
}
