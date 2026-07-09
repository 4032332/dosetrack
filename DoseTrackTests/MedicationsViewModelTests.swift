// DoseTrackTests/MedicationsViewModelTests.swift
import XCTest
import CoreData
@testable import DoseTrack

@MainActor
final class MedicationsViewModelTests: XCTestCase {

    var context: NSManagedObjectContext!
    var sut: MedicationsViewModel!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).viewContext
        sut = MedicationsViewModel(context: context, isProSubscriber: { false })
    }

    override func tearDownWithError() throws {
        sut = nil
        context = nil
    }

    func testFetchMedications_returnsOnlyActive() throws {
        Medication.create(in: context, name: "Active", dosage: "10mg")
        let inactive = Medication.create(in: context, name: "Inactive", dosage: "20mg")
        inactive.isActive = false
        try context.save()

        sut.fetchMedications()

        XCTAssertEqual(sut.medications.count, 1)
        XCTAssertEqual(sut.medications.first?.name, "Active")
    }

    func testCanAddMedication_trueWhenBelowLimit() {
        XCTAssertTrue(sut.canAddMedication())
        XCTAssertFalse(sut.showingPaywall)
    }

    func testCanAddMedication_falseAtFreeTierLimit() throws {
        for i in 1...5 {
            Medication.create(in: context, name: "Med \(i)", dosage: "10mg")
        }
        try context.save()
        sut.fetchMedications()

        let result = sut.canAddMedication()

        XCTAssertFalse(result)
        XCTAssertTrue(sut.showingPaywall)
    }

    func testCanAddMedication_trueForProSubscriberAtLimit() throws {
        let proSut = MedicationsViewModel(context: context, isProSubscriber: { true })
        for i in 1...5 {
            Medication.create(in: context, name: "Med \(i)", dosage: "10mg")
        }
        try context.save()
        proSut.fetchMedications()

        XCTAssertTrue(proSut.canAddMedication())
        XCTAssertFalse(proSut.showingPaywall)
    }

    func testCanAddMedication_trueForPatientWithActiveCaregiverAtLimit() throws {
        // A patient covered by an active (therefore Pro) caregiver is not their own subscriber,
        // but must not hit the free-tier wall — their caregiver's plan covers them.
        let coveredSut = MedicationsViewModel(
            context: context,
            isProSubscriber: { false },
            hasActiveCaregiver: { true }
        )
        for i in 1...5 {
            Medication.create(in: context, name: "Med \(i)", dosage: "10mg")
        }
        try context.save()
        coveredSut.fetchMedications()

        XCTAssertTrue(coveredSut.canAddMedication())
        XCTAssertFalse(coveredSut.showingPaywall)
    }

    func testRequestDelete_setsIsActiveToFalseImmediately() throws {
        // No confirmation step — reaching this action already requires a deliberate two-step
        // gesture (swipe + tap, or Edit mode + tap the minus button), so requestDelete performs
        // the soft-delete directly rather than needing an intermediate "Are you sure?" dialog.
        let med = Medication.create(in: context, name: "To Delete", dosage: "5mg")
        try context.save()
        sut.fetchMedications()

        sut.requestDelete(med)

        XCTAssertFalse(med.isActive)
        XCTAssertEqual(sut.medications.count, 0)
    }

    func testMoveItems_updatesSortOrder() throws {
        for i in 0..<3 {
            let m = Medication.create(in: context, name: "Med \(i)", dosage: "10mg")
            m.sortOrder = Int32(i)
        }
        try context.save()
        sut.fetchMedications()

        // Move first item to end
        sut.moveItems(from: IndexSet(integer: 0), to: 3)

        XCTAssertEqual(sut.medications[2].wrappedName, "Med 0")
    }

    func testRequestAddMedication_setsShowingAddForm() {
        sut.requestAddMedication()
        XCTAssertTrue(sut.showingAddForm)
    }

    func testRequestAddMedication_showsPaywallAtLimit() throws {
        for i in 1...5 {
            Medication.create(in: context, name: "Med \(i)", dosage: "10mg")
        }
        try context.save()
        sut.fetchMedications()

        sut.requestAddMedication()

        XCTAssertFalse(sut.showingAddForm)
        XCTAssertTrue(sut.showingPaywall)
    }
}
