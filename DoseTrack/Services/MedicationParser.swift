// DoseTrack/Services/MedicationParser.swift
// Turns the lines of text Vision recognised on a medication box into a structured scan result
// (name, strength, count, form). Deliberately conservative: it would rather return nil and let
// the user pick the name from the raw lines than confidently fill in the wrong thing.

import CoreGraphics
import Foundation

enum MedicationParser {

    // MARK: - Entry points

    /// Height-aware parse. Prefers the tallest non-boilerplate line as the name — on real
    /// packaging the brand/generic name is almost always the largest text, a much stronger
    /// signal than casing or position.
    static func parse(lines: [RecognizedLine]) -> MedicationScanResult? {
        guard !lines.isEmpty else { return nil }
        let strings = lines.map(\.text)

        let strength = extractStrength(from: strings)
        let count = extractCount(from: strings)
        let form = extractForm(from: strings)
        let name = extractName(from: lines)

        guard let name, !name.isEmpty else { return nil }

        return MedicationScanResult(
            name: name,
            strength: strength?.value ?? "",
            strengthUnit: strength?.unit ?? "mg",
            count: count ?? 0,
            form: form ?? "tablet",
            rawLines: strings
        )
    }

    /// String-only convenience (used by tests and by the raw-lines fallback). Every line is
    /// treated as unknown height, so name selection falls back to order/casing heuristics.
    static func parse(lines: [String]) -> MedicationScanResult? {
        parse(lines: lines.map { RecognizedLine(text: $0, heightFraction: 0) })
    }

    // MARK: - Strength: "500 mg", "10mg", "2.5mg/5mL"

    private struct StrengthMatch {
        let full: String
        let value: String
        let unit: String
    }

    // Longer unit alternatives (mg/ml, mg/5ml) come first so the regex prefers them over a bare
    // "mg" when both could match.
    private static let strengthPattern = try! NSRegularExpression(
        pattern: #"(\d+(?:\.\d+)?)\s*(mg\/(?:5ml|ml)|micrograms?|mcg|mg|iu|ml|g|%)"#,
        options: .caseInsensitive
    )

    private static func extractStrength(from lines: [String]) -> StrengthMatch? {
        for line in lines {
            let ns = line as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let match = strengthPattern.firstMatch(in: line, range: range) {
                let value = ns.substring(with: match.range(at: 1))
                var unit = ns.substring(with: match.range(at: 2)).lowercased()
                // Normalise spelled-out / variant units to what the form picker expects.
                if unit.hasPrefix("microgram") { unit = "mcg" }
                let full = ns.substring(with: match.range)
                return StrengthMatch(full: full, value: value, unit: unit)
            }
        }
        return nil
    }

    // MARK: - Count: "30 tablets", "28 CAPSULES", "100 tab", "30's"

    private static let countPattern = try! NSRegularExpression(
        pattern: #"(\d+)\s*(?:x\s*)?(?:tablets?|caps?(?:ules?)?|caplets?|softgels?|sachets?|doses?|puffs?|patches?|vials?|ampoules?|injections?|lozenges?|pastilles?|gummies|tabs?|'s)\b"#,
        options: .caseInsensitive
    )

    private static func extractCount(from lines: [String]) -> Int? {
        for line in lines {
            let ns = line as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let match = countPattern.firstMatch(in: line, range: range) {
                let numStr = ns.substring(with: match.range(at: 1))
                if let n = Int(numStr), n > 0, n <= 1000 { return n }
            }
        }
        return nil
    }

    // MARK: - Form

    private static let formKeywords: [(keyword: String, form: String)] = [
        // Order matters: check more specific words before generic ones.
        ("softgel", "capsule"), ("capsule", "capsule"), ("caplet", "tablet"),
        ("tablet", "tablet"), ("lozenge", "tablet"),
        ("inhaler", "inhaler"), ("puff", "inhaler"),
        ("injection", "injection"), ("ampoule", "injection"), ("vial", "injection"),
        ("patch", "patch"),
        ("spray", "spray"), ("nasal", "spray"),
        ("drops", "drop"), ("drop", "drop"),
        ("syrup", "ml"), ("suspension", "ml"), ("solution", "ml"), ("liquid", "ml"), ("oral liquid", "ml"),
        ("sachet", "sachet"),
        ("supplement", "supplement"),
        ("cap", "capsule"),   // generic fallback, last so "caplet"/"capsule" win first
    ]

    private static func extractForm(from lines: [String]) -> String? {
        let joined = lines.joined(separator: " ").lowercased()
        for (keyword, form) in formKeywords where joined.contains(keyword) {
            return form
        }
        return nil
    }

    // MARK: - Name

    /// Lowercased substrings that mark a line as packaging boilerplate rather than the product
    /// name — regulatory codes, storage/warning text, dosing instructions, etc.
    private static let boilerplateMarkers: [String] = [
        "tablet", "capsule", "caplet", "softgel", "lozenge", "sachet",
        "dose", "direction", "active ingredient", "inactive", "store", "storage",
        "expir", "batch", "lot no", "medicine", "medication", "pharmacy", "prescrib",
        "warning", "keep out", "reach of children", "apn", "ean", "aust r", "aust l",
        "australian", "new zealand", "contains", "each ", "take ", "swallow",
        "before", "after", "consult", "doctor", "pharmacist", "www.", ".com", "http",
        "manufactured", "distributed", "product of", "made in", "use by", "read the",
        "not exceed", "recommended", "if symptoms", "professional",
    ]

    private static func isBoilerplate(_ line: String) -> Bool {
        let lc = line.lowercased()
        return boilerplateMarkers.contains(where: { lc.contains($0) })
    }

    /// Remove strength ("200 mg") and count ("24 Tablets") fragments from a line. OCR frequently
    /// merges the brand name and strength onto ONE line ("Nurofen 200mg"), so rather than discard
    /// such a line we strip the noise and keep the name portion. A pure "500 mg" line strips down
    /// to nothing and is then rejected by the candidate check.
    private static func stripNoise(from line: String) -> String {
        var s = line as NSString
        for pattern in [strengthPattern, countPattern] {
            // Repeatedly remove the first match until none remain (ranges shift as we mutate).
            while let m = pattern.firstMatch(in: s as String, range: NSRange(location: 0, length: s.length)) {
                s = s.replacingCharacters(in: m.range, with: " ") as NSString
            }
        }
        return (s as String).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A stripped line is a plausible name if it has real letters, isn't too short, isn't mostly
    /// digits/symbols, and isn't packaging boilerplate.
    private static func isNameCandidate(_ stripped: String) -> Bool {
        guard stripped.count >= 3 else { return false }
        guard stripped.rangeOfCharacter(from: .letters) != nil else { return false }
        let letters = stripped.filter { $0.isLetter }.count
        guard Double(letters) / Double(stripped.count) >= 0.5 else { return false }
        return !isBoilerplate(stripped)
    }

    private static func extractName(from lines: [RecognizedLine]) -> String? {
        // Strip strength/count noise from each line, then keep the plausible name portions,
        // carrying each line's height along so the tallest can win below.
        let candidates: [(name: String, height: CGFloat)] = lines.compactMap { line in
            let stripped = clean(stripNoise(from: line.text))
            guard isNameCandidate(stripped) else { return nil }
            return (stripped, line.heightFraction)
        }
        guard !candidates.isEmpty else { return nil }

        // If we have real height data, the tallest candidate is the name — brand/generic names
        // are the dominant text on a box, a much stronger signal than casing or position.
        let maxHeight = candidates.map(\.height).max() ?? 0
        if maxHeight > 0 {
            return candidates.max { $0.height < $1.height }?.name
        }

        // No height info (string-only path): prefer a proper-noun-looking line, else the first
        // surviving candidate in reading order.
        let properNoun = candidates.first(where: { candidate in
            guard let first = candidate.name.first else { return false }
            return first.isUppercase && candidate.name.count <= 40 && !candidate.name.contains("  ")
        })
        return (properNoun ?? candidates[0]).name
    }

    /// Tidy a chosen name line: collapse whitespace and trim trailing punctuation/®/™.
    private static func clean(_ raw: String) -> String {
        let collapsed = raw
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "®™©*.,:;-–— "))
    }
}
