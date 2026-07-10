// DoseTrack/ViewModels/MedicationsViewModel.swift
import CoreData
import Combine
import WidgetKit

/// User-selectable ordering for the medications list.
enum MedicationSort: String, CaseIterable, Identifiable {
    case manual, name, timeDue, dateAdded
    var id: String { rawValue }
    var label: String {
        switch self {
        case .manual:    return "Custom order"
        case .name:      return "Alphabetical"
        case .timeDue:   return "Time due"
        case .dateAdded: return "Date added"
        }
    }
    var systemImage: String {
        switch self {
        case .manual:    return "hand.draw"
        case .name:      return "textformat.abc"
        case .timeDue:   return "clock"
        case .dateAdded: return "calendar.badge.plus"
        }
    }

    /// Earliest enabled-schedule time of day, in minutes since midnight; large sentinel when a
    /// medication has no enabled schedule so it sorts to the end under "Time due".
    private static func earliestMinutes(_ med: Medication) -> Int {
        med.schedulesArray
            .filter { $0.isEnabled }
            .map { Int($0.hour) * 60 + Int($0.minute) }
            .min() ?? Int.max
    }

    func apply(_ meds: [Medication]) -> [Medication] {
        switch self {
        case .manual:
            return meds.sorted {
                if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                return ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast)
            }
        case .name:
            return meds.sorted { $0.wrappedName.localizedCaseInsensitiveCompare($1.wrappedName) == .orderedAscending }
        case .timeDue:
            return meds.sorted { Self.earliestMinutes($0) < Self.earliestMinutes($1) }
        case .dateAdded:
            return meds.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        }
    }
}

@MainActor
final class MedicationsViewModel: ObservableObject {

    @Published var medications: [Medication] = []
    @Published var showingPaywall: Bool = false
    @Published var showingAddForm: Bool = false
    @Published var medicationToEdit: Medication?
    /// Persisted list ordering. Reordering by hand is only meaningful under `.manual`.
    @Published var sortMode: MedicationSort {
        didSet {
            UserDefaults.standard.set(sortMode.rawValue, forKey: "medicationSortMode")
            fetchMedications()
        }
    }

    private var context: NSManagedObjectContext
    private let isProSubscriber: () -> Bool
    /// Test-only override. When nil, `hasActiveCaregiver()` reads the live `CaregiverManager`.
    /// Kept optional (rather than a MainActor-touching default closure) because default
    /// argument expressions are evaluated in a nonisolated context and can't reference
    /// `@MainActor CaregiverManager.shared`.
    private let hasActiveCaregiverOverride: (() -> Bool)?

    init(
        context: NSManagedObjectContext,
        isProSubscriber: @escaping () -> Bool = {
            UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.isProSubscriber)
        },
        hasActiveCaregiver: (() -> Bool)? = nil
    ) {
        self.context = context
        self.isProSubscriber = isProSubscriber
        self.hasActiveCaregiverOverride = hasActiveCaregiver
        self.sortMode = MedicationSort(rawValue: UserDefaults.standard.string(forKey: "medicationSortMode") ?? "") ?? .manual
        fetchMedications()
    }

    /// Whether the signed-in user is a patient with an active caregiver. Because accepting a
    /// caregiver invite is itself Pro-gated, an active caregiver relationship implies a paying
    /// caregiver — so the patient is covered by that plan and should never hit the free-tier
    /// wall. (Subscription status isn't stored server-side, so an active relationship is the
    /// best proxy the patient's own device has for "my caregiver is Pro.")
    private func hasActiveCaregiver() -> Bool {
        if let hasActiveCaregiverOverride { return hasActiveCaregiverOverride() }
        return CaregiverManager.shared.ownPatientRelationship?.isActive == true
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
        let fetched = (try? context.fetch(request)) ?? []
        medications = sortMode.apply(fetched)
    }

    /// Returns false and sets showingPaywall when the free-tier limit would be exceeded.
    @discardableResult
    func canAddMedication() -> Bool {
        // A caregiver viewing an overseen patient: only a Pro subscriber can reach this state
        // (accepting an invite is Pro-gated), and doing the med management for the patient is
        // the whole point of caregiver mode — allow unlimited adds to the patient's account.
        // (`medications` here is the patient's list, written into the patient's separate store
        // and pushed with the patient's userId; see AddEditMedicationViewModel.save.)
        if ActiveAccountResolver.shared.activeUserId != nil { return true }

        // Own account. Unlimited if this user is Pro themselves, OR is a patient with an active
        // caregiver — a covered patient must never be blocked from adding their own medications.
        if isProSubscriber() || hasActiveCaregiver() { return true }

        if medications.count >= Constants.FreeTier.maxMedications {
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
        // Own account only — see the matching comment in AddEditMedicationViewModel.save().
        if pushUserId == nil {
            WatchConnectivityManager.shared.syncTodayMedications(context: context)
        }
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
        // Dragging to reorder expresses a custom order — switch to (and persist) manual sort so
        // the arrangement sticks rather than being immediately re-sorted away.
        if sortMode != .manual { sortMode = .manual }
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
