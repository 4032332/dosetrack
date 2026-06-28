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
        vm.dosage = "10mg"

        let result = vm.save()

        XCTAssertNotNil(result)
        let meds = try context.fetch(Medication.fetchRequest())
        XCTAssertEqual(meds.count, 1)
        XCTAssertEqual(meds.first?.name, "Lisinopril")
    }

    func testSave_createsSchedules() throws {
        let vm = AddEditMedicationViewModel(context: context)
        vm.name = "Metformin"
        vm.dosage = "500mg"
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
        vm.dosage = "10mg"

        let result = vm.save()

        XCTAssertNil(result)
        XCTAssertNotNil(vm.nameError)
    }

    func testSave_failsWithEmptyDosage() {
        let vm = AddEditMedicationViewModel(context: context)
        vm.name = "Aspirin"
        vm.dosage = ""

        let result = vm.save()

        XCTAssertNil(result)
        XCTAssertNotNil(vm.dosageError)
    }

    func testSave_trimsWhitespace() throws {
        let vm = AddEditMedicationViewModel(context: context)
        vm.name = "  Aspirin  "
        vm.dosage = "  81mg  "

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
        vm.dosage = "10mg"
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
        XCTAssertEqual(vm.dosage, "20mg")
        XCTAssertEqual(vm.unit, "pill")
        XCTAssertEqual(vm.colorHex, "#FF6B6B")
        XCTAssertEqual(vm.notes, "Take at night")
        XCTAssertEqual(vm.currentCount, 30)
        XCTAssertEqual(vm.refillThreshold, 10)
    }
}
