// DoseTrackTests/NotificationCopyTests.swift
import XCTest
@testable import DoseTrack

final class NotificationCopyTests: XCTestCase {

    func testRandomLine_substitutesMedicationName_neverLeavesPlaceholder() {
        for _ in 0..<200 {
            let line = NotificationCopy.randomLine(medicationName: "Metformin", unit: "tablet", hour: 9)
            XCTAssertTrue(line.contains("Metformin"), "Line missing medication name: \(line)")
            XCTAssertFalse(line.contains("{name}"), "Unsubstituted placeholder: \(line)")
        }
    }

    func testRandomLine_neverMentionsDoseOrQuantity() {
        // The whole point of this fix: no strength, no pill count, ever.
        let forbidden = ["mg", "mcg", "ml", " tablet", " tablets", " capsule", " capsules", " pill", " pills"]
        for _ in 0..<200 {
            let line = NotificationCopy.randomLine(medicationName: "Restavit", unit: "tablet", hour: 14).lowercased()
            for word in forbidden {
                XCTAssertFalse(line.contains(word), "Line leaked dose info (\(word)): \(line)")
            }
        }
    }

    func testRandomLine_isVaried() {
        // Over many draws from a ~40-line pool we should see a good number of distinct lines,
        // not the same handful repeating — this is the "fun, not robotic" requirement.
        var seen = Set<String>()
        for _ in 0..<300 {
            seen.insert(NotificationCopy.randomLine(medicationName: "Vitamin D", unit: "tablet", hour: 10))
        }
        XCTAssertGreaterThan(seen.count, 15)
    }

    func testRandomLine_daytimeInhaler_canProduceInhalerSpecificLine() {
        var sawInhalerLine = false
        for _ in 0..<300 {
            let line = NotificationCopy.randomLine(medicationName: "Ventolin", unit: "inhaler", hour: 10)
            if line.contains("breath") || line.contains("Breathe") || line.contains("puff") || line.contains("lungs") || line.contains("Inhale") {
                sawInhalerLine = true
                break
            }
        }
        XCTAssertTrue(sawInhalerLine, "Never drew an inhaler-specific line across 300 tries")
    }

    func testRandomLine_nonInhalerNeverProducesInhalerSpecificLine() {
        for _ in 0..<300 {
            let line = NotificationCopy.randomLine(medicationName: "Metformin", unit: "tablet", hour: 10)
            XCTAssertFalse(line.contains("breath") || line.contains("puff") || line.contains("lungs"))
        }
    }

    func testRandomLine_bedtimeSchedule_canProduceBedtimeSpecificLine() {
        var sawBedtimeLine = false
        for _ in 0..<300 {
            let line = NotificationCopy.randomLine(medicationName: "Melatonin", unit: "tablet", hour: 22)
            if line.contains("asleep") || line.contains("bed") || line.contains("dreams") || line.contains("drift") || line.contains("Lights out") || line.contains("Tuck") {
                sawBedtimeLine = true
                break
            }
        }
        XCTAssertTrue(sawBedtimeLine, "Never drew a bedtime-specific line across 300 tries")
    }

    func testRandomLine_middayNeverProducesBedtimeSpecificLine() {
        for _ in 0..<300 {
            let line = NotificationCopy.randomLine(medicationName: "Melatonin", unit: "tablet", hour: 13)
            XCTAssertFalse(line.contains("asleep") || line.contains("Lights out") || line.contains("Tuck"))
        }
    }
}
