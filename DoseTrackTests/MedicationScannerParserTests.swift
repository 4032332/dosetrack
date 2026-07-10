// DoseTrackTests/MedicationScannerParserTests.swift
import XCTest
@testable import DoseTrack

final class MedicationScannerParserTests: XCTestCase {

    func testParse_typicalAustralianBoxLayout() {
        // Roughly what Vision OCR returns for a real PBS-style medication box, line by line,
        // top to bottom, as it would actually appear (brand name prominent, then strength,
        // then count, then regulatory/warning boilerplate).
        let lines = [
            "Metformin",
            "Sandoz",
            "500 mg",
            "100 Tablets",
            "AUST R 123456",
            "Keep out of reach of children",
            "Store below 25°C"
        ]
        let result = MedicationParser.parse(lines: lines)
        XCTAssertNotNil(result, "Should extract details from a clean, typical box layout")
        XCTAssertEqual(result?.name, "Metformin")
        XCTAssertEqual(result?.strength, "500")
        XCTAssertEqual(result?.strengthUnit, "mg")
        XCTAssertEqual(result?.count, 100)
    }

    func testParse_allCapsBoxText() {
        // Many real boxes render the brand name in all-caps, not title case.
        let lines = [
            "VYVANSE",
            "LISDEXAMFETAMINE DIMESYLATE",
            "70 mg",
            "28 Capsules"
        ]
        let result = MedicationParser.parse(lines: lines)
        XCTAssertNotNil(result, "All-caps brand name should still be detected as a name candidate")
    }

    func testParse_noClearNameLine_returnsNil() {
        // A photo of just the dosage instructions / warnings panel, no product name visible.
        let lines = [
            "Take one tablet daily",
            "Do not exceed recommended dose",
            "Keep out of reach of children",
            "Consult your doctor or pharmacist"
        ]
        let result = MedicationParser.parse(lines: lines)
        XCTAssertNil(result, "Should not fabricate a name when every line is boilerplate")
    }

    func testParse_nameAndStrengthOnSameLine_stripsStrengthKeepsName() {
        // OCR very commonly merges the brand name and strength onto one line.
        let lines = ["Nurofen 200mg", "24 Tablets"]
        let result = MedicationParser.parse(lines: lines)
        XCTAssertEqual(result?.name, "Nurofen")
        XCTAssertEqual(result?.strength, "200")
        XCTAssertEqual(result?.strengthUnit, "mg")
        XCTAssertEqual(result?.count, 24)
    }

    func testParse_strengthWithoutSpaceAndMicrograms() {
        let lines = ["Levothyroxine", "100microgram", "50 tablets"]
        let result = MedicationParser.parse(lines: lines)
        XCTAssertEqual(result?.name, "Levothyroxine")
        XCTAssertEqual(result?.strength, "100")
        XCTAssertEqual(result?.strengthUnit, "mcg")
    }

    func testParse_liquidStrengthPerVolume() {
        let lines = ["Amoxil", "250mg/5mL", "Oral Liquid"]
        let result = MedicationParser.parse(lines: lines)
        XCTAssertEqual(result?.name, "Amoxil")
        XCTAssertEqual(result?.strength, "250")
        XCTAssertEqual(result?.strengthUnit, "mg/5ml")
        XCTAssertEqual(result?.form, "ml")
    }

    func testParse_countWithApostropheS() {
        // "Panadol 500mg 100's" — the "100's" pack-size shorthand.
        let lines = ["Panadol", "500 mg", "100's"]
        let result = MedicationParser.parse(lines: lines)
        XCTAssertEqual(result?.name, "Panadol")
        XCTAssertEqual(result?.count, 100)
    }

    func testParse_stripsTrademarkSymbolFromName() {
        let lines = ["Claratyne®", "10 mg", "30 Tablets"]
        let result = MedicationParser.parse(lines: lines)
        XCTAssertEqual(result?.name, "Claratyne")
    }

    func testParse_pureCountAndStrengthLines_areNotMistakenForName() {
        // Every non-boilerplate line is just numbers+units → nothing left after stripping → nil.
        let lines = ["500 mg", "100 Tablets", "AUST R 55555"]
        let result = MedicationParser.parse(lines: lines)
        XCTAssertNil(result)
    }
}
