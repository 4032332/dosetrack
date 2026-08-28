// DoseTrackTests/DoseSummaryTests.swift
import XCTest
import CoreData
@testable import DoseTrack

final class DoseSummaryTests: XCTestCase {

    var context: NSManagedObjectContext!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).viewContext
    }
    override func tearDownWithError() throws { context = nil }

    private func makeMedication(dosage: String, unit: String = "tablet", totalDosesPerDay: Double, enabledSchedules: Int) -> Medication {
        let med = Medication.create(in: context, name: "Test", dosage: dosage, unit: unit)
        med.totalDosesPerDay = totalDosesPerDay
        for _ in 0..<enabledSchedules {
            Schedule.create(in: context, medication: med, hour: 8, minute: 0)
        }
        return med
    }

    func test_doseSummary_singleUnit_showsJustStrength() {
        // 500mg, 1 tablet once daily => just "500mg", no clutter
        let med = makeMedication(dosage: "500mg", totalDosesPerDay: 1, enabledSchedules: 1)
        XCTAssertEqual(med.doseSummary, "500mg")
    }

    func test_doseSummary_twoTablets_showsQuantityAndTotal() {
        // 500mg tablets, 2 per dose once daily (totalDosesPerDay = 2, 1 schedule)
        let med = makeMedication(dosage: "500mg", totalDosesPerDay: 2, enabledSchedules: 1)
        XCTAssertEqual(med.doseSummary, "2 tablets · 1000mg")
    }

    func test_doseSummary_halfTablet_showsFractionalTotal() {
        // 20mg tablets, half a tablet per dose (totalDosesPerDay = 0.5, 1 schedule)
        let med = makeMedication(dosage: "20mg", totalDosesPerDay: 0.5, enabledSchedules: 1)
        XCTAssertEqual(med.doseSummary, "0.5 tablet · 10mg")
    }

    func test_doseSummary_oneAndHalfTablets() {
        let med = makeMedication(dosage: "20mg", totalDosesPerDay: 1.5, enabledSchedules: 1)
        XCTAssertEqual(med.doseSummary, "1.5 tablets · 30mg")
    }

    func test_doseSummary_twiceDaily_doesNotDoubleCount() {
        // Metformin 500mg, 2 tablets twice daily => totalDosesPerDay 4 across 2 schedules => 2 per dose
        let med = makeMedication(dosage: "500mg", totalDosesPerDay: 4, enabledSchedules: 2)
        XCTAssertEqual(med.doseSummary, "2 tablets · 1000mg")
    }

    func test_doseSummaryWithForm_singleUnit_keepsFormSuffix() {
        let med = makeMedication(dosage: "500mg", unit: "pill", totalDosesPerDay: 1, enabledSchedules: 1)
        XCTAssertEqual(med.doseSummaryWithForm, "500mg · pill")
    }

    func test_doseSummaryWithForm_multiUnit_matchesDoseSummary() {
        let med = makeMedication(dosage: "500mg", totalDosesPerDay: 2, enabledSchedules: 1)
        XCTAssertEqual(med.doseSummaryWithForm, med.doseSummary)
    }
}
