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

    static let unitOptions = ["pill", "ml", "mg", "injection", "supplement", "drop", "spray"]
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
            schedules = med.schedulesArray.map { s in
                ScheduleDraft(
                    id: s.id ?? UUID(),
                    hour: Int(s.hour),
                    minute: Int(s.minute),
                    frequency: s.wrappedFrequency,
                    daysOfWeek: s.daysOfWeekArray,
                    isEnabled: s.isEnabled
                )
            }
            if schedules.isEmpty { schedules = [ScheduleDraft()] }
        }
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
        med.totalDosesPerDay = Int32(schedules.filter { $0.isEnabled }.count)

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
            s.intervalDays = 1
            s.medication = med
        }

        try? context.save()
        return med
    }
}
