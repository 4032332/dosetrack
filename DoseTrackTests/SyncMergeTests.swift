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
        med.updatedAt = Date()
        try? ctx.save()

        // Remote row still says active (row predates the delete reaching the server).
        let row = MedicationRow.testRow(id: id.uuidString, isActive: true, updatedAt: Date().addingTimeInterval(-3600))
        SupabaseSyncManager.shared.mergeMedicationsForTesting([row], context: ctx)

        let fetched = (try? ctx.fetch(Medication.fetchRequest()))?.first
        XCTAssertEqual(fetched?.isActive, false, "a locally-deactivated med must not be resurrected by a stale remote row")
    }

    func test_merge_keepsLocalWhenLocalIsNewer() {
        let ctx = PersistenceController(inMemory: true).viewContext
        let id = UUID()
        let med = Medication(context: ctx)
        med.id = id; med.name = "LocalNew"; med.dosage = "1"; med.unit = "pill"; med.colorHex = "#000"
        med.isActive = true; med.updatedAt = Date()            // now
        try? ctx.save()
        let staleRow = MedicationRow.testRow(id: id.uuidString, isActive: true,
                                             name: "RemoteOld", updatedAt: Date().addingTimeInterval(-3600))
        SupabaseSyncManager.shared.mergeMedicationsForTesting([staleRow], context: ctx)
        XCTAssertEqual((try? ctx.fetch(Medication.fetchRequest()))?.first?.name, "LocalNew")
    }

    func test_merge_appliesRemoteWhenRemoteIsNewer() {
        let ctx = PersistenceController(inMemory: true).viewContext
        let id = UUID()
        let med = Medication(context: ctx)
        med.id = id; med.name = "LocalOld"; med.dosage = "1"; med.unit = "pill"; med.colorHex = "#000"
        med.isActive = true; med.updatedAt = Date().addingTimeInterval(-3600)
        try? ctx.save()
        let freshRow = MedicationRow.testRow(id: id.uuidString, isActive: true, name: "RemoteNew", updatedAt: Date())
        SupabaseSyncManager.shared.mergeMedicationsForTesting([freshRow], context: ctx)
        XCTAssertEqual((try? ctx.fetch(Medication.fetchRequest()))?.first?.name, "RemoteNew")
    }
}
