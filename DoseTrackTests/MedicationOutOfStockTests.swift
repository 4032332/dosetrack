// DoseTrackTests/MedicationOutOfStockTests.swift
import XCTest
import CoreData
@testable import DoseTrack

final class MedicationOutOfStockTests: XCTestCase {

    var context: NSManagedObjectContext!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).viewContext
    }

    override func tearDownWithError() throws {
        context = nil
    }

    private func makeMedication(currentCount: Int, updatedAt: Date?, totalDosesPerDay: Int = 1) -> Medication {
        let med = Medication.create(in: context, name: "Test", dosage: "10mg")
        med.currentCount = Int32(currentCount)
        med.totalDosesPerDay = Int32(totalDosesPerDay)
        med.updatedAt = updatedAt
        return med
    }

    func test_zeroSupplyOverTwoDaysAgo_isOutOfStock() {
        let med = makeMedication(currentCount: 0, updatedAt: Date().addingTimeInterval(-2 * 86400))
        XCTAssertTrue(med.isOutOfStockOverADay)
    }

    func test_zeroSupplyJustNow_isNotYetOutOfStock() {
        let med = makeMedication(currentCount: 0, updatedAt: Date())
        XCTAssertFalse(med.isOutOfStockOverADay)
    }

    func test_zeroSupplyExactlyAtBoundary_isNotOutOfStock() {
        // Just under 24h — should not yet trigger.
        let med = makeMedication(currentCount: 0, updatedAt: Date().addingTimeInterval(-86300))
        XCTAssertFalse(med.isOutOfStockOverADay)
    }

    func test_nonZeroSupply_isNeverOutOfStock() {
        let med = makeMedication(currentCount: 5, updatedAt: Date().addingTimeInterval(-2 * 86400))
        XCTAssertFalse(med.isOutOfStockOverADay)
    }

    func test_asNeededMedication_neverFlags() {
        // totalDosesPerDay 0 (as-needed, not on a running-count schedule) should never nag.
        let med = makeMedication(currentCount: 0, updatedAt: Date().addingTimeInterval(-2 * 86400), totalDosesPerDay: 0)
        XCTAssertFalse(med.isOutOfStockOverADay)
    }

    func test_nilUpdatedAt_isNotOutOfStock() {
        let med = makeMedication(currentCount: 0, updatedAt: nil)
        XCTAssertFalse(med.isOutOfStockOverADay)
    }
}
