// DoseTrack/ViewModels/MedicationsViewModel.swift
import CoreData
import Combine
import WidgetKit

@MainActor
final class MedicationsViewModel: ObservableObject {

    @Published var medications: [Medication] = []
    @Published var showingPaywall: Bool = false
    @Published var showingAddForm: Bool = false
    @Published var medicationToEdit: Medication?
    @Published var medicationToDelete: Medication?
    @Published var showingDeleteConfirm: Bool = false

    private let context: NSManagedObjectContext
    private let isProSubscriber: () -> Bool

    init(
        context: NSManagedObjectContext,
        isProSubscriber: @escaping () -> Bool = {
            UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.isProSubscriber)
        }
    ) {
        self.context = context
        self.isProSubscriber = isProSubscriber
        fetchMedications()
    }

    // MARK: - Public

    func fetchMedications() {
        let request = Medication.fetchRequest()
        request.predicate = NSPredicate(format: "isActive == YES")
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Medication.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \Medication.createdAt, ascending: true)
        ]
        medications = (try? context.fetch(request)) ?? []
    }

    /// Returns false and sets showingPaywall when the free-tier limit would be exceeded.
    @discardableResult
    func canAddMedication() -> Bool {
        if !isProSubscriber() && medications.count >= Constants.FreeTier.maxMedications {
            showingPaywall = true
            return false
        }
        return true
    }

    func requestAddMedication() {
        guard canAddMedication() else { return }
        showingAddForm = true
    }

    func requestEdit(_ medication: Medication) {
        medicationToEdit = medication
    }

    func requestDelete(_ medication: Medication) {
        medicationToDelete = medication
        showingDeleteConfirm = true
    }

    /// Soft-delete: sets isActive = false, preserving history.
    func confirmSoftDelete() {
        guard let med = medicationToDelete else { return }
        med.isActive = false
        try? context.save()
        WidgetCenter.shared.reloadAllTimelines()
        fetchMedications()
        medicationToDelete = nil
        showingDeleteConfirm = false
    }

    func cancelDelete() {
        medicationToDelete = nil
        showingDeleteConfirm = false
    }

    func moveItems(from source: IndexSet, to destination: Int) {
        var reordered = medications
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, med) in reordered.enumerated() {
            med.sortOrder = Int32(index)
        }
        try? context.save()
        medications = reordered
    }
}
