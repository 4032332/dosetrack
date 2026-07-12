// DoseTrack/Services/ScanSubjectLocator.swift
// Decides which part of the camera frame is the medication we're scanning — the "subject" — so
// the parser only consumes text ON the box/bottle/label and ignores everything around it
// (background bottles, price stickers, the patient's name across the room, flowers on the bench).
//
// Strategy (tiered, per the design): first try to lock onto a pharmacy DISPENSING LABEL — the
// dense cluster of text carrying the "QTY NAME STRENGTH FORM" line and/or "Take …" instructions.
// If there's no dispensing label (an OTC / no-script box or a plain manufacturer pack), fall back
// to the manufacturer front panel: the cluster around the largest (brand) text. Either way we
// return one bounding region to highlight on the live feed, and the set of items inside it.
//
// Pure value type over plain rects + strings, so the clustering is unit-testable without a camera.

import CoreGraphics
import Foundation

struct ScanSubjectLocator {

    struct Item {
        let text: String
        let rect: CGRect
        /// Text height as a fraction of the frame (bigger = more prominent). Used to find the
        /// brand block when there's no dispensing label.
        let heightFraction: CGFloat

        init(text: String, rect: CGRect, heightFraction: CGFloat = 0) {
            self.text = text
            self.rect = rect
            self.heightFraction = heightFraction
        }
    }

    struct Result: Equatable {
        /// The subject region to highlight, or nil if there wasn't enough to lock onto.
        let region: CGRect?
        /// Indices (into the input array) of the items that fall inside the subject region.
        let memberIndices: Set<Int>
    }

    /// Identify the subject region and its member items.
    static func locate(_ items: [Item]) -> Result {
        guard !items.isEmpty else { return Result(region: nil, memberIndices: []) }

        // Seed indices: prefer dispensing-signature lines; else the single tallest (brand) item.
        let signatureSeeds = items.indices.filter { isDispensingSignature(items[$0].text) }
        let seeds: [Int]
        if !signatureSeeds.isEmpty {
            seeds = signatureSeeds
        } else if let tallest = items.indices.max(by: { items[$0].heightFraction < items[$1].heightFraction }) {
            seeds = [tallest]
        } else {
            seeds = [0]
        }

        // Grow a region outward from the seeds, absorbing any item that sits near the current
        // region, until nothing new is close enough. This gathers a whole wrapped/curved label or
        // brand panel while leaving distant background text out. The reach is based on a typical
        // line height (not the seed's own height) so a thin seed line — a one-line "PRESCRIPTION
        // ONLY MEDICINE" banner, say — can still bridge to the lines just below it.
        let lineHeight = medianHeight(of: items)
        let margin = max(lineHeight * nearMargin, 1)
        var region = seeds.map { items[$0].rect }.reduce(CGRect.null) { $0.union($1) }
        var members = Set(seeds)
        var changed = true
        while changed {
            changed = false
            let grown = region.insetBy(dx: -margin, dy: -margin)
            for i in items.indices where !members.contains(i) {
                if items[i].rect.intersects(grown) {
                    members.insert(i)
                    region = region.union(items[i].rect)
                    changed = true
                }
            }
        }

        // Final membership: everything actually inside the (slightly padded) region.
        let padded = region.insetBy(dx: -region.width * 0.04, dy: -region.height * 0.04)
        let finalMembers = Set(items.indices.filter { padded.intersects(items[$0].rect) })
        return Result(region: padded, memberIndices: finalMembers)
    }

    /// How far beyond the current region an item can sit and still be pulled in, as a multiple of
    /// a typical line height. Generous enough to bridge the gaps between lines of a label (which
    /// are ~1 line-height apart), tight enough to leave a bottle sitting elsewhere on the bench out.
    private static let nearMargin: CGFloat = 1.6

    private static func medianHeight(of items: [Item]) -> CGFloat {
        let heights = items.map(\.rect.height).sorted()
        guard !heights.isEmpty else { return 0 }
        return heights[heights.count / 2]
    }

    // MARK: - Dispensing-label signature

    private static let strengthAndForm = try! NSRegularExpression(
        pattern: #"\d+(?:\.\d+)?\s*(?:mg|mcg|µg|iu|ml|g)\b"#, options: .caseInsensitive
    )
    private static let formWord = try! NSRegularExpression(
        pattern: #"\b(?:tab|tabs|tablet|tablets|cap|caps|capsule|capsules|caplet|caplets)\b"#,
        options: .caseInsensitive
    )
    private static let instructionVerb = try! NSRegularExpression(
        pattern: #"\b(?:take|use|apply|swallow|dissolve|inhale|instil|chew|insert)\b"#,
        options: .caseInsensitive
    )
    private static let pharmacyMarkers = [
        "chemist warehouse", "terrywhite", "chemmart", "pharmacy", "keep out of reach",
        "prescription only", "repeat", "dispensed", "qty",
    ]

    /// True when a line looks like it belongs to a pharmacy dispensing label — the thing we most
    /// want to lock onto. Deliberately broad: any one strong marker qualifies the line as a seed,
    /// and the region-growing step gathers the rest of the label around it.
    static func isDispensingSignature(_ text: String) -> Bool {
        let full = NSRange(location: 0, length: (text as NSString).length)
        if strengthAndForm.firstMatch(in: text, range: full) != nil { return true }
        if formWord.firstMatch(in: text, range: full) != nil { return true }
        if instructionVerb.firstMatch(in: text, range: full) != nil { return true }
        let lc = text.lowercased()
        return pharmacyMarkers.contains { lc.contains($0) }
    }
}
