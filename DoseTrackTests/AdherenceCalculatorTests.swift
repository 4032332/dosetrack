// DoseTrackTests/AdherenceCalculatorTests.swift
import XCTest
import CoreData
@testable import DoseTrack

@MainActor
final class AdherenceCalculatorTests: XCTestCase {

    var context: NSManagedObjectContext!
    var sut: HistoryViewModel!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).viewContext
        sut = HistoryViewModel(context: context)
    }

    override func tearDownWithError() throws {
        sut = nil
        context = nil
    }

    func testOverallPercent_oneHundredWhenNoLogs() {
        sut.refresh()
        XCTAssertEqual(sut.overallPercent, 1.0, accuracy: 0.001)
    }

    func testOverallPercent_calculatesCorrectly() throws {
        let med = Medication.create(in: context, name: "Aspirin", dosage: "81mg")
        DoseLog.create(in: context, medication: med, scheduledAt: Date(), status: .taken)
        DoseLog.create(in: context, medication: med, scheduledAt: Date(), status: .taken)
        DoseLog.create(in: context, medication: med, scheduledAt: Date(), status: .skipped)
        try context.save()

        sut.refresh()

        XCTAssertEqual(sut.overallPercent, 2.0 / 3.0, accuracy: 0.001)
    }

    func testDayAdherences_countMatchesDateRange_week() throws {
        sut.rangeMode = .week
        sut.refresh()
        XCTAssertEqual(sut.dayAdherences.count, 7)
    }

    func testDayAdherences_countMatchesDateRange_month() throws {
        sut.rangeMode = .month
        sut.refresh()
        XCTAssertEqual(sut.dayAdherences.count, 30)
    }

    func testDayAdherence_colorGreenWhenHundredPercent() throws {
        let med = Medication.create(in: context, name: "Test", dosage: "5mg")
        DoseLog.create(in: context, medication: med, scheduledAt: Date(), status: .taken)
        try context.save()

        sut.rangeMode = .week
        sut.refresh()

        // Today's entry should have percent == 1.0
        let today = Calendar.current.startOfDay(for: Date())
        if let todayEntry = sut.dayAdherences.first(where: { Calendar.current.isDate($0.date, inSameDayAs: today) }) {
            XCTAssertEqual(todayEntry.percent, 1.0, accuracy: 0.001)
        }
    }

    func testMedicationAdherences_appearsAfterRefresh() throws {
        let med = Medication.create(in: context, name: "Lisinopril", dosage: "10mg")
        DoseLog.create(in: context, medication: med, scheduledAt: Date(), status: .taken)
        DoseLog.create(in: context, medication: med, scheduledAt: Date(), status: .skipped)
        try context.save()

        sut.refresh()

        XCTAssertEqual(sut.medicationAdherences.count, 1)
        XCTAssertEqual(sut.medicationAdherences.first?.name, "Lisinopril")
        XCTAssertEqual(sut.medicationAdherences.first?.taken, 1)
        XCTAssertEqual(sut.medicationAdherences.first?.total, 2)
    }

    func testMedicationAdherences_excludesMedsWithNoLogs() throws {
        Medication.create(in: context, name: "Med With No Logs", dosage: "5mg")
        let med2 = Medication.create(in: context, name: "Med With Logs", dosage: "10mg")
        DoseLog.create(in: context, medication: med2, scheduledAt: Date(), status: .taken)
        try context.save()

        sut.refresh()

        XCTAssertEqual(sut.medicationAdherences.count, 1)
        XCTAssertEqual(sut.medicationAdherences.first?.name, "Med With Logs")
    }

    func testMedicationAdherences_sortedAlphabetically() throws {
        let m1 = Medication.create(in: context, name: "Zinc", dosage: "50mg")
        let m2 = Medication.create(in: context, name: "Aspirin", dosage: "81mg")
        DoseLog.create(in: context, medication: m1, scheduledAt: Date(), status: .taken)
        DoseLog.create(in: context, medication: m2, scheduledAt: Date(), status: .taken)
        try context.save()

        sut.refresh()

        XCTAssertEqual(sut.medicationAdherences.first?.name, "Aspirin")
        XCTAssertEqual(sut.medicationAdherences.last?.name, "Zinc")
    }

    func testCustomDateRange_onlyShowsLogsInRange() throws {
        let med = Medication.create(in: context, name: "Test", dosage: "1mg")
        let recentDate = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        let oldDate = Calendar.current.date(byAdding: .day, value: -60, to: Date())!
        DoseLog.create(in: context, medication: med, scheduledAt: recentDate, status: .taken)
        DoseLog.create(in: context, medication: med, scheduledAt: oldDate, status: .taken)
        try context.save()

        sut.rangeMode = .custom
        sut.customStart = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        sut.customEnd = Date()
        sut.refresh()

        XCTAssertEqual(sut.medicationAdherences.first?.total, 1, "Should only count the recent log")
    }

    func testDayAdherence_percentIsZeroWhenAllMissed() throws {
        let med = Medication.create(in: context, name: "Test", dosage: "5mg")
        DoseLog.create(in: context, medication: med, scheduledAt: Date(), status: .missed)
        DoseLog.create(in: context, medication: med, scheduledAt: Date(), status: .missed)
        try context.save()

        sut.rangeMode = .week
        sut.refresh()

        let today = Calendar.current.startOfDay(for: Date())
        let todayEntry = sut.dayAdherences.first { Calendar.current.isDate($0.date, inSameDayAs: today) }
        XCTAssertEqual(todayEntry?.percent ?? 1, 0.0, accuracy: 0.001)
    }

    // MARK: - As-needed (PRN) exclusion
    //
    // An as-needed dose can never be "missed", so if it counted as taken it could only ever push
    // the score up — someone leaning heavily on a PRN painkiller could read 95% adherent while
    // missing half their scheduled doses. These tests pin that exclusion down on both sides of
    // the ratio.

    func testOverallPercent_asNeededDosesAreExcludedEntirely() throws {
        let med = Medication.create(in: context, name: "Panadeine Forte", dosage: "500mg")
        // One scheduled dose, missed → a true 0% adherence.
        DoseLog.create(in: context, medication: med, scheduledAt: Date(), status: .missed)
        // Three as-needed doses taken. These must not rescue the score.
        for _ in 0..<3 {
            DoseLog.create(in: context, medication: med, scheduledAt: Date(), status: .taken, isAsNeeded: true)
        }
        try context.save()

        sut.refresh()

        XCTAssertEqual(sut.overallPercent, 0.0, accuracy: 0.001,
                       "Three taken PRN doses must not offset one missed scheduled dose")
    }

    func testOverallPercent_isOneHundredWhenOnlyAsNeededLogsExist() throws {
        let med = Medication.create(in: context, name: "Ibuprofen", dosage: "200mg")
        DoseLog.create(in: context, medication: med, scheduledAt: Date(), status: .taken, isAsNeeded: true)
        DoseLog.create(in: context, medication: med, scheduledAt: Date(), status: .taken, isAsNeeded: true)
        try context.save()

        sut.refresh()

        // No scheduled doses at all → nothing to be adherent to, so the neutral 100% applies
        // rather than a misleading 0%.
        XCTAssertEqual(sut.overallPercent, 1.0, accuracy: 0.001)
    }

    func testMedicationAdherence_reportsAsNeededSeparatelyFromRate() throws {
        let med = Medication.create(in: context, name: "Oxycodone", dosage: "5mg")
        DoseLog.create(in: context, medication: med, scheduledAt: Date(), status: .taken)
        DoseLog.create(in: context, medication: med, scheduledAt: Date(), status: .missed)
        DoseLog.create(in: context, medication: med, scheduledAt: Date(), status: .taken, isAsNeeded: true)
        DoseLog.create(in: context, medication: med, scheduledAt: Date(), status: .taken, isAsNeeded: true)
        try context.save()

        sut.refresh()

        let row = try XCTUnwrap(sut.medicationAdherences.first)
        XCTAssertEqual(row.total, 2, "Rate denominator counts scheduled doses only")
        XCTAssertEqual(row.taken, 1)
        XCTAssertEqual(row.asNeededCount, 2, "PRN doses surface as their own count")
        XCTAssertEqual(row.percent, 0.5, accuracy: 0.001)
    }

    // MARK: - Vitamin / supplement exclusion
    //
    // A forgotten multivitamin must never read as a missed prescription — but it should still be
    // visible in the breakdown with its own take-rate.

    func testOverallPercent_missedVitaminsDoNotHurtScore() throws {
        let med = Medication.create(in: context, name: "Metformin", dosage: "500mg", kind: .medication)
        let vitamin = Medication.create(in: context, name: "Vitamin D", dosage: "1000IU", kind: .vitamin)
        let supplement = Medication.create(in: context, name: "Magnesium", dosage: "", kind: .supplement)

        DoseLog.create(in: context, medication: med, scheduledAt: Date(), status: .taken)
        // Four missed non-medication doses that must not drag the perfect medication score down.
        DoseLog.create(in: context, medication: vitamin, scheduledAt: Date(), status: .missed)
        DoseLog.create(in: context, medication: vitamin, scheduledAt: Date(), status: .missed)
        DoseLog.create(in: context, medication: supplement, scheduledAt: Date(), status: .missed)
        DoseLog.create(in: context, medication: supplement, scheduledAt: Date(), status: .missed)
        try context.save()

        sut.refresh()

        XCTAssertEqual(sut.overallPercent, 1.0, accuracy: 0.001,
                       "Missed vitamins/supplements must not reduce medication adherence")
    }

    func testMedicationAdherences_stillListVitaminsWithTheirOwnRate() throws {
        let vitamin = Medication.create(in: context, name: "Vitamin C", dosage: "1000mg", kind: .vitamin)
        DoseLog.create(in: context, medication: vitamin, scheduledAt: Date(), status: .taken)
        DoseLog.create(in: context, medication: vitamin, scheduledAt: Date(), status: .missed)
        try context.save()

        sut.refresh()

        let row = try XCTUnwrap(sut.medicationAdherences.first { $0.name == "Vitamin C" })
        XCTAssertEqual(row.kind, .vitamin)
        XCTAssertEqual(row.percent, 0.5, accuracy: 0.001, "Vitamins keep a visible take-rate")
        XCTAssertFalse(row.countsTowardOverall, "…but it's flagged as excluded from the headline score")
    }

    func testMedicationAdherences_groupedMedicationsFirstThenVitaminsThenSupplements() throws {
        // Names chosen so pure alphabetical order (Aspirin, Zinc, Vitamin A) would NOT produce the
        // expected result, proving the sort is kind-first.
        let supp = Medication.create(in: context, name: "Zinc", dosage: "", kind: .supplement)
        let vit = Medication.create(in: context, name: "Vitamin A", dosage: "", kind: .vitamin)
        let med = Medication.create(in: context, name: "Aspirin", dosage: "81mg", kind: .medication)
        for item in [supp, vit, med] {
            DoseLog.create(in: context, medication: item, scheduledAt: Date(), status: .taken)
        }
        try context.save()

        sut.refresh()

        XCTAssertEqual(sut.medicationAdherences.map(\.kind), [.medication, .vitamin, .supplement])
    }

    func testCountsTowardAdherence_flagMatrix() throws {
        let med = Medication.create(in: context, name: "Med", dosage: "1mg", kind: .medication)
        let vit = Medication.create(in: context, name: "Vit", dosage: "1mg", kind: .vitamin)

        let scheduledMed = DoseLog.create(in: context, medication: med, scheduledAt: Date(), status: .taken)
        let prnMed = DoseLog.create(in: context, medication: med, scheduledAt: Date(), status: .taken, isAsNeeded: true)
        let scheduledVit = DoseLog.create(in: context, medication: vit, scheduledAt: Date(), status: .taken)
        let prnVit = DoseLog.create(in: context, medication: vit, scheduledAt: Date(), status: .taken, isAsNeeded: true)

        XCTAssertTrue(scheduledMed.countsTowardAdherence, "Only a scheduled medication dose is scored")
        XCTAssertFalse(prnMed.countsTowardAdherence)
        XCTAssertFalse(scheduledVit.countsTowardAdherence)
        XCTAssertFalse(prnVit.countsTowardAdherence)
    }

    func testMedicationKind_defaultsToMedicationForPreExistingRows() throws {
        // Simulates a row written before `kind` existed: attribute left at its model default.
        let med = Medication(context: context)
        med.id = UUID()
        med.name = "Legacy"
        med.dosage = "5mg"
        try context.save()

        XCTAssertEqual(med.medicationKind, .medication,
                       "Existing medications must keep counting toward adherence after the migration")
    }
}
