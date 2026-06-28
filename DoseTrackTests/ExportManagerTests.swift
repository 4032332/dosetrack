// DoseTrackTests/ExportManagerTests.swift
import XCTest
import CoreData
@testable import DoseTrack

final class ExportManagerTests: XCTestCase {

    var context: NSManagedObjectContext!
    var sut: ExportManager!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).viewContext
        sut = ExportManager.shared
    }

    override func tearDownWithError() throws {
        context = nil
    }

    // MARK: - CSV generation

    func testGenerateCSV_includesHeader() throws {
        let csv = String(data: sut.generateCSV(from: [], dateRange: fullInterval()), encoding: .utf8) ?? ""
        XCTAssertTrue(csv.hasPrefix("Date,Time,Medication,Dose,Unit,Status,Notes"))
    }

    func testGenerateCSV_oneRowPerLog() throws {
        let med = Medication.create(in: context, name: "Metformin", dosage: "500mg")
        let log1 = DoseLog.create(in: context, medication: med, scheduledAt: Date(), status: .taken)
        let log2 = DoseLog.create(in: context, medication: med, scheduledAt: Date(), status: .skipped)
        try context.save()

        let csv = String(data: sut.generateCSV(from: [log1, log2], dateRange: fullInterval()), encoding: .utf8) ?? ""
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.count, 3) // header + 2 rows
    }

    func testGenerateCSV_containsMedicationName() throws {
        let med = Medication.create(in: context, name: "Lisinopril", dosage: "10mg")
        let log = DoseLog.create(in: context, medication: med, scheduledAt: Date(), status: .taken)
        try context.save()

        let csv = String(data: sut.generateCSV(from: [log], dateRange: fullInterval()), encoding: .utf8) ?? ""
        XCTAssertTrue(csv.contains("Lisinopril"))
        XCTAssertTrue(csv.contains("10mg"))
    }

    func testGenerateCSV_escapesCommasInName() throws {
        let med = Medication.create(in: context, name: "Iron, Ferrous", dosage: "325mg")
        let log = DoseLog.create(in: context, medication: med, scheduledAt: Date(), status: .taken)
        try context.save()

        let csv = String(data: sut.generateCSV(from: [log], dateRange: fullInterval()), encoding: .utf8) ?? ""
        XCTAssertTrue(csv.contains("\"Iron, Ferrous\""), "Commas in names must be quoted")
    }

    func testGenerateCSV_filtersLogsOutsideDateRange() throws {
        let med = Medication.create(in: context, name: "Aspirin", dosage: "81mg")
        let oldDate = Date(timeIntervalSinceNow: -86400 * 30)
        let log = DoseLog.create(in: context, medication: med, scheduledAt: oldDate, status: .taken)
        try context.save()

        // Range covers only today
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        let range = DateInterval(start: today, end: tomorrow)

        let csv = String(data: sut.generateCSV(from: [log], dateRange: range), encoding: .utf8) ?? ""
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.count, 1, "Only header row — old log filtered out")
    }

    func testGenerateCSV_statusLabels() throws {
        let med = Medication.create(in: context, name: "Test", dosage: "1mg")
        let log = DoseLog.create(in: context, medication: med, scheduledAt: Date(), status: .missed)
        try context.save()

        let csv = String(data: sut.generateCSV(from: [log], dateRange: fullInterval()), encoding: .utf8) ?? ""
        XCTAssertTrue(csv.contains("Missed"), "Status should use displayName")
    }

    // MARK: - fetchAllLogs

    func testFetchAllLogs_returnsLogsInInterval() throws {
        let med = Medication.create(in: context, name: "Test", dosage: "5mg")
        let today = Date()
        let yesterday = Date(timeIntervalSinceNow: -86400)
        let future = Date(timeIntervalSinceNow: 86400 * 10)

        DoseLog.create(in: context, medication: med, scheduledAt: today, status: .taken)
        DoseLog.create(in: context, medication: med, scheduledAt: yesterday, status: .taken)
        DoseLog.create(in: context, medication: med, scheduledAt: future, status: .taken)
        try context.save()

        let start = Calendar.current.date(byAdding: .day, value: -2, to: today)!
        let end = Calendar.current.date(byAdding: .day, value: 2, to: today)!
        let interval = DateInterval(start: start, end: end)

        let logs = sut.fetchAllLogs(context: context, in: interval)
        XCTAssertEqual(logs.count, 2, "Only today + yesterday should be in range")
    }

    // MARK: - Helpers

    private func fullInterval() -> DateInterval {
        DateInterval(
            start: Date(timeIntervalSinceNow: -86400 * 365),
            end: Date(timeIntervalSinceNow: 86400)
        )
    }
}
