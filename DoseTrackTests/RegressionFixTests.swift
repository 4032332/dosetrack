// DoseTrackTests/RegressionFixTests.swift
// Regression guards for bugs that were reported repeatedly across multiple patches.
import XCTest
import CoreData
@testable import DoseTrack

final class DOBFormatTests: XCTestCase {

    /// The core DOB "won't save" bug: `patient_dob` is a Postgres `date`, so it comes back as
    /// "yyyy-MM-dd". The old code parsed that with ISO8601DateFormatter (nil for date-only) and
    /// then wrote `?? 0`, zeroing the DOB on every pull. Parsing a date-only string must succeed.
    func testTimestamp_parsesDateOnlyString() {
        XCTAssertNotNil(DOBFormat.timestamp(from: "1992-07-10"),
                        "Date-only 'yyyy-MM-dd' (Postgres date column) must parse — this is the DOB revert bug.")
    }

    func testTimestamp_parsesLegacyFullISO8601() {
        XCTAssertNotNil(DOBFormat.timestamp(from: "1992-07-10T00:00:00Z"),
                        "Legacy full-timestamp values must still parse for backward compatibility.")
    }

    func testTimestamp_returnsNilForGarbage_ratherThanZero() {
        XCTAssertNil(DOBFormat.timestamp(from: "not a date"),
                     "Unparseable input must return nil so applySettings leaves the local value alone, not wipe it.")
    }

    func testRoundTrip_preservesCalendarDay() {
        let cal = Calendar(identifier: .gregorian)
        var comps = DateComponents(); comps.year = 1988; comps.month = 3; comps.day = 4
        let original = cal.date(from: comps)!
        let string = DOBFormat.string(from: original)
        let ts = DOBFormat.timestamp(from: string)!
        let restored = Date(timeIntervalSince1970: ts)
        XCTAssertEqual(cal.component(.year, from: restored), 1988)
        XCTAssertEqual(cal.component(.month, from: restored), 3)
        XCTAssertEqual(cal.component(.day, from: restored), 4)
    }
}

@MainActor
final class RefillWarningTests: XCTestCase {

    private var context: NSManagedObjectContext!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).viewContext
    }

    override func tearDownWithError() throws { context = nil }

    /// Reported bug: a medication at 0 supply showed no warning. The old guard `currentCount > 0`
    /// hid the flag at exactly 0 — the most urgent (out of stock) state.
    func testWarns_whenOutOfStock() throws {
        let med = Medication.create(in: context, name: "Restavit", dosage: "10mg")
        med.currentCount = 0
        med.refillThreshold = 7
        med.totalDosesPerDay = 1
        XCTAssertTrue(med.isRefillWarning, "0 supply on a scheduled med must warn (out of stock).")
    }

    func testWarns_whenLow() throws {
        let med = Medication.create(in: context, name: "Melatonin", dosage: "2mg")
        med.currentCount = 3
        med.refillThreshold = 7
        med.totalDosesPerDay = 1
        XCTAssertTrue(med.isRefillWarning)
    }

    func testNoWarning_whenWellStocked() throws {
        let med = Medication.create(in: context, name: "Nexium", dosage: "20mg")
        med.currentCount = 30
        med.refillThreshold = 7
        med.totalDosesPerDay = 1
        XCTAssertFalse(med.isRefillWarning)
    }

    /// A med not consumed on a schedule (no doses/day) shouldn't nag about supply.
    func testNoWarning_whenNotScheduled() throws {
        let med = Medication.create(in: context, name: "As Needed", dosage: "5mg")
        med.currentCount = 0
        med.refillThreshold = 7
        med.totalDosesPerDay = 0
        XCTAssertFalse(med.isRefillWarning)
    }
}
