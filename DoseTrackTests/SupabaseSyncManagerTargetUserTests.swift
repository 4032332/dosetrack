import XCTest
@testable import DoseTrack

final class SupabaseSyncManagerTargetUserTests: XCTestCase {
    func test_medicationRow_tagsExplicitTargetUserId_notSessionUser() {
        let context = PersistenceController(inMemory: true).container.viewContext
        let med = Medication(context: context)
        med.id = UUID()
        med.name = "Metformin"

        let targetUserId = UUID() // deliberately NOT AuthManager.shared.session?.user.id
        let row = MedicationRow(medication: med, userId: targetUserId)

        XCTAssertEqual(row.userId, targetUserId.uuidString)
    }

    func test_doseLogRow_tagsExplicitTargetUserId_notSessionUser() {
        let context = PersistenceController(inMemory: true).container.viewContext
        let log = DoseLog(context: context)
        log.id = UUID()
        log.status = "taken"

        let targetUserId = UUID()
        let row = DoseLogRow(log: log, userId: targetUserId)

        XCTAssertEqual(row.userId, targetUserId.uuidString)
    }
}
