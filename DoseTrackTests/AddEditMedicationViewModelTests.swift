// DoseTrackTests/AddEditMedicationViewModelTests.swift
import XCTest
import CoreData
@testable import DoseTrack

@MainActor
final class AddEditMedicationViewModelTests: XCTestCase {

    var context: NSManagedObjectContext!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).viewContext
    }

    override func tearDownWithError() throws {
        context = nil
    }

    func testSave_createsNewMedication() throws {
        let vm = AddEditMedicationViewModel(context: context)
        vm.name = "Lisinopril"
        vm.doseAmount = "10"
        vm.doseUnit = "mg"

        let result = vm.save()

        XCTAssertNotNil(result)
        let meds = try context.fetch(Medication.fetchRequest())
        XCTAssertEqual(meds.count, 1)
        XCTAssertEqual(meds.first?.name, "Lisinopril")
    }

    func testSave_createsSchedules() throws {
        let vm = AddEditMedicationViewModel(context: context)
        vm.name = "Metformin"
        vm.doseAmount = "500"
        vm.doseUnit = "mg"
        vm.schedules = [
            ScheduleDraft(hour: 8, minute: 0),
            ScheduleDraft(hour: 20, minute: 0)
        ]

        vm.save()

        let schedules = try context.fetch(Schedule.fetchRequest())
        XCTAssertEqual(schedules.count, 2)
    }

    func testSave_failsWithEmptyName() {
        let vm = AddEditMedicationViewModel(context: context)
        vm.name = "   "
        vm.doseAmount = "10"
        vm.doseUnit = "mg"

        let result = vm.save()

        XCTAssertNil(result)
        XCTAssertNotNil(vm.nameError)
    }

    /// Strength used to be mandatory. It no longer is: plenty of real products don't print a single
    /// strength (a scoop of powder, a 19-ingredient multivitamin), and requiring a number there
    /// pushed people into inventing one — worse than a blank on a medical record.
    func testSave_succeedsWithEmptyDosage() throws {
        let vm = AddEditMedicationViewModel(context: context)
        vm.name = "Magnesium Powder"
        vm.doseAmount = ""
        vm.quantityUnit = "scoop"

        let result = vm.save()

        XCTAssertNotNil(result, "A missing strength must not block saving")
        XCTAssertNil(vm.doseError)
    }

    /// A blank strength must store a genuinely empty dosage — not a bare unit like "mg", which
    /// would render as a nonsense strength everywhere the dose summary is shown.
    func testSave_emptyDosageStoresEmptyStringNotBareUnit() throws {
        let vm = AddEditMedicationViewModel(context: context)
        vm.name = "Protein"
        vm.doseAmount = ""
        vm.doseUnit = "mg"

        let med = try XCTUnwrap(vm.save())

        XCTAssertEqual(med.wrappedDosage, "", "Expected empty dosage, got a bare unit")
    }

    func testSave_trimsWhitespace() throws {
        let vm = AddEditMedicationViewModel(context: context)
        vm.name = "  Aspirin  "
        vm.doseAmount = "  81  "
        vm.doseUnit = "mg"

        vm.save()

        let meds = try context.fetch(Medication.fetchRequest())
        XCTAssertEqual(meds.first?.name, "Aspirin")
        XCTAssertEqual(meds.first?.dosage, "81mg")
    }

    func testSave_updatesExistingMedication() throws {
        let med = Medication.create(in: context, name: "Old Name", dosage: "5mg")
        try context.save()

        let vm = AddEditMedicationViewModel(context: context, medication: med)
        vm.name = "New Name"
        vm.doseAmount = "10"
        vm.doseUnit = "mg"
        vm.save()

        XCTAssertEqual(med.name, "New Name")
        XCTAssertEqual(med.dosage, "10mg")
        let meds = try context.fetch(Medication.fetchRequest())
        XCTAssertEqual(meds.count, 1, "Should update, not create a duplicate")
    }

    func testSave_replacesSchedulesOnEdit() throws {
        let med = Medication.create(in: context, name: "Vitamin D", dosage: "1000 IU")
        Schedule.create(in: context, medication: med, hour: 8, minute: 0)
        Schedule.create(in: context, medication: med, hour: 20, minute: 0)
        try context.save()

        let vm = AddEditMedicationViewModel(context: context, medication: med)
        vm.schedules = [ScheduleDraft(hour: 12, minute: 30)]
        vm.save()

        let schedules = try context.fetch(Schedule.fetchRequest())
        XCTAssertEqual(schedules.count, 1)
        XCTAssertEqual(schedules.first?.hour, 12)
        XCTAssertEqual(schedules.first?.minute, 30)
    }

    func testIsEditing_trueForExistingMedication() {
        let med = Medication.create(in: context, name: "Test", dosage: "5mg")
        let vm = AddEditMedicationViewModel(context: context, medication: med)
        XCTAssertTrue(vm.isEditing)
    }

    func testIsEditing_falseForNewMedication() {
        let vm = AddEditMedicationViewModel(context: context)
        XCTAssertFalse(vm.isEditing)
    }

    func testAddSchedule_appendsNewDraft() {
        let vm = AddEditMedicationViewModel(context: context)
        XCTAssertEqual(vm.schedules.count, 1)
        vm.addSchedule()
        XCTAssertEqual(vm.schedules.count, 2)
    }

    func testRemoveSchedule_keepsMinimumOne() {
        let vm = AddEditMedicationViewModel(context: context)
        vm.removeSchedule(at: IndexSet(integer: 0))
        XCTAssertEqual(vm.schedules.count, 1, "Should always have at least one schedule")
    }

    func testFormPopulatesFromExistingMedication() throws {
        let med = Medication.create(in: context, name: "Atorvastatin", dosage: "20mg")
        med.unit = "pill"
        med.colorHex = "#FF6B6B"
        med.notes = "Take at night"
        med.currentCount = 30
        med.refillThreshold = 10
        try context.save()

        let vm = AddEditMedicationViewModel(context: context, medication: med)

        XCTAssertEqual(vm.name, "Atorvastatin")
        XCTAssertEqual(vm.doseAmount, "20")
        XCTAssertEqual(vm.doseUnit, "mg")
        XCTAssertEqual(vm.quantityUnit, "pill")
        XCTAssertEqual(vm.colorHex, "#FF6B6B")
        XCTAssertEqual(vm.notes, "Take at night")
        XCTAssertEqual(vm.currentCount, 30)
        XCTAssertEqual(vm.refillThreshold, 10)
    }
}
