// DoseTrack/Services/MedicationTextRecognizer.swift
// Vision text recognition for the medication-box scanner, extracted out of the view so it can
// be unit-tested end to end (render an image → recognise → parse) instead of only ever exercised
// live through the camera.

import Vision
import UIKit

enum MedicationScanError: LocalizedError {
    case noImage
    case recognitionFailed(Error)

    var errorDescription: String? {
        switch self {
        case .noImage:
            return "Could not process this image."
        case .recognitionFailed:
            return "Couldn't read this image. Please try again with better lighting."
        }
    }
}

/// One line of recognised text plus how tall it is relative to the whole image. Height is a
/// strong prominence signal on medication packaging — the brand/generic name is almost always
/// the largest text on the box — so the parser uses it to pick the name far more reliably than
/// text content alone can.
struct RecognizedLine: Equatable {
    let text: String
    /// Bounding-box height as a fraction (0–1) of the image height. 0 when unknown (e.g. lines
    /// constructed directly in a test from plain strings).
    let heightFraction: CGFloat
}

enum MedicationTextRecognizer {

    /// Runs Vision text recognition on `image`, correctly accounting for its orientation.
    ///
    /// The orientation handling is the crux of the whole feature working: `UIImage.cgImage`
    /// hands back the raw sensor buffer WITHOUT applying `imageOrientation`, so a photo shot in
    /// portrait produces a sideways `cgImage`. Feeding that to Vision without telling it the
    /// orientation means every line of text is read rotated 90° — which returns either nothing
    /// or garbage, and is the single biggest reason scans previously "did nothing."
    static func recognizeLines(in image: UIImage) throws -> [RecognizedLine] {
        guard let cgImage = image.cgImage else { throw MedicationScanError.noImage }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: CGImagePropertyOrientation(image.imageOrientation),
            options: [:]
        )

        do {
            try handler.perform([request])
        } catch {
            throw MedicationScanError.recognitionFailed(error)
        }

        return sortedLines(from: request.results ?? [])
    }

    /// Sort observations into natural reading order (top-to-bottom, then left-to-right) and pair
    /// each with its height fraction. Vision does NOT guarantee results in reading order, and the
    /// parser's "name is usually near the top / most prominent" heuristics depend on the order
    /// being sane, so this is not optional cleanup.
    static func sortedLines(from observations: [VNRecognizedTextObservation]) -> [RecognizedLine] {
        let sorted = observations.sorted { a, b in
            // Vision's coordinate origin is bottom-left, so a larger midY is higher up the
            // image. Group lines onto the same visual row within a small tolerance, then order
            // those left-to-right.
            if abs(a.boundingBox.midY - b.boundingBox.midY) > 0.02 {
                return a.boundingBox.midY > b.boundingBox.midY
            }
            return a.boundingBox.midX < b.boundingBox.midX
        }
        return sorted.compactMap { obs in
            guard let text = obs.topCandidates(1).first?.string else { return nil }
            return RecognizedLine(text: text, heightFraction: obs.boundingBox.height)
        }
    }
}

extension CGImagePropertyOrientation {
    /// Bridges a `UIImage.Orientation` to the `CGImagePropertyOrientation` Vision expects.
    init(_ uiOrientation: UIImage.Orientation) {
        switch uiOrientation {
        case .up:            self = .up
        case .upMirrored:    self = .upMirrored
        case .down:          self = .down
        case .downMirrored:  self = .downMirrored
        case .left:          self = .left
        case .leftMirrored:  self = .leftMirrored
        case .right:         self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default:    self = .up
        }
    }
}
