// DoseTrackTests/MedicationExtensionsTests.swift
import XCTest
import CoreData
@testable import DoseTrack

final class MedicationExtensionsTests: XCTestCase {

    var context: NSManagedObjectContext!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).viewContext
    }

    override func tearDownWithError() throws {
        context = nil
    }

    private func makeMedication(dosage: String, totalDosesPerDay: Int, scheduleCount: Int) -> Medication {
        let med = Medication.create(in: context, name: "Test", dosage: dosage)
        med.totalDosesPerDay = Int32(totalDosesPerDay)
        for _ in 0..<scheduleCount {
            let s = Schedule(context: context)
            s.id = UUID()
            s.isEnabled = true
            s.medication = med
        }
        return med
    }

    func testTotalDoseText_singleTabletPerDose_returnsUnchanged() {
        // 1 schedule/day, totalDosesPerDay 1 -> quantityPerDose 1 -> no multiplication.
        let med = makeMedication(dosage: "500mg", totalDosesPerDay: 1, scheduleCount: 1)
        XCTAssertEqual(med.totalDoseText, "500mg")
    }

    func testTotalDoseText_twoTabletsPerDose_multipliesStrength() {
        // Melatonin 2mg, 2 tablets once daily -> totalDosesPerDay 2, 1 schedule -> quantityPerDose 2.
        let med = makeMedication(dosage: "2mg", totalDosesPerDay: 2, scheduleCount: 1)
        XCTAssertEqual(med.totalDoseText, "4mg")
    }

    func testTotalDoseText_twoTabletsTwiceDaily_multipliesPerScheduleNotTotal() {
        // Restavit 10mg, 2 tablets, twice daily -> totalDosesPerDay 4, 2 schedules -> quantityPerDose 2.
        let med = makeMedication(dosage: "10mg", totalDosesPerDay: 4, scheduleCount: 2)
        XCTAssertEqual(med.totalDoseText, "20mg")
    }

    func testTotalDoseText_decimalStrength_formatsWithoutTrailingZero() {
        let med = makeMedication(dosage: "0.5mg", totalDosesPerDay: 2, scheduleCount: 1)
        XCTAssertEqual(med.totalDoseText, "1mg")
    }

    func testTotalDoseText_nonNumericDosage_returnsUnchanged() {
        let med = makeMedication(dosage: "as directed", totalDosesPerDay: 2, scheduleCount: 1)
        XCTAssertEqual(med.totalDoseText, "as directed")
    }

    func testTotalDoseText_contraceptiveWithZeroDosesPerDay_returnsUnchanged() {
        let med = makeMedication(dosage: "1dose", totalDosesPerDay: 0, scheduleCount: 1)
        XCTAssertEqual(med.totalDoseText, "1dose")
    }
}
