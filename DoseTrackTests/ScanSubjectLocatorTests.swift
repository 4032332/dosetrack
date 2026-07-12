// DoseTrackTests/ScanSubjectLocatorTests.swift
import XCTest
import CoreGraphics
@testable import DoseTrack

final class ScanSubjectLocatorTests: XCTestCase {

    private func item(_ text: String, _ x: CGFloat, _ y: CGFloat, w: CGFloat = 100, h: CGFloat = 20, hf: CGFloat = 0) -> ScanSubjectLocator.Item {
        ScanSubjectLocator.Item(text: text, rect: CGRect(x: x, y: y, width: w, height: h), heightFraction: hf)
    }

    func test_empty_returnsNoRegion() {
        let r = ScanSubjectLocator.locate([])
        XCTAssertNil(r.region)
        XCTAssertTrue(r.memberIndices.isEmpty)
    }

    func test_locksOntoDispensingLabel_excludesDistantBackgroundText() {
        // A tight label cluster near the top, plus a lone background word far away.
        let items = [
            item("100 MINIPRESS 1MG TAB (prazosin)", 40, 100, w: 220),  // 0 signature
            item("Take a HALF tablet at night", 40, 124, w: 200),       // 1 signature (instruction)
            item("MR ROBERT BROWN", 40, 150, w: 160),                   // 2 near → member (on label)
            item("Listerine", 40, 600, w: 90),                          // 3 far background → excluded
        ]
        let r = ScanSubjectLocator.locate(items)
        XCTAssertNotNil(r.region)
        XCTAssertTrue(r.memberIndices.contains(0))
        XCTAssertTrue(r.memberIndices.contains(1))
        XCTAssertFalse(r.memberIndices.contains(3), "Distant background text must be excluded")
    }

    func test_noDispensingLabel_fallsBackToLargestTextPanel() {
        // OTC box: no strength/form/instruction lines. Locks onto the brand block (tallest text)
        // and its neighbours, excluding a distant background item.
        let items = [
            item("PRESCRIPTION ONLY MEDICINE", 40, 60, w: 260, h: 16, hf: 0.03),
            item("Panadeine Forte", 40, 90, w: 240, h: 40, hf: 0.10),   // 1 tallest = brand seed
            item("paracetamol", 40, 135, w: 180, h: 18, hf: 0.04),      // 2 near → member
            item("flowers", 40, 700, w: 80, h: 16, hf: 0.03),           // 3 far → excluded
        ]
        let r = ScanSubjectLocator.locate(items)
        XCTAssertNotNil(r.region)
        XCTAssertTrue(r.memberIndices.contains(1))
        XCTAssertTrue(r.memberIndices.contains(2))
        XCTAssertFalse(r.memberIndices.contains(3))
    }

    func test_signatureClassifier() {
        XCTAssertTrue(ScanSubjectLocator.isDispensingSignature("100 MINIPRESS 1MG TAB"))
        XCTAssertTrue(ScanSubjectLocator.isDispensingSignature("Take ONE tablet daily"))
        XCTAssertTrue(ScanSubjectLocator.isDispensingSignature("Chemist Warehouse Aspley"))
        XCTAssertTrue(ScanSubjectLocator.isDispensingSignature("30 tablets"))
        XCTAssertFalse(ScanSubjectLocator.isDispensingSignature("Listerine"))
        XCTAssertFalse(ScanSubjectLocator.isDispensingSignature("flowers"))
    }
}
