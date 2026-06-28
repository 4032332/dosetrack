// DoseTrack/App/PersistenceController.swift
import CoreData
import CloudKit

/// Central CoreData stack. Uses NSPersistentCloudKitContainer for Pro subscribers,
/// NSPersistentContainer for free tier. Call `reconfigure(isPro:)` when subscription
/// status changes — this tears down and rebuilds the stack.
final class PersistenceController: ObservableObject {

    static let shared = PersistenceController()

    // MARK: - Public

    private(set) var container: NSPersistentContainer

    var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    // MARK: - Init

    init(inMemory: Bool = false) {
        let isPro = UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.isProSubscriber)
        container = Self.makeContainer(isPro: isPro, inMemory: inMemory)
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    // MARK: - Container switching

    /// Call after subscription status changes. Saves any pending changes first.
    func reconfigure(isPro: Bool) {
        try? container.viewContext.save()
        container = Self.makeContainer(isPro: isPro, inMemory: false)
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

    // MARK: - Private factory

    private static func makeContainer(isPro: Bool, inMemory: Bool) -> NSPersistentContainer {
        let modelURL = Bundle.main.url(forResource: "DoseTrack", withExtension: "momd")!
        let model = NSManagedObjectModel(contentsOf: modelURL)!

        let container: NSPersistentContainer
        if isPro {
            container = NSPersistentCloudKitContainer(name: "DoseTrack", managedObjectModel: model)
        } else {
            container = NSPersistentContainer(name: "DoseTrack", managedObjectModel: model)
        }

        let storeURL: URL
        if inMemory {
            storeURL = URL(fileURLWithPath: "/dev/null")
        } else {
            let groupURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: Constants.AppGroup.identifier
            )
            storeURL = (groupURL ?? URL.documentsDirectory)
                .appendingPathComponent("DoseTrack.sqlite")
        }

        let description = NSPersistentStoreDescription(url: storeURL)
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true

        if isPro {
            description.cloudKitContainerOptions =
                NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.com.robbrown.dosetrack")
        }

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
