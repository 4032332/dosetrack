// DoseTrackTests/DoseLoggingServiceTests.swift
import XCTest
import CoreData
@testable import DoseTrack

@MainActor
final class DoseLoggingServiceTests: XCTestCase {
    private func makeContext() -> NSManagedObjectContext {
        PersistenceController(inMemory: true).viewContext
    }

    func test_markTaken_createsLogWithTakenStatus() {
        let ctx = makeContext()
        let med = Medication.create(in: ctx, name: "Metformin", dosage: "500mg")
        med.totalDosesPerDay = 2
        let sched = Schedule.create(in: ctx, medication: med, hour: 8, minute: 0)
        let at = Date()
        DoseLoggingService.shared.log(
            medication: med, schedule: sched, scheduledAt: at,
            status: .taken, existingLog: nil, notes: nil, context: ctx, pushUserId: nil
        )
        let logs = (try? ctx.fetch(DoseLog.fetchRequest())) ?? []
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.status, "taken")
    }

    func test_markTaken_decrementsSupplyByPerDoseQuantity() {
        let ctx = makeContext()
        let med = Medication.create(in: ctx, name: "Metformin", dosage: "500mg")
        med.currentCount = 10
        med.totalDosesPerDay = 4            // 2 schedules => 2 per dose
        let s1 = Schedule.create(in: ctx, medication: med, hour: 8, minute: 0)
        _ = Schedule.create(in: ctx, medication: med, hour: 20, minute: 0)
        DoseLoggingService.shared.log(
            medication: med, schedule: s1, scheduledAt: Date(),
            status: .taken, existingLog: nil, notes: nil, context: ctx, pushUserId: nil
        )
        XCTAssertEqual(med.currentCount, 8)  // 10 - 2
    }

    func test_markSkipped_doesNotDecrementSupply() {
        let ctx = makeContext()
        let med = Medication.create(in: ctx, name: "M", dosage: "1")
        med.currentCount = 5
        let s = Schedule.create(in: ctx, medication: med, hour: 8, minute: 0)
        DoseLoggingService.shared.log(
            medication: med, schedule: s, scheduledAt: Date(),
            status: .skipped, existingLog: nil, notes: "nausea", context: ctx, pushUserId: nil
        )
        XCTAssertEqual(med.currentCount, 5)
    }

    func test_reTakingExistingTakenLog_doesNotDoubleDecrement() {
        let ctx = makeContext()
        let med = Medication.create(in: ctx, name: "M", dosage: "1")
        med.currentCount = 5
        med.totalDosesPerDay = 1
        let s = Schedule.create(in: ctx, medication: med, hour: 8, minute: 0)
        let at = Date()
        let existing = DoseLog.create(in: ctx, medication: med, scheduledAt: at, status: .taken)
        DoseLoggingService.shared.log(
            medication: med, schedule: s, scheduledAt: at,
            status: .taken, existingLog: existing, notes: nil, context: ctx, pushUserId: nil
        )
        XCTAssertEqual(med.currentCount, 5) // already taken => no further decrement
    }

    func test_skipReason_storedInNotes() {
        let ctx = makeContext()
        let med = Medication.create(in: ctx, name: "M", dosage: "1")
        let s = Schedule.create(in: ctx, medication: med, hour: 8, minute: 0)
        DoseLoggingService.shared.log(
            medication: med, schedule: s, scheduledAt: Date(),
            status: .skipped, existingLog: nil, notes: "away", context: ctx, pushUserId: nil
        )
        let log = (try? ctx.fetch(DoseLog.fetchRequest()))?.first
        XCTAssertEqual(log?.notes, "away")
    }
}
