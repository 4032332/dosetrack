// DoseTrack/ViewModels/AddEditMedicationViewModel.swift
import CoreData
import SwiftUI

struct ScheduleDraft: Identifiable {
    var id = UUID()
    var hour: Int = 8
    var minute: Int = 0
    var frequency: String = "daily"
    var daysOfWeek: [Int] = []
    var isEnabled: Bool = true
    var intervalDays: Int = 1  // Used when frequency == "custom" (e.g. contraceptives)
}

@MainActor
final class AddEditMedicationViewModel: ObservableObject {

    // MARK: - Form state

    @Published var name: String = ""
    @Published var dosage: String = ""
    @Published var unit: String = "pill"
    @Published var colorHex: String = "#5B8AF0"
    @Published var notes: String = ""
    @Published var currentCount: Int = 0
    @Published var refillThreshold: Int = 7
    @Published var schedules: [ScheduleDraft] = [ScheduleDraft()]
    @Published var photoData: Data? = nil

    // MARK: - Contraceptive tracking

    @Published var isContraceptive: Bool = false
    @Published var selectedPreset: Constants.Contraceptive.Preset? = nil
    @Published var lastAdministeredDate: Date = Date()

    // MARK: - Validation

    @Published var nameError: String? = nil
    @Published var dosageError: String? = nil

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !dosage.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Metadata

    let isEditing: Bool
    private let medication: Medication?
    private let context: NSManagedObjectContext

    static let unitOptions = ["pill", "ml", "mg", "injection", "supplement", "drop", "spray", "contraceptive"]
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
            dosage = med.wrappedDosage
            unit = med.wrappedUnit
            colorHex = med.wrappedColorHex
            notes = med.wrappedNotes
            currentCount = Int(med.currentCount)
            refillThreshold = Int(med.refillThreshold)
            photoData = med.photoData
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

            // Restore last-administered date from most recent taken log
            if isContraceptive, let lastLog = med.doseLogsArray.last {
                lastAdministeredDate = lastLog.loggedAt ?? Date()
            }
        }
    }

    // MARK: - Contraceptive preset application

    func applyPreset(_ preset: Constants.Contraceptive.Preset) {
        selectedPreset = preset
        name = preset.name
        dosage = nextDueDescription(intervalDays: preset.intervalDays)
        unit = "contraceptive"
        colorHex = preset.colorHex
        isContraceptive = true
        schedules = [ScheduleDraft(
            hour: 9,
            minute: 0,
            frequency: "custom",
            intervalDays: preset.intervalDays
        )]
    }

    // MARK: - Actions

    func addSchedule() {
        schedules.append(ScheduleDraft())
    }

    func removeSchedule(at offsets: IndexSet) {
        schedules.remove(atOffsets: offsets)
        if schedules.isEmpty { schedules = [ScheduleDraft()] }
    }

    func validate() -> Bool {
        nameError = name.trimmingCharacters(in: .whitespaces).isEmpty ? "Name is required" : nil
        dosageError = dosage.trimmingCharacters(in: .whitespaces).isEmpty ? "Dosage is required" : nil
        return nameError == nil && dosageError == nil
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
        med.dosage = dosage.trimmingCharacters(in: .whitespaces)
        med.unit = unit
        med.colorHex = colorHex
        med.notes = notes.trimmingCharacters(in: .whitespaces)
        med.currentCount = Int32(currentCount)
        med.refillThreshold = Int32(refillThreshold)
        med.photoData = photoData
        med.totalDosesPerDay = Int32(isContraceptive ? 0 : schedules.filter { $0.isEnabled }.count)

        // Rebuild schedules — delete all existing, create fresh from drafts
        for old in med.schedulesArray {
            context.delete(old)
        }
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
        }

        // For contraceptives: record the last-administered date as a DoseLog
        // so the scheduler can compute next-due from real data.
        if isContraceptive && !isEditing {
            let log = DoseLog(context: context)
            log.id = UUID()
            log.medication = med
            log.scheduledAt = lastAdministeredDate
            log.loggedAt = lastAdministeredDate
            log.status = "taken"
        }

        try? context.save()
        return med
    }

    // MARK: - Helpers

    /// Human-readable string describing how often this contraceptive is administered.
    private func nextDueDescription(intervalDays: Int) -> String {
        switch intervalDays {
        case 1..<14:   return "Every \(intervalDays) days"
        case 14..<60:  return "Every \(intervalDays / 7) weeks"
        case 60..<365: return "Every \(intervalDays / 30) months"
        default:       return "Every \(intervalDays / 365) year\(intervalDays >= 730 ? "s" : "")"
        }
    }
}
