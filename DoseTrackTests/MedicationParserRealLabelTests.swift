// DoseTrackTests/MedicationParserRealLabelTests.swift
//
// Regression tests built from 15 annotated real-world scans (medication-scanner/IMG_58xx.jpeg),
// where the expected values are the user's own handwritten ground-truth labels.
//
// The guiding principle, taken from those annotations: **a blank field is far safer than a wrong
// one.** Across the sample the correct answer was "nothing" in 11 places, and the genuinely
// dangerous failures were all cases where the parser confidently committed a number lifted from
// the wrong part of the label — a max-daily-dose warning read as a per-unit strength, an
// ingredient breakdown chosen over the front-of-pack figure, a dosing frequency read as a pack
// count. Tests here therefore assert nil in preference to a plausible-looking guess.
import XCTest
@testable import DoseTrack

final class MedicationParserRealLabelTests: XCTestCase {

    // MARK: - Strength must never come from a maximum-dose warning
    //
    // IMG_5899, Panadeine Forte. The label carries no per-unit strength at all; the only mg figure
    // present is a safety ceiling for the whole day. Reading it as the strength produced "4000mg",
    // which would be written into the medication record as a single dose.

    func testStrength_isNotTakenFromMaximumDailyDoseWarning() {
        let lines = [
            "PANADEINE FORTE TAB",
            "(paracetamol + codeine)",
            "50 tablets",
            "Maximum 4000mg of Paracetamol containing products in a day",
        ]
        let result = MedicationParser.parse(lines: lines)
        XCTAssertNotEqual(result?.strength, "4000",
                          "A maximum-daily-dose warning must never be read as the per-unit strength")
    }

    func testStrength_isNotTakenFromDoNotExceedWarning() {
        let lines = [
            "Ibuprofen Tablets",
            "24 tablets",
            "Do not exceed 1200mg in 24 hours",
        ]
        let result = MedicationParser.parse(lines: lines)
        XCTAssertNotEqual(result?.strength, "1200",
                          "A 'do not exceed' ceiling must never be read as the per-unit strength")
    }

    // MARK: - Supply must never come from a dosing frequency
    //
    // IMG_5903 (oxycodone) reported a supply of 4, taken from "every 4 hours". IMG_5887 (Elevit)
    // reported 1, taken from "1x DAILY", while "150 Tablets" sat directly beside it.

    func testSupply_isNotTakenFromEveryNHoursFrequency() {
        let lines = [
            "Oxycodone Tablet (10)",
            "Take ONE tablet every 4 hours when necessary for pain",
        ]
        let result = MedicationParser.parse(lines: lines)
        XCTAssertNotEqual(result?.count, 4,
                          "'every 4 hours' is a frequency, not a pack count")
    }

    func testSupply_prefersPackCountOverOnceDailyMarker() {
        let lines = [
            "elevit",
            "Pre-conception & Pregnancy",
            "150 Tablets",
            "1x DAILY",
        ]
        let result = MedicationParser.parse(lines: lines)
        XCTAssertEqual(result?.count, 150,
                       "The pack count (150 Tablets) must win over the '1x DAILY' dosing marker")
    }

    // MARK: - Name must not be marketing copy, a manufacturer, or an ingredient list
    //
    // The "largest text height wins" heuristic loses to long ALL-CAPS body copy on real packaging.

    func testName_isNotAMarketingClaimLine() {
        let lines = [
            "PHARMACY MEDICINE",
            "elevit",
            "SCIENTIFICALLY FORMULATED with 19 vitamins & minerals for mum & baby",
            "150 Tablets",
        ]
        let result = MedicationParser.parse(lines: lines)
        XCTAssertNotEqual(result?.name, "SCIENTIFICALLY FORMULATED with 19 vitamins & minerals for mum & baby",
                          "A marketing claim must never be chosen as the medication name")
    }

    func testName_isNotAnIndicationSentence() {
        let lines = [
            "SLEEP RIGHT",
            "DOXYLAMINE SUCCINATE 25 mg",
            "TEMPORARY RELIEF OF INSOMNIA AND SLEEPLESSNESS",
            "20 TABLETS",
        ]
        let result = MedicationParser.parse(lines: lines)
        XCTAssertNotEqual(result?.name, "TEMPORARY RELIEF OF INSOMNIA AND SLEEPLESSNESS",
                          "An indication sentence must never be chosen as the medication name")
    }

    // MARK: - Per-dose from number words and ranges
    //
    // Eight of the fifteen scans failed here. §6b of CLAUDE.md claims number words are handled;
    // these pin down the exact real-label phrasings.

    func testPerDose_readsNumberWordOne() {
        let lines = ["Levoxine", "Take ONE tablet daily as directed by the doctor"]
        let result = MedicationParser.parse(lines: lines)
        XCTAssertEqual(result?.perDose, 1, "'Take ONE tablet' should yield 1")
    }

    func testPerDose_readsNumberWordFour() {
        let lines = ["CLONIDINE", "Take FOUR tablets at night"]
        let result = MedicationParser.parse(lines: lines)
        XCTAssertEqual(result?.perDose, 4, "'Take FOUR tablets' should yield 4")
    }

    func testPerDose_wordRangeTakesLowerBound() {
        let lines = ["PANADEINE FORTE", "Take ONE to TWO tablets before bed"]
        let result = MedicationParser.parse(lines: lines)
        XCTAssertEqual(result?.perDose, 1,
                       "A range must take the lower bound — never silently overstate the dose")
    }

    func testPerDose_numericRangeTakesLowerBound() {
        let lines = ["SLEEPRIGHT", "Take 1-2 tablets 20 minutes before bed"]
        let result = MedicationParser.parse(lines: lines)
        XCTAssertEqual(result?.perDose, 1,
                       "'1-2 tablets' must yield 1, not the upper bound 2")
    }

    func testPerDose_halfOrOneTakesTheHalfSafely() {
        // "Take a HALF or ONE tablet" — the parser stores whole units, so 1 is acceptable here,
        // but it must not invent something larger.
        let lines = ["DOZAVIT 25MG TABS", "Take a HALF or ONE tablet 30mins before sleep"]
        let result = MedicationParser.parse(lines: lines)
        if let perDose = result?.perDose {
            XCTAssertLessThanOrEqual(perDose, 1, "Must never overstate a half-or-one dose")
        }
    }

    func testPerDose_isNotTheFrequencyNumber() {
        let lines = ["Amoxicillin", "Take 1 tablet 3 times a day"]
        let result = MedicationParser.parse(lines: lines)
        XCTAssertEqual(result?.perDose, 1,
                       "The number before the form word wins, not the frequency '3 times'")
    }

    // MARK: - Strength unit fidelity
    //
    // IMG_5900, Apo-Clonidine "100 µg" was committed as "100mg" — a 1000× error and the single most
    // dangerous failure in the sample.

    func testStrength_microgramGlyphIsNotFlattenedToMilligrams() {
        let lines = ["APO-CLONIDINE", "clonidine hydrochloride 100 µg", "100 tablets"]
        let result = MedicationParser.parse(lines: lines)
        XCTAssertEqual(result?.strengthUnit, "mcg",
                       "µg must be preserved as micrograms, never flattened to mg")
    }

    func testStrength_spelledOutMicrogramsPreserved() {
        let lines = ["Levoxine", "Each tablet contains: 50 micrograms levothyroxine sodium"]
        let result = MedicationParser.parse(lines: lines)
        XCTAssertEqual(result?.strength, "50")
        XCTAssertEqual(result?.strengthUnit, "mcg")
    }

    // MARK: - Legitimately-blank fields
    //
    // The annotations marked "NO STRENGTH LISTED" / "NO SUPPLY LISTED" in 11 places. Returning
    // nothing there is the correct result, not a shortfall.

    func testStrength_blankWhenLabelCarriesNoStrength() {
        let lines = [
            "elevit",
            "Pre-conception & Pregnancy",
            "150 Tablets",
            "with 19 vitamins & minerals",
        ]
        let result = MedicationParser.parse(lines: lines)
        XCTAssertEqual(result?.hasStrength, false,
                       "No strength on the label means no strength in the result")
    }

    func testSupply_blankWhenLabelCarriesNoPackCount() {
        let lines = [
            "Levoxine",
            "levothyroxine sodium 50 micrograms",
            "AUST R 333525",
        ]
        let result = MedicationParser.parse(lines: lines)
        XCTAssertEqual(result?.hasSupply, false,
                       "No pack count on the label means no count in the result")
    }

    // MARK: - Inhaler form inference
    //
    // IMG_5902: "RILAST RAPIHALER 100/3" + "Shake well and inhale TWO doses by mouth TWICE daily"
    // produced "2 tablets". The count was right; the form was never inferred, so it fell back to
    // the default. An inhaler recorded in tablets is a plausible-looking wrong value.

    func testForm_rapihalerIsRecognisedAsInhaler() {
        let lines = [
            "RILAST RAPIHALER 100/3",
            "budesonide + formoterol",
            "Shake well and inhale TWO doses by mouth TWICE daily",
        ]
        let result = MedicationParser.parse(lines: lines)
        XCTAssertEqual(result?.form, "inhaler", "RAPIHALER must not be recorded as tablets")
        XCTAssertEqual(result?.perDose, 2, "The count itself was always correct")
    }

    /// The -haler suffix is matched by pattern, so brands beyond the one that failed are covered
    /// without having to enumerate them.
    func testForm_anyHalerSuffixDeviceIsAnInhaler() {
        for device in ["Turbuhaler", "Accuhaler", "Handihaler", "Autohaler", "Breezhaler"] {
            let result = MedicationParser.parse(lines: ["Symbicort \(device)", "200 doses"])
            XCTAssertEqual(result?.form, "inhaler", "\(device) should be an inhaler")
        }
    }

    func testForm_nonHalerInhalerDevicesRecognised() {
        for device in ["Respimat", "Ellipta", "Diskus", "Genuair"] {
            let result = MedicationParser.parse(lines: ["Spiriva \(device)", "30 doses"])
            XCTAssertEqual(result?.form, "inhaler", "\(device) should be an inhaler")
        }
    }

    func testForm_inhaleVerbAloneImpliesInhaler() {
        let lines = ["Ventolin", "Inhale 2 puffs when required"]
        let result = MedicationParser.parse(lines: lines)
        XCTAssertEqual(result?.form, "inhaler")
    }

    /// Guard against the new inhaler check being too eager — an ordinary tablet box must still
    /// resolve to "tablet".
    func testForm_ordinaryTabletBoxIsUnaffected() {
        let lines = ["Metformin", "500 mg", "100 Tablets"]
        let result = MedicationParser.parse(lines: lines)
        XCTAssertEqual(result?.form, "tablet")
    }

    func testForm_nasalSprayIsNotMisreadAsInhaler() {
        let lines = ["Nasonex", "Nasal Spray", "140 sprays"]
        let result = MedicationParser.parse(lines: lines)
        XCTAssertEqual(result?.form, "spray", "A nasal spray is not an inhaler")
    }
}
