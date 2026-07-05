// DoseTrackTests/SyncMergeTests.swift
import XCTest
import CoreData
@testable import DoseTrack

@MainActor
final class SyncMergeTests: XCTestCase {
    func test_merge_doesNotResurrectLocallyDeactivatedMedication() {
        let ctx = PersistenceController(inMemory: true).viewContext
        let id = UUID()
        let med = Medication(context: ctx)
        med.id = id; med.name = "Old"; med.dosage = "1"; med.unit = "pill"
        med.colorHex = "#000000"; med.isActive = false   // locally soft-deleted
        try? ctx.save()

        // Remote row still says active (row predates the delete reaching the server).
        let row = MedicationRow.testRow(id: id.uuidString, isActive: true)
        SupabaseSyncManager.shared.mergeMedicationsForTesting([row], context: ctx)

        let fetched = (try? ctx.fetch(Medication.fetchRequest()))?.first
        XCTAssertEqual(fetched?.isActive, false, "a locally-deactivated med must not be resurrected by a stale remote row")
    }
}
