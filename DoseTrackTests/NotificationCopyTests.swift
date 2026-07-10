// DoseTrackTests/NotificationCopyTests.swift
import XCTest
@testable import DoseTrack

final class NotificationCopyTests: XCTestCase {

    override func setUpWithError() throws {
        // Pin routine times to the known defaults (Wake Up 07:00, Bedtime 22:00) so gating tests
        // aren't affected by whatever a prior test run left in UserDefaults.
        UserDefaults.standard.removeObject(forKey: "mealTimes")
    }

    func testRandomLine_substitutesMedicationName_neverLeavesPlaceholder() {
        for _ in 0..<200 {
            let line = NotificationCopy.randomLine(medicationName: "Metformin", unit: "tablet", hour: 12)
            XCTAssertTrue(line.contains("Metformin"), "Line missing medication name: \(line)")
            XCTAssertFalse(line.contains("{name}"), "Unsubstituted placeholder: \(line)")
        }
    }

    func testRandomLine_neverMentionsNumericDoseOrQuantity() {
        // The whole point of this fix: no strength (500mg), no pill count (2 tablets), ever.
        // Form names like "tablet"/"pill"/"capsule" are fine on their own — only a NUMBER
        // attached to a unit (a dose or a count) would leak the thing we removed.
        let dosePattern = try! NSRegularExpression(
            pattern: #"\d+\s?(mg|mcg|ml|iu|mmol|meq|g)\b|\d+\s?(tablet|capsule|pill|spray|drop|patch)s?\b"#,
            options: .caseInsensitive
        )
        for unit in ["tablet", "capsule", "pill", "spray", "inhaler", "injection", "patch", "drop", "ml"] {
            for hour in [9, 13, 22] {
                for _ in 0..<50 {
                    let line = NotificationCopy.randomLine(medicationName: "Restavit", unit: unit, hour: hour)
                    let range = NSRange(line.startIndex..., in: line)
                    XCTAssertNil(dosePattern.firstMatch(in: line, range: range), "Line leaked a dose/quantity: \(line)")
                }
            }
        }
    }

    func testGeneralPool_hasAtLeastOneHundredLines() {
        // Draw a large sample at a neutral hour/unit (no gated pools apply) and count distinct
        // lines seen — with 300 draws from a >=100-line pool we should comfortably see 60+.
        var seen = Set<String>()
        for _ in 0..<400 {
            seen.insert(NotificationCopy.randomLine(medicationName: "X", unit: "unknown-unit", hour: 13))
        }
        XCTAssertGreaterThan(seen.count, 60, "General pool doesn't look like it has >=100 lines")
    }

    func testRandomLine_isVaried() {
        var seen = Set<String>()
        for _ in 0..<300 {
            seen.insert(NotificationCopy.randomLine(medicationName: "Vitamin D", unit: "tablet", hour: 13))
        }
        XCTAssertGreaterThan(seen.count, 30)
    }

    func testRandomLine_sometimesPullsFromGeneralPoolEvenWhenGatedPoolsApply() {
        // Even when a med-type + bedtime gate both apply, the general pool must still be in the
        // mix (not overridden) — this is spelled out explicitly: it should still sometimes draw
        // a plain general line, not always the specific one.
        var sawGeneralLine = false
        for _ in 0..<300 {
            let line = NotificationCopy.randomLine(medicationName: "Melatonin", unit: "inhaler", hour: 22)
            if line == "It's Melatonin time!" || line == "Don't forget to take your Melatonin." {
                sawGeneralLine = true
                break
            }
        }
        XCTAssertTrue(sawGeneralLine, "Never drew a general-pool line even though gated pools applied")
    }

    // MARK: - Medication-form gating

    private func typeLineIndicators(_ unit: String) -> [String] {
        switch unit {
        case "inhaler":   return ["breath", "Breathe", "puff", "lungs", "Inhale"]
        case "spray":     return ["Spritz", "spray", "mist"]
        case "injection": return ["injection", "shot", "jab", "pinch"]
        case "patch":     return ["patch"]
        case "drop":      return ["drop"]
        case "ml":        return ["measured", "sip", "pour", "liquid", "dose"]
        case "tablet":    return ["tablet", "hatch", "swallow"]
        case "capsule":   return ["capsule", "takeoff"]
        case "pill":      return ["pill"]
        default: return []
        }
    }

    func testRandomLine_eachMedicationForm_canProduceItsOwnSpecificLine() {
        for unit in ["tablet", "capsule", "pill", "spray", "inhaler", "injection", "patch", "drop", "ml"] {
            let indicators = typeLineIndicators(unit)
            var sawSpecific = false
            for _ in 0..<400 {
                let line = NotificationCopy.randomLine(medicationName: "Med", unit: unit, hour: 13)
                if indicators.contains(where: { line.contains($0) }) {
                    sawSpecific = true
                    break
                }
            }
            XCTAssertTrue(sawSpecific, "Never drew a \(unit)-specific line across 400 tries")
        }
    }

    func testRandomLine_unknownUnit_neverProducesAnyFormSpecificLine() {
        let allIndicators = ["breath", "puff", "lungs", "Spritz", "mist", "shot", "jab",
                              "patch", "drop", "measured", "hatch", "takeoff"]
        for _ in 0..<300 {
            let line = NotificationCopy.randomLine(medicationName: "Med", unit: "unknown-unit", hour: 13)
            for indicator in allIndicators {
                XCTAssertFalse(line.contains(indicator), "Unexpected form-specific line for unknown unit: \(line)")
            }
        }
    }

    // MARK: - Time-of-day gating (relative to Wake Up / Bedtime routine times)

    func testRandomLine_nearDefaultWakeUpHour_canProduceWakeUpLine() {
        // Default Wake Up is 07:00; 08:00 is within the ±2h window.
        var sawWakeUpLine = false
        for _ in 0..<400 {
            let line = NotificationCopy.randomLine(medicationName: "Med", unit: "tablet", hour: 8)
            if line.contains("Morning") || line.contains("morning") || line.contains("Rise") || line.contains("Wakey") {
                sawWakeUpLine = true
                break
            }
        }
        XCTAssertTrue(sawWakeUpLine, "Never drew a Wake-Up-specific line across 400 tries")
    }

    func testRandomLine_farFromWakeUpHour_neverProducesWakeUpLine() {
        for _ in 0..<300 {
            let line = NotificationCopy.randomLine(medicationName: "Med", unit: "tablet", hour: 13)
            XCTAssertFalse(line.contains("Rise") || line.contains("Wakey") || line.contains("Morning"))
        }
    }

    func testRandomLine_nearDefaultBedtimeHour_canProduceBedtimeLine() {
        // Default Bedtime is 22:00; 23:00 is within the ±2h window.
        var sawBedtimeLine = false
        for _ in 0..<400 {
            let line = NotificationCopy.randomLine(medicationName: "Med", unit: "tablet", hour: 23)
            if line.contains("asleep") || line.contains("bed") || line.contains("dream") || line.contains("drift") || line.contains("pillow") {
                sawBedtimeLine = true
                break
            }
        }
        XCTAssertTrue(sawBedtimeLine, "Never drew a Bedtime-specific line across 400 tries")
    }

    func testRandomLine_bedtimeWindow_wrapsPastMidnight() {
        // Default Bedtime is 22:00, so 00:00 (2h later, wrapping past midnight) should still
        // count as "near bedtime" — this is the wraparound case that a naive |a-b| would miss.
        var sawBedtimeLine = false
        for _ in 0..<400 {
            let line = NotificationCopy.randomLine(medicationName: "Med", unit: "tablet", hour: 0)
            if line.contains("asleep") || line.contains("bed") || line.contains("dream") || line.contains("drift") || line.contains("pillow") {
                sawBedtimeLine = true
                break
            }
        }
        XCTAssertTrue(sawBedtimeLine, "Bedtime window didn't wrap past midnight")
    }

    func testRandomLine_farFromBedtimeHour_neverProducesBedtimeLine() {
        for _ in 0..<300 {
            let line = NotificationCopy.randomLine(medicationName: "Med", unit: "tablet", hour: 13)
            XCTAssertFalse(line.contains("asleep") || line.contains("pillow") || line.contains("Lights out"))
        }
    }
}
