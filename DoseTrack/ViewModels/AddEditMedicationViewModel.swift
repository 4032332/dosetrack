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
}

@MainActor
final class AddEditMedicationViewModel: ObservableObject {

    // MARK: - Form state

    @Published var name: String = ""
    /// Numeric part of the dose, e.g. "500"
    @Published var doseAmount: String = ""
    /// Strength unit, e.g. "mg"
    @Published var doseUnit: String = "mg"
    /// How many units per dose, e.g. 1
    @Published var quantityAmount: Int = 1
    /// Form factor, e.g. "tablet"
    @Published var quantityUnit: String = "tablet"
    @Published var colorHex: String = "#5B8AF0"
    @Published var notes: String = ""
    @Published var currentCount: Int = 0
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

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !doseAmount.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Metadata
    let isEditing: Bool
    private let medication: Medication?
    private let context: NSManagedObjectContext

    // Dose strength units (what's in each unit)
    static let doseUnitOptions = ["mg", "ml", "IU", "mcg", "g", "µg", "%", "mmol", "mEq"]
    // Form factor (how it's taken)
    static let quantityUnitOptions = ["tablet", "capsule", "pill", "oral syringe", "injection", "spray", "patch", "drop", "sachet", "suppository", "lozenge"]
    static let colorOptions = [
        "#5B8AF0", "#FF6B6B", "#4ECDC4", "#45B7D1",
        "#96CEB4", "#FFEAA7", "#DDA0DD", "#98D8C8"
    ]

    // MARK: - Init

    init(context: NSManagedObjectContext, medication: Medication? = nil) {
        self.context = context
        self.medication = medication
        self.isEditing = medication != nil

        if let med = medication {
            name = med.wrappedName
            colorHex = med.wrappedColorHex
            notes = med.wrappedNotes
            currentCount = Int(med.currentCount)
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
                    intervalDays: Int(s.intervalDays)
                )
            }
            if schedules.isEmpty { schedules = [ScheduleDraft()] }

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
        doseError = doseAmount.trimmingCharacters(in: .whitespaces).isEmpty ? "Dose amount is required" : nil
        return nameError == nil && doseError == nil
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
        // Build dosage string: "500mg"
        med.dosage = "\(doseAmount.trimmingCharacters(in: .whitespaces))\(doseUnit)"
        med.unit = isContraceptive ? "contraceptive" : quantityUnit
        med.colorHex = colorHex
        med.notes = notes.trimmingCharacters(in: .whitespaces)
        med.currentCount = Int32(currentCount)
        med.refillThreshold = Int32(refillThreshold)
        med.photoData = photoData
        med.escriptData = escriptData
        // Daily consumption = quantity per dose × how many times a day the schedule fires —
        // schedule count alone undercounts whenever a dose is more than one unit (e.g. "2
        // tablets, twice daily" is 4/day, not 2).
        med.totalDosesPerDay = Int32(isContraceptive ? 0 : quantityAmount * schedules.filter { $0.isEnabled }.count)
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
    static func parseDosage(_ dosage: String) -> (amount: String, unit: String) {
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
