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
}
