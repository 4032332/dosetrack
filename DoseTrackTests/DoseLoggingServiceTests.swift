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

    // MARK: - backdateEdit

    func test_backdateEdit_marksLogAsBackdated() {
        let ctx = makeContext()
        let med = Medication.create(in: ctx, name: "Metformin", dosage: "500mg")
        let log = DoseLog.create(in: ctx, medication: med, scheduledAt: Date(), status: .missed)
        DoseLoggingService.shared.backdateEdit(
            log: log, newStatus: .taken, notes: nil, context: ctx, pushUserId: nil
        )
        XCTAssertEqual(log.doseStatus, .taken)
        XCTAssertTrue(log.isBackdated)
    }

    func test_backdateEdit_missedToTaken_decrementsSupply() {
        let ctx = makeContext()
        let med = Medication.create(in: ctx, name: "Metformin", dosage: "500mg")
        med.currentCount = 10
        med.totalDosesPerDay = 1
        _ = Schedule.create(in: ctx, medication: med, hour: 8, minute: 0)
        let log = DoseLog.create(in: ctx, medication: med, scheduledAt: Date(), status: .missed)

        DoseLoggingService.shared.backdateEdit(
            log: log, newStatus: .taken, notes: nil, context: ctx, pushUserId: nil
        )
        XCTAssertEqual(med.currentCount, 9, "Correcting a missed dose to taken should decrement supply, same as logging it taken live")
    }

    func test_backdateEdit_takenToMissed_restoresSupply() {
        let ctx = makeContext()
        let med = Medication.create(in: ctx, name: "Metformin", dosage: "500mg")
        med.currentCount = 5
        med.totalDosesPerDay = 1
        _ = Schedule.create(in: ctx, medication: med, hour: 8, minute: 0)
        let log = DoseLog.create(in: ctx, medication: med, scheduledAt: Date(), status: .taken)

        DoseLoggingService.shared.backdateEdit(
            log: log, newStatus: .missed, notes: nil, context: ctx, pushUserId: nil
        )
        XCTAssertEqual(med.currentCount, 6, "Correcting a taken dose to missed should restore the supply it had decremented")
    }

    func test_backdateEdit_skippedToTaken_doesNotDoubleAdjustSupply() {
        let ctx = makeContext()
        let med = Medication.create(in: ctx, name: "Metformin", dosage: "500mg")
        med.currentCount = 10
        med.totalDosesPerDay = 1
        _ = Schedule.create(in: ctx, medication: med, hour: 8, minute: 0)
        let log = DoseLog.create(in: ctx, medication: med, scheduledAt: Date(), status: .skipped)

        DoseLoggingService.shared.backdateEdit(
            log: log, newStatus: .taken, notes: nil, context: ctx, pushUserId: nil
        )
        XCTAssertEqual(med.currentCount, 9, "Skipped never decremented, so moving to taken decrements exactly once")
    }

    // MARK: - As-needed (PRN) logging

    func test_logAsNeeded_createsOneLogPerDoseMarkedAsNeeded() {
        let ctx = makeContext()
        let med = Medication.create(in: ctx, name: "Panadeine Forte", dosage: "500mg")
        med.allowsAsNeeded = true
        med.storedQuantityPerDose = 1

        DoseLoggingService.shared.logAsNeeded(
            medication: med, doseCount: 3, notes: "Headache", context: ctx, pushUserId: nil
        )

        let logs = (try? ctx.fetch(DoseLog.fetchRequest())) ?? []
        XCTAssertEqual(logs.count, 3, "One row per dose, so History shows three entries")
        XCTAssertTrue(logs.allSatisfy { $0.isAsNeeded })
        XCTAssertTrue(logs.allSatisfy { $0.doseStatus == .taken })
        XCTAssertTrue(logs.allSatisfy { $0.wrappedNotes == "Headache" })
    }

    func test_logAsNeeded_decrementsSupplyByCountTimesPerDose() {
        let ctx = makeContext()
        let med = Medication.create(in: ctx, name: "Ibuprofen", dosage: "200mg")
        med.currentCount = 20
        med.storedQuantityPerDose = 2   // two tablets per dose

        DoseLoggingService.shared.logAsNeeded(
            medication: med, doseCount: 3, notes: nil, context: ctx, pushUserId: nil
        )

        // 3 doses x 2 tablets = 6 consumed
        XCTAssertEqual(med.currentCount, 14, accuracy: 0.001)
    }

    /// An as-needed-only item has no schedules, so the legacy
    /// totalDosesPerDay ÷ enabledScheduleCount derivation is meaningless for it — this is the
    /// regression guard for that (it used to yield a flat 0.5 for everything).
    func test_logAsNeeded_usesStoredPerDoseWhenItemHasNoSchedules() {
        let ctx = makeContext()
        let med = Medication.create(in: ctx, name: "PRN only", dosage: "5mg")
        med.currentCount = 10
        med.storedQuantityPerDose = 2
        med.totalDosesPerDay = 0        // no schedules at all
        XCTAssertTrue(med.schedulesArray.isEmpty)

        DoseLoggingService.shared.logAsNeeded(
            medication: med, doseCount: 1, notes: nil, context: ctx, pushUserId: nil
        )

        XCTAssertEqual(med.currentCount, 8, accuracy: 0.001,
                       "Must consume the stored 2 units, not a derived fallback")
    }

    func test_logAsNeeded_zeroDosesIsANoOp() {
        let ctx = makeContext()
        let med = Medication.create(in: ctx, name: "Ibuprofen", dosage: "200mg")
        med.currentCount = 10

        let logs = DoseLoggingService.shared.logAsNeeded(
            medication: med, doseCount: 0, notes: nil, context: ctx, pushUserId: nil
        )

        XCTAssertTrue(logs.isEmpty)
        XCTAssertEqual(med.currentCount, 10, accuracy: 0.001)
    }

    func test_logAsNeeded_neverDrivesSupplyNegative() {
        let ctx = makeContext()
        let med = Medication.create(in: ctx, name: "Ibuprofen", dosage: "200mg")
        med.currentCount = 1
        med.storedQuantityPerDose = 1

        DoseLoggingService.shared.logAsNeeded(
            medication: med, doseCount: 5, notes: nil, context: ctx, pushUserId: nil
        )

        XCTAssertEqual(med.currentCount, 0, accuracy: 0.001)
    }
}
