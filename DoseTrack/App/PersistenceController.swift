// DoseTrack/App/PersistenceController.swift
import CoreData

/// Central CoreData stack. A single `NSPersistentContainer` backs the app's local store;
/// cross-device/caregiver sync is handled separately by `SupabaseSyncManager`, not CloudKit.
final class PersistenceController: ObservableObject {

    static let shared = PersistenceController()

    // MARK: - Public

    private(set) var container: NSPersistentContainer

    var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    // MARK: - Init

    init(inMemory: Bool = false) {
        container = Self.makeContainer(inMemory: inMemory)
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    // MARK: - Save

    func save() {
        let context = container.viewContext
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            // Surface in debug; in production, log to analytics
            assertionFailure("CoreData save failed: \(error)")
        }
    }

    // MARK: - Per-patient caregiver stores

    /// One NSPersistentContainer + NSManagedObjectContext per overseen patient, keyed by the
    /// patient's `userId`. Caregiver data is synced into a store that is entirely separate
    /// from the caregiver's own store, so viewing a patient can never blend/leak into the
    /// caregiver's local data (or vice versa). Cached so repeated lookups for the same
    /// patient reuse the same context/container rather than re-opening the SQLite file.
    private var patientContainers: [UUID: NSPersistentContainer] = [:]

    /// Returns (creating and caching if necessary) the managed object context backing the
    /// separate local store for the given caregiver-overseen patient.
    ///
    /// This is a separate container from the main store created in `makeContainer` above — a
    /// patient store is always a plain `NSPersistentContainer` against its own SQLite file
    /// (`DoseTrack-caregiver-<userId>.sqlite`) in the app group container. It does not
    /// participate in CloudKit sync; patient data arrives via `SupabaseSyncManager.pullAll`.
    func context(forPatient userId: UUID) -> NSManagedObjectContext {
        if let existing = patientContainers[userId] {
            return existing.viewContext
        }

        let container = NSPersistentContainer(name: "DoseTrack", managedObjectModel: Self.sharedModel)

        let storeURL = Self.storeURL(filename: "DoseTrack-caregiver-\(userId.uuidString).sqlite")
        let description = NSPersistentStoreDescription(url: storeURL)
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]

        container.loadPersistentStores { _, error in
            if let error {
                fatalError("Caregiver patient store failed to load for \(userId): \(error)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        patientContainers[userId] = container
        return container.viewContext
    }

    /// Discards the cached container/context for a patient (e.g. caregiver relationship revoked).
    func discardPatientContext(for userId: UUID) {
        patientContainers.removeValue(forKey: userId)
    }

    // MARK: - Private factory

    /// Resolves the on-disk URL for a given store filename inside the shared app group
    /// container (falling back to the documents directory), matching the location scheme
    /// already used by the main store.
    private static func storeURL(filename: String) -> URL {
        let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Constants.AppGroup.identifier
        )
        return (groupURL ?? URL.documentsDirectory).appendingPathComponent(filename)
    }

    /// Loaded exactly once and reused by every `NSPersistentContainer` this class
    /// creates (the main store AND every per-patient caregiver store). Loading a
    /// fresh `NSManagedObjectModel(contentsOf:)` per container — as this file
    /// previously did in both `makeContainer` and `context(forPatient:)` — creates
    /// multiple distinct model instances that each describe the same entities,
    /// which is exactly what triggers Core Data's "Multiple NSEntityDescriptions
    /// claim the NSManagedObject subclass" runtime confusion and the resulting
    /// unrecognized-selector crashes (e.g. `-[DoseLog id]: unrecognized selector`)
    /// when an object created under one model instance is treated as the wrong
    /// runtime type by code expecting another. A single shared model instance,
    /// used by every container, is the fix — NSManagedObjectModel is safe to
    /// share across multiple NSPersistentContainers.
    private static let sharedModel: NSManagedObjectModel = {
        let modelURL = Bundle.main.url(forResource: "DoseTrack", withExtension: "momd")!
        return NSManagedObjectModel(contentsOf: modelURL)!
    }()

    private static func makeContainer(inMemory: Bool) -> NSPersistentContainer {
        let container = NSPersistentContainer(name: "DoseTrack", managedObjectModel: sharedModel)

        let storeURL: URL
        if inMemory {
            storeURL = URL(fileURLWithPath: "/dev/null")
        } else {
            storeURL = Self.storeURL(filename: "DoseTrack.sqlite")
        }

        let description = NSPersistentStoreDescription(url: storeURL)
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true

        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in
            if let error {
                // In production, handle gracefully (corrupt store recovery, migration failure)
                fatalError("CoreData store failed to load: \(error)")
            }
        }

        return container
    }
}

// MARK: - Preview helper

extension PersistenceController {
    static var preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext

        let med = Medication.create(in: context, name: "Metformin", dosage: "500mg")
        Schedule.create(in: context, medication: med, hour: 8, minute: 0)
        Schedule.create(in: context, medication: med, hour: 20, minute: 0)
        DoseLog.create(in: context, medication: med, scheduledAt: Date(), status: .taken)

        try? context.save()
        return controller
    }()
}
