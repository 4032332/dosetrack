// DoseTrackTests/ReportGeneratorTests.swift
import XCTest
import CoreData
import PDFKit
@testable import DoseTrack

final class ReportGeneratorTests: XCTestCase {
    func test_generatePDF_paginates_whenManyMedications() {
        let ctx = PersistenceController(inMemory: true).viewContext
        var meds: [Medication] = []
        var logs: [DoseLog] = []
        let now = Date()
        for i in 0..<40 {
            let med = Medication.create(in: ctx, name: "Med\(i)", dosage: "1")
            meds.append(med)
            // A row is only drawn (and only takes up vertical space) when the medication has
            // at least one log — see ReportGenerator's `guard !medLogs.isEmpty else { continue }`.
            logs.append(DoseLog.create(in: ctx, medication: med, scheduledAt: now, status: .taken))
        }
        let data = ReportGenerator.shared.generatePDF(
            logs: logs, medications: meds,
            dateRange: DateInterval(start: now.addingTimeInterval(-2_592_000), end: now),
            patientName: "Test"
        )
        let doc = PDFDocument(data: data)
        XCTAssertGreaterThan(doc?.pageCount ?? 0, 1, "40 medication rows should overflow onto a second page")
    }

    func test_generatePDF_singlePage_whenFewMedications() {
        let ctx = PersistenceController(inMemory: true).viewContext
        let med = Medication.create(in: ctx, name: "Metformin", dosage: "500mg")
        let now = Date()
        let log = DoseLog.create(in: ctx, medication: med, scheduledAt: now, status: .taken)
        let data = ReportGenerator.shared.generatePDF(
            logs: [log], medications: [med],
            dateRange: DateInterval(start: now.addingTimeInterval(-86400), end: now),
            patientName: "Test"
        )
        let doc = PDFDocument(data: data)
        XCTAssertEqual(doc?.pageCount, 1)
    }
}
