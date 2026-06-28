// DoseTrackTests/TodayViewModelTests.swift
import XCTest
import CoreData
@testable import DoseTrack

@MainActor
final class TodayViewModelTests: XCTestCase {

    var context: NSManagedObjectContext!
    var sut: TodayViewModel!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).viewContext
        sut = TodayViewModel(context: context)
    }

    override func tearDownWithError() throws {
        sut = nil
        context = nil
    }

    func testAdherencePercent_oneHundredWhenNoMedications() {
        sut.refresh()
        XCTAssertEqual(sut.adherencePercent, 100)
        XCTAssertEqual(sut.totalCount, 0)
    }

    func testAdherencePercent_calculatesCorrectly() {
        sut.takenCount = 3
        sut.totalCount = 4
        XCTAssertEqual(sut.adherencePercent, 75)
    }

    func testAdherencePercent_roundsDown() {
        sut.takenCount = 1
        sut.totalCount = 3
        XCTAssertEqual(sut.adherencePercent, 33)
    }

    func testAllDoneToday_trueWhenAllTaken() {
        sut.takenCount = 3
        sut.totalCount = 3
        XCTAssertTrue(sut.allDonToday)
    }

    func testAllDoneToday_falseWhenPartial() {
        sut.takenCount = 2
        sut.totalCount = 3
        XCTAssertFalse(sut.allDonToday)
    }

    func testAllDoneToday_falseWhenZeroTotal() {
        sut.takenCount = 0
        sut.totalCount = 0
        XCTAssertFalse(sut.allDonToday)
    }

    func testMarkTaken_writesNewLog() throws {
        let med = Medication.create(in: context, name: "Aspirin", dosage: "81mg")
        let schedule = Schedule.create(in: context, medication: med, hour: 8, minute: 0)
        try context.save()

        let entry = DoseEntry(
            id: UUID(), medication: med, schedule: schedule,
            scheduledAt: Date(), status: .missed, existingLog: nil
        )

        sut.markTaken(entry)

        let logs = try context.fetch(DoseLog.fetchRequest())
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.doseStatus, .taken)
    }

    func testMarkSkipped_writesNewLog() throws {
        let med = Medication.create(in: context, name: "Metformin", dosage: "500mg")
        let schedule = Schedule.create(in: context, medication: med, hour: 9, minute: 0)
        try context.save()

        let entry = DoseEntry(
            id: UUID(), medication: med, schedule: schedule,
            scheduledAt: Date(), status: .missed, existingLog: nil
        )

        sut.markSkipped(entry)

        let logs = try context.fetch(DoseLog.fetchRequest())
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.doseStatus, .skipped)
    }

    func testMarkTaken_updatesExistingLog_doesNotCreateDuplicate() throws {
        let med = Medication.create(in: context, name: "Ibuprofen", dosage: "200mg")
        let schedule = Schedule.create(in: context, medication: med)
        let existing = DoseLog.create(in: context, medication: med, scheduledAt: Date(), status: .skipped)
        try context.save()

        let entry = DoseEntry(
            id: UUID(), medication: med, schedule: schedule,
            scheduledAt: Date(), status: .skipped, existingLog: existing
        )

        sut.markTaken(entry)

        XCTAssertEqual(existing.doseStatus, .taken)
        let logs = try context.fetch(DoseLog.fetchRequest())
        XCTAssertEqual(logs.count, 1, "Should update in place, not create a second log")
    }
}
