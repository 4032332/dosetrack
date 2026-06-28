// DoseTrackTests/CoreDataTests.swift
import XCTest
import CoreData
@testable import DoseTrack

final class CoreDataTests: XCTestCase {

    var sut: PersistenceController!
    var context: NSManagedObjectContext!

    override func setUpWithError() throws {
        sut = PersistenceController(inMemory: true)
        context = sut.viewContext
    }

    override func tearDownWithError() throws {
        context = nil
        sut = nil
    }

    // MARK: - Medication

    func testCreateMedication_persistsCorrectly() throws {
        let med = Medication.create(in: context, name: "Aspirin", dosage: "81mg")
        try context.save()

        let fetch = NSFetchRequest<Medication>(entityName: "Medication")
        let results = try context.fetch(fetch)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.name, "Aspirin")
        XCTAssertEqual(results.first?.dosage, "81mg")
        XCTAssertTrue(results.first?.isActive == true)
        XCTAssertNotNil(results.first?.id)
        XCTAssertNotNil(results.first?.createdAt)
    }

    func testSoftDeleteMedication_setsIsActiveToFalse() throws {
        let med = Medication.create(in: context, name: "Metformin", dosage: "500mg")
        try context.save()

        med.isActive = false
        try context.save()

        let fetch = NSFetchRequest<Medication>(entityName: "Medication")
        fetch.predicate = NSPredicate(format: "isActive == YES")
        let activeResults = try context.fetch(fetch)
        XCTAssertEqual(activeResults.count, 0)
    }

    func testDeleteMedication_cascadesToSchedulesAndLogs() throws {
        let med = Medication.create(in: context, name: "Ibuprofen", dosage: "200mg")
        Schedule.create(in: context, medication: med, hour: 8, minute: 0)
        DoseLog.create(in: context, medication: med, scheduledAt: Date(), status: .taken)
        try context.save()

        context.delete(med)
        try context.save()

        let schedFetch = NSFetchRequest<Schedule>(entityName: "Schedule")
        let logFetch = NSFetchRequest<DoseLog>(entityName: "DoseLog")
        let schedules = try context.fetch(schedFetch)
        let logs = try context.fetch(logFetch)

        XCTAssertEqual(schedules.count, 0, "Schedules should cascade-delete with medication")
        XCTAssertEqual(logs.count, 0, "DoseLogs should cascade-delete with medication")
    }

    // MARK: - Schedule

    func testCreateSchedule_linkedToMedication() throws {
        let med = Medication.create(in: context, name: "Vitamin D", dosage: "1000 IU")
        let schedule = Schedule.create(in: context, medication: med, hour: 9, minute: 30)
        try context.save()

        XCTAssertEqual(schedule.medication, med)
        XCTAssertEqual(schedule.hour, 9)
        XCTAssertEqual(schedule.minute, 30)
        XCTAssertTrue(schedule.isEnabled)
        XCTAssertNotNil(schedule.id)
    }

    func testSchedule_daysOfWeekRoundTrip() throws {
        let med = Medication.create(in: context, name: "Omega-3", dosage: "1000mg")
        let schedule = Schedule.create(in: context, medication: med)
        schedule.daysOfWeekArray = [2, 4, 6]
        try context.save()

        context.refresh(schedule, mergeChanges: false)
        XCTAssertEqual(schedule.daysOfWeekArray, [2, 4, 6])
    }

    // MARK: - DoseLog

    func testCreateDoseLog_withTakenStatus() throws {
        let med = Medication.create(in: context, name: "Lisinopril", dosage: "10mg")
        let scheduled = Date()
        let log = DoseLog.create(in: context, medication: med, scheduledAt: scheduled, status: .taken)
        try context.save()

        XCTAssertEqual(log.doseStatus, .taken)
        XCTAssertEqual(log.scheduledAt, scheduled)
        XCTAssertNotNil(log.loggedAt)
        XCTAssertEqual(log.medication, med)
    }

    func testCreateDoseLog_allStatuses() throws {
        let med = Medication.create(in: context, name: "Atorvastatin", dosage: "20mg")
        let date = Date()
        DoseLog.create(in: context, medication: med, scheduledAt: date, status: .taken)
        DoseLog.create(in: context, medication: med, scheduledAt: date, status: .skipped)
        DoseLog.create(in: context, medication: med, scheduledAt: date, status: .missed)
        try context.save()

        let fetch = NSFetchRequest<DoseLog>(entityName: "DoseLog")
        let logs = try context.fetch(fetch)
        let statuses = Set(logs.map { $0.doseStatus })
        XCTAssertEqual(statuses, [.taken, .skipped, .missed])
    }

    // MARK: - PersistenceController

    func testPersistenceController_saveNoop_whenNoChanges() {
        sut.save()
    }

    func testPersistenceController_preview_hasSeedData() {
        let previewContext = PersistenceController.preview.viewContext
        let fetch = NSFetchRequest<Medication>(entityName: "Medication")
        let results = try? previewContext.fetch(fetch)
        XCTAssertFalse(results?.isEmpty ?? true, "Preview should have seed medication")
    }

    // MARK: - Free Tier Limit

    func testFreeTierLimit_maxFiveMedications() throws {
        for i in 1...5 {
            Medication.create(in: context, name: "Med \(i)", dosage: "10mg")
        }
        try context.save()

        let fetch = NSFetchRequest<Medication>(entityName: "Medication")
        fetch.predicate = NSPredicate(format: "isActive == YES")
        let count = try context.count(for: fetch)
        XCTAssertEqual(count, Constants.FreeTier.maxMedications)
    }

    // MARK: - Wrapped accessors

    func testWrappedAccessors_returnDefaultsForNilValues() throws {
        let med = Medication.create(in: context, name: "Test", dosage: "100mg")
        med.notes = nil
        med.colorHex = nil
        try context.save()

        XCTAssertEqual(med.wrappedNotes, "")
        XCTAssertEqual(med.wrappedColorHex, "#5B8AF0")
    }

    func testMedication_isRefillWarning_whenCountBelowThreshold() throws {
        let med = Medication.create(in: context, name: "Low Pill", dosage: "50mg")
        med.currentCount = 3
        med.refillThreshold = 7
        try context.save()

        XCTAssertTrue(med.isRefillWarning)
    }

    func testMedication_isRefillWarning_falseWhenCountAboveThreshold() throws {
        let med = Medication.create(in: context, name: "Full Pill", dosage: "50mg")
        med.currentCount = 30
        med.refillThreshold = 7
        try context.save()

        XCTAssertFalse(med.isRefillWarning)
    }
}
