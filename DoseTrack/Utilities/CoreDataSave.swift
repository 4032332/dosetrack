// DoseTrack/Utilities/CoreDataSave.swift
import CoreData
import os

private let log = Logger(subsystem: "com.robbrown.dosetrack", category: "coredata")

extension NSManagedObjectContext {
    /// Save, or log+assert on failure. Replaces scattered `try? save()` that silently drop
    /// medical-data write errors.
    func saveOrReport(_ label: String = #function) {
        guard hasChanges else { return }
        do { try save() }
        catch { log.error("CoreData save failed [\(label)]: \(error.localizedDescription)"); assertionFailure("save failed: \(error)") }
    }
}
