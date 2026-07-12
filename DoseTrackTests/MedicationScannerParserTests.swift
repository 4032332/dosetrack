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

    // MARK: - Supply quantity (QTY markers)

    func testParse_explicitQTYMarker_isSupply() {
        let lines = ["Vyvanse", "50 mg", "QTY: 30", "Take 1 capsule each morning"]
        let result = MedicationParser.parse(lines: lines)
        XCTAssertEqual(result?.name, "Vyvanse")
        XCTAssertEqual(result?.strength, "50")
        XCTAssertEqual(result?.count, 30)
    }

    func testParse_packOfN_isSupply() {
        let lines = ["Endep", "10 mg", "Pack of 50"]
        XCTAssertEqual(MedicationParser.parse(lines: lines)?.count, 50)
    }

    func testParse_instructionTabletCount_isNotMistakenForSupply() {
        // "Take 1 tablet..." must NOT set supply to 1; the real supply is the pack line.
        let lines = ["Metformin", "500mg", "100 Tablets", "Take 1 tablet 3 times a day"]
        let result = MedicationParser.parse(lines: lines)
        XCTAssertEqual(result?.count, 100, "Supply should come from the pack line, not the instruction")
    }

    // MARK: - Per-dose from instructions

    func testParse_perDose_digit() {
        let lines = ["Panadol", "500mg", "20 Tablets", "Take 2 tablets with food"]
        let result = MedicationParser.parse(lines: lines)
        XCTAssertEqual(result?.perDose, 2)
        XCTAssertEqual(result?.count, 20)
    }

    func testParse_perDose_numberWord() {
        let lines = ["Amoxil", "500mg", "Take ONE capsule three times daily"]
        XCTAssertEqual(MedicationParser.parse(lines: lines)?.perDose, 1)
    }

    func testParse_perDose_ignoresFrequencyNumber() {
        // The classic trap: "1 tablet, 3 times" → per dose is 1, NOT 3.
        let lines = ["Sertraline", "50mg", "Take 1 tablet 3 times per day"]
        XCTAssertEqual(MedicationParser.parse(lines: lines)?.perDose, 1)
    }

    func testParse_perDose_range_takesLowerNumber() {
        let lines = ["Ibuprofen", "200mg", "Take 1 to 2 tablets every 4 hours"]
        XCTAssertEqual(MedicationParser.parse(lines: lines)?.perDose, 1)
    }

    func testParse_perDose_absentWhenNoInstruction() {
        let lines = ["Metformin", "500 mg", "100 Tablets"]
        XCTAssertEqual(MedicationParser.parse(lines: lines)?.perDose, 0)
    }

    func testParse_fullPharmacyLabel_allFields() {
        // A realistic dispensed-pharmacy label: brand, generic, strength, QTY, and directions.
        let lines = [
            "VYVANSE",
            "Lisdexamfetamine",
            "50 mg",
            "Qty: 30 capsules",
            "Take 1 capsule in the morning",
        ]
        let result = MedicationParser.parse(lines: lines)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.strength, "50")
        XCTAssertEqual(result?.strengthUnit, "mg")
        XCTAssertEqual(result?.count, 30)
        XCTAssertEqual(result?.perDose, 1)
        XCTAssertEqual(result?.form, "capsule")
        XCTAssertNotNil(result?.instructions)
    }

    // MARK: - Real pharmacy dispensing lines (from training photos, IMG_5519–5535)
    // These lines are the "QTY NAME STRENGTH FORM (alt)" (or name-first) format printed on the
    // Chemist Warehouse / TerryWhite dispensing label — the highest-confidence single source.

    func testDispensing_minipress_qtyFirst() {
        // "100 MINIPRESS 1MG TAB (prazosin)" — leading integer is the pack quantity.
        let r = MedicationParser.parse(lines: ["100 MINIPRESS 1MG TAB ( prazosin )"])
        XCTAssertEqual(r?.count, 100)
        XCTAssertEqual(r?.strength, "1")
        XCTAssertEqual(r?.strengthUnit, "mg")
    }

    func testDispensing_meloxicam_nameFirstTrailingQty() {
        // "MELOXICAM TABLETS 15mg 30 (MELOXICAM (SANDOZ))" — qty trails the strength.
        let r = MedicationParser.parse(lines: ["MELOXICAM TABLETS 15mg 30 ( MELOXICAM (SANDOZ) )"])
        XCTAssertEqual(r?.count, 30)
        XCTAssertEqual(r?.strength, "15")
    }

    func testDispensing_vyvanse_bottleLine() {
        let r = MedicationParser.parse(lines: ["30 VYVANSE 70MG CAP ( lisdexamfetamine )"])
        XCTAssertEqual(r?.count, 30)
        XCTAssertEqual(r?.strength, "70")
    }

    func testDispensing_clonidine_micrograms() {
        // µg glyph must be read as micrograms, and the pack integer (200) taken, not the strength.
        let r = MedicationParser.parse(lines: ["APO-CLONIDINE", "clonidine hydrochloride", "100 µg", "100 TABLETS"])
        XCTAssertEqual(r?.strengthUnit, "mcg")
        XCTAssertEqual(r?.strength, "100")
    }

    func testDispensing_ignoresPackOfMarker() {
        // "Pack 1 of 2" must never be read as the quantity; the real qty leads the line.
        let r = MedicationParser.parse(lines: [
            "200 CLONIDINE (APO) 100mcg TAB ( clonidine )",
            "Take FOUR tablets at night",
            "Pack 1 of 2"
        ])
        XCTAssertEqual(r?.count, 200)
        XCTAssertEqual(r?.perDose, 4, "FOUR tablets → 4 per dose")
    }

    func testStrength_ignoresTitrationDecoyNumbers() {
        // Minipress titration instruction is full of mg numbers that are NOT the strength.
        let r = MedicationParser.parse(lines: [
            "100 MINIPRESS 1MG TAB ( prazosin )",
            "Take a HALF tablet at night, Every week increase the dose by 0.5mg until reaching 4mg"
        ])
        XCTAssertEqual(r?.strength, "1", "Strength must come from the name line, not the titration text")
        XCTAssertEqual(r?.strengthUnit, "mg")
    }

    // MARK: - Live-feedback regressions (IMG_5541–5544): full accumulations with all the noise

    func testFeedback_melatonin_nameFromParenthetical_qtyNotPrice() {
        // 5541/5544: scanner had picked "LAST REPEAT FOR FURTHER…" as name and "99" (from $44.99)
        // as supply. Correct: Melatonin, 60.
        let lines = [
            "PRESCRIPTION ONLY MEDICINE",
            "LAST REPEAT FOR FURTHER REPEATS A NEW PRESCRIPTION IS NECESSARY",
            "60 DOZATIN 2MG MR TAB ( Melatonin )",
            "Take ONE to TWO tablets Before bed. Swallow whole.",
            "MR ROBERT BROWN",
            "10/07/26 1621357 SS 0 Repeats Left",
            "DR R RAMPERSAD $44.99 Pack 2 of 2",
            "Chemist Warehouse Westfield North Lakes East",
        ]
        let r = MedicationParser.parse(lines: lines)
        XCTAssertEqual(r?.name, "Melatonin")
        XCTAssertEqual(r?.strength, "2")
        XCTAssertEqual(r?.count, 60, "Supply must be 60, not 99 (that's the $44.99 price)")
    }

    func testFeedback_minipress_nameNotPharmacy() {
        // 5542: scanner had picked "CHEMIST WAREHOUSE" as name. Correct: prazosin/Minipress.
        let lines = [
            "PRESCRIPTION ONLY MEDICINE",
            "100 MINIPRESS 1MG TAB ( prazosin )",
            "Take a HALF tablet at night, Every week increase the dose by 0.5mg until reaching 4mg",
            "MR ROBERT BROWN",
            "Chemist Warehouse Northlakes Home Co.",
            "100 TABLETS",
        ]
        let r = MedicationParser.parse(lines: lines)
        XCTAssertEqual(r?.name, "prazosin")
        XCTAssertNotEqual(r?.name, "CHEMIST WAREHOUSE")
        XCTAssertEqual(r?.count, 100)
    }

    func testFeedback_meloxicam_nameNotPatientLine() {
        // 5543: scanner had picked "MR ROBERT BROWN 28/04/26 Dr…" as name. Correct: Meloxicam.
        let lines = [
            "Meloxicam Sandoz",
            "MELOXICAM TABLETS 15mg 30 ( MELOXICAM (SANDOZ) )",
            "Take ONE tablet daily with food as directed by the doctor",
            "MR ROBERT BROWN 28/04/26 Dr Ramesh",
            "TerryWhite Chemmart Kippa-Ring",
            "[Full Cost $18.00]",
        ]
        let r = MedicationParser.parse(lines: lines)
        XCTAssertEqual(r?.name, "MELOXICAM")
        XCTAssertEqual(r?.strength, "15")
        XCTAssertEqual(r?.count, 30)
        XCTAssertEqual(r?.perDose, 1)
    }

    func testStrength_notTakenFromLiteralDoseLabel() {
        // "DOSE: TO BE TAKEN AS DIRECTED" has no number — must not crash or invent a strength.
        let r = MedicationParser.parse(lines: [
            "Minipress",
            "1 mg prazosin",
            "DOSE: TO BE TAKEN AS DIRECTED BY THE PHYSICIAN",
            "100 TABLETS"
        ])
        XCTAssertEqual(r?.strength, "1")
        XCTAssertEqual(r?.count, 100)
    }
}
