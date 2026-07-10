// DoseTrackTests/MedicationTextRecognizerTests.swift
// End-to-end OCR tests: render a synthetic medication box to an image, run it through the REAL
// Vision recognizer + parser, and assert the extracted fields. This is what was missing before —
// the scanner was only ever exercised live through the camera, so regressions (like the
// orientation bug that made portrait photos unreadable) went unnoticed.

import XCTest
import UIKit
@testable import DoseTrack

final class MedicationTextRecognizerTests: XCTestCase {

    // MARK: - Synthetic box rendering

    private struct BoxLine {
        let text: String
        let fontSize: CGFloat
        let bold: Bool
    }

    /// Renders lines of text onto a white "box", biggest first, so the result looks like real
    /// packaging (prominent name, smaller strength/count, tiny boilerplate).
    private func renderBox(_ lines: [BoxLine], size: CGSize = CGSize(width: 800, height: 1000)) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            var y: CGFloat = 60
            for line in lines {
                let font = line.bold
                    ? UIFont.boldSystemFont(ofSize: line.fontSize)
                    : UIFont.systemFont(ofSize: line.fontSize)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: UIColor.black,
                ]
                let attributed = NSAttributedString(string: line.text, attributes: attrs)
                attributed.draw(at: CGPoint(x: 60, y: y))
                y += line.fontSize * 1.8
            }
        }
    }

    private func nurofenBox() -> UIImage {
        renderBox([
            BoxLine(text: "Nurofen", fontSize: 90, bold: true),
            BoxLine(text: "Ibuprofen", fontSize: 40, bold: false),
            BoxLine(text: "200 mg", fontSize: 52, bold: true),
            BoxLine(text: "24 Tablets", fontSize: 48, bold: false),
            BoxLine(text: "Keep out of reach of children", fontSize: 26, bold: false),
        ])
    }

    /// Simulate a portrait photo: physically rotate the pixels so the text is sideways in the
    /// buffer, then tag the image `.right` — exactly the state a real portrait camera capture is
    /// in. An orientation-aware reader must rotate it back to read it.
    private func asPortraitCapture(_ image: UIImage) -> UIImage {
        let cg = image.cgImage!
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: h, height: w))
        let rotated = renderer.image { ctx in
            let c = ctx.cgContext
            c.translateBy(x: h / 2, y: w / 2)
            c.rotate(by: -.pi / 2)
            c.translateBy(x: -w / 2, y: -h / 2)
            image.draw(in: CGRect(x: 0, y: 0, width: w, height: h))
        }.cgImage!
        return UIImage(cgImage: rotated, scale: 1, orientation: .right)
    }

    // MARK: - Tests

    func testRecognize_uprightBox_extractsAllFields() throws {
        let lines = try MedicationTextRecognizer.recognizeLines(in: nurofenBox())
        XCTAssertFalse(lines.isEmpty, "OCR returned no text from a clean rendered box")

        let result = MedicationParser.parse(lines: lines)
        XCTAssertNotNil(result, "Parser produced no result from: \(lines.map(\.text))")
        XCTAssertEqual(result?.name, "Nurofen", "lines: \(lines.map(\.text))")
        XCTAssertEqual(result?.strength, "200")
        XCTAssertEqual(result?.strengthUnit, "mg")
        XCTAssertEqual(result?.count, 24)
        XCTAssertEqual(result?.form, "tablet")
    }

    func testRecognize_portraitCapture_stillReadsText() throws {
        // The regression guard: before the orientation fix this returned garbage/nothing because
        // Vision read the sideways buffer as-is.
        let lines = try MedicationTextRecognizer.recognizeLines(in: asPortraitCapture(nurofenBox()))
        XCTAssertFalse(lines.isEmpty, "OCR returned no text from a portrait-oriented capture")

        let result = MedicationParser.parse(lines: lines)
        XCTAssertNotNil(result, "Parser produced no result from portrait capture: \(lines.map(\.text))")
        XCTAssertEqual(result?.name, "Nurofen", "lines: \(lines.map(\.text))")
        XCTAssertEqual(result?.strength, "200")
        XCTAssertEqual(result?.count, 24)
    }

    func testRecognize_namePickedIsTheLargestText() throws {
        // "Panadol" is the biggest text; "Paracetamol" (generic) is smaller; both are valid name
        // candidates, so the height signal is what disambiguates to the brand name.
        let box = renderBox([
            BoxLine(text: "Panadol", fontSize: 96, bold: true),
            BoxLine(text: "Paracetamol", fontSize: 36, bold: false),
            BoxLine(text: "500 mg", fontSize: 50, bold: true),
            BoxLine(text: "20 Caplets", fontSize: 46, bold: false),
        ])
        let lines = try MedicationTextRecognizer.recognizeLines(in: box)
        let result = MedicationParser.parse(lines: lines)
        XCTAssertEqual(result?.name, "Panadol", "lines: \(lines.map(\.text))")
        XCTAssertEqual(result?.strength, "500")
        XCTAssertEqual(result?.form, "tablet") // caplet -> tablet
    }
}
