// DoseTrackTests/RoutineLinkerTests.swift
import XCTest
import CoreData
@testable import DoseTrack

@MainActor
final class RoutineLinkerTests: XCTestCase {

    var context: NSManagedObjectContext!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).viewContext
    }
    override func tearDownWithError() throws { context = nil }

    private func bedtime(_ h: Int = 20, _ m: Int = 30) -> Routine {
        Routine(name: "Bedtime", hour: h, minute: m, anchor: .bedtime)
    }

    func test_link_singleSchedule_setsLabelAndTime() throws {
        let med = Medication.create(in: context, name: "Melatonin", dosage: "2mg")
        let sched = Schedule.create(in: context, medication: med, hour: 20, minute: 0)
        try context.save()

        RoutineLinker.link(med: med, to: bedtime(), context: context)

        XCTAssertEqual(sched.routineLabel, "Bedtime")
        XCTAssertEqual(sched.hour, 20)
        XCTAssertEqual(sched.minute, 30, "Linking moves the schedule onto the routine's time")
    }

    func test_link_twiceDaily_onlyMovesClosestDose() throws {
        // The exact bug this guards: a twice-daily med must NOT be collapsed onto one time.
        let med = Medication.create(in: context, name: "Magnesium", dosage: "100mg")
        let morning = Schedule.create(in: context, medication: med, hour: 5,  minute: 0)
        let evening = Schedule.create(in: context, medication: med, hour: 20, minute: 30)
        try context.save()

        RoutineLinker.link(med: med, to: bedtime(20, 30), context: context)

        XCTAssertEqual(evening.routineLabel, "Bedtime", "Nearest dose joins the routine")
        XCTAssertNil(morning.routineLabel, "The morning dose is left untouched")
        XCTAssertEqual(morning.hour, 5, "Morning time preserved — not collapsed")
    }

    func test_link_noSchedules_createsOne() throws {
        let med = Medication.create(in: context, name: "Vitamin D", dosage: "1000IU")
        try context.save()

        RoutineLinker.link(med: med, to: bedtime(), context: context)

        XCTAssertEqual(med.schedulesArray.count, 1)
        XCTAssertEqual(med.schedulesArray.first?.routineLabel, "Bedtime")
    }

    func test_unlink_dropsLabelKeepsTime() throws {
        let med = Medication.create(in: context, name: "Restavit", dosage: "25mg")
        let sched = Schedule.create(in: context, medication: med, hour: 20, minute: 30)
        sched.routineLabel = "Bedtime"
        try context.save()

        RoutineLinker.unlink(med: med, routineName: "Bedtime", context: context)

        XCTAssertNil(sched.routineLabel)
        XCTAssertEqual(sched.hour, 20)
        XCTAssertEqual(sched.minute, 30, "Unlinking keeps the clock time")
    }

    func test_propagateChange_movesLinkedSchedulesToNewTime() throws {
        let med = Medication.create(in: context, name: "Clonidine", dosage: "100mcg")
        let sched = Schedule.create(in: context, medication: med, hour: 20, minute: 30)
        sched.routineLabel = "Bedtime"
        try context.save()

        // Bedtime moves from 20:30 to 21:15 — the linked dose must follow.
        RoutineLinker.propagateChange(fromName: "Bedtime",
                                      to: Routine(name: "Bedtime", hour: 21, minute: 15, anchor: .bedtime),
                                      context: context)

        XCTAssertEqual(sched.hour, 21)
        XCTAssertEqual(sched.minute, 15)
        XCTAssertEqual(sched.routineLabel, "Bedtime")
    }
}
