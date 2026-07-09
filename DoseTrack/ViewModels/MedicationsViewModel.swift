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

    private var context: NSManagedObjectContext
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

    /// Swaps the underlying store this view model reads/writes against (e.g. when a caregiver
    /// switches between their own account and an overseen patient's separate local store) and
    /// refetches immediately so the UI reflects the new store's data.
    func updateContext(_ newContext: NSManagedObjectContext) {
        guard newContext !== context else { return }
        context = newContext
        fetchMedications()
    }

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
        // A caregiver viewing an overseen patient shouldn't create medications in the
        // patient's account from this UI — and without this guard, `medications.count` here
        // would be the patient's count, not the signed-in user's own, making the free-tier
        // check meaningless for whichever account happens to be active.
        guard ActiveAccountResolver.shared.activeUserId == nil else { return false }
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

    /// Soft-deletes immediately: sets isActive = false, preserving history. No extra
    /// confirmation dialog — reaching this action already requires either swiping on a row
    /// and tapping the destructive "Delete" action, or entering Edit mode and tapping the red
    /// minus button, both of which are themselves a deliberate two-step gesture. An additional
    /// "Are you sure?" dialog on top of that was judged clunky rather than protective.
    func requestDelete(_ medication: Medication) {
        medication.isActive = false
        medication.updatedAt = Date()
        context.saveOrReport()
        WidgetCenter.shared.reloadAllTimelines()
        // Push the tombstone, or a stale remote row keeps this medication looking active on
        // the next pull.
        let pushUserId = ActiveAccountResolver.shared.activeUserId
        Task { await SupabaseSyncManager.shared.pushMedication(medication, forUserId: pushUserId) }
        fetchMedications()
    }

    func moveItems(from source: IndexSet, to destination: Int) {
        var reordered = medications
        reordered.move(fromOffsets: source, toOffset: destination)
        let now = Date()
        for (index, med) in reordered.enumerated() {
            med.sortOrder = Int32(index)
            med.updatedAt = now
        }
        context.saveOrReport()
        medications = reordered
        // Without pushing, the new order saves locally but silently resets on the next pull
        // (remote rows still carry the old sortOrder). Stamp updatedAt + push each row.
        let pushUserId = ActiveAccountResolver.shared.activeUserId
        let toPush = reordered
        Task {
            for med in toPush {
                await SupabaseSyncManager.shared.pushMedication(med, forUserId: pushUserId)
            }
        }
    }
}
