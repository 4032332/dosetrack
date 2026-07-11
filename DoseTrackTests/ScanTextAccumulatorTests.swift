// DoseTrackTests/ScanTextAccumulatorTests.swift
// Verifies the cross-frame text accumulation that lets the live scanner read a wrapped
// (cylindrical bottle) label — the live camera UI itself can't run in tests, but this is the
// logic that makes the rotate-to-read behaviour work, so it's the important part to cover.
import XCTest
@testable import DoseTrack

final class ScanTextAccumulatorTests: XCTestCase {

    func test_dedupesSameLineAcrossFrames() {
        var acc = ScanTextAccumulator()
        acc.add(text: "Metformin", height: 0.2)
        acc.add(text: "metformin", height: 0.2)   // different case, same line
        acc.add(text: "  Metformin ", height: 0.2) // extra whitespace, same line
        XCTAssertEqual(acc.lines.count, 1)
    }

    func test_sameLineAcrossFrames_keepsMaxHeightSeen() {
        // The same line recognised at different sizes across frames must retain the GREATEST
        // height — that's what keeps the name-by-height heuristic working even if the name was
        // only captured large on one earlier frame (e.g. before the user rotated past it).
        var acc = ScanTextAccumulator()
        acc.add(text: "Vyvanse", height: 0.10)
        acc.add(text: "Vyvanse", height: 0.30)
        acc.add(text: "vyvanse", height: 0.05)   // same line (different case), smaller
        XCTAssertEqual(acc.lines.count, 1)
        XCTAssertEqual(acc.lines.first?.heightFraction, 0.30)
    }

    func test_rotatingBottle_accumulatesAllFieldsFromSeparateFrames() {
        // Simulate a cylindrical bottle: no single frame shows the whole wrapped label, so each
        // field arrives on a different frame as the user rotates it. The accumulation must end up
        // holding everything, and the parser must then extract all fields.
        var acc = ScanTextAccumulator()
        // Frame 1 — front of the label
        acc.add(text: "Sertraline", height: 0.28)
        acc.add(text: "50 mg", height: 0.12)
        // Frame 2 — rotated; front text now off-frame, side text visible
        acc.add(text: "Qty: 30 tablets", height: 0.10)
        // Frame 3 — rotated further; directions panel
        acc.add(text: "Take 1 tablet twice a day", height: 0.09)

        let result = MedicationParser.parse(lines: acc.lines)
        XCTAssertEqual(result?.name, "Sertraline")
        XCTAssertEqual(result?.strength, "50")
        XCTAssertEqual(result?.count, 30)
        XCTAssertEqual(result?.perDose, 1)
    }

    func test_removeAll_clears() {
        var acc = ScanTextAccumulator()
        acc.add(text: "Panadol", height: 0.2)
        acc.removeAll()
        XCTAssertTrue(acc.lines.isEmpty)
    }

    func test_respectsCap() {
        var acc = ScanTextAccumulator(cap: 3)
        for i in 0..<10 { acc.add(text: "line \(i)", height: 0.1) }
        XCTAssertEqual(acc.lines.count, 3)
    }

    func test_ignoresBlankText() {
        var acc = ScanTextAccumulator()
        acc.add(text: "   ", height: 0.2)
        acc.add(text: "", height: 0.2)
        XCTAssertTrue(acc.lines.isEmpty)
    }
}
