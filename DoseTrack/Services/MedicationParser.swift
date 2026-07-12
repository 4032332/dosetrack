// DoseTrack/Services/MedicationParser.swift
// Turns lines of text (from Vision OCR of a medication box, or the live DataScanner feed) into a
// structured scan result: name, strength, supply quantity, form, and — reasoned from any dosing
// instructions found — how many units are taken per dose. Deliberately conservative: it would
// rather leave a field blank and let the user fill it than confidently fill in the wrong thing.

import CoreGraphics
import Foundation

// MARK: - Result model

struct MedicationScanResult {
    var name: String
    var strength: String        // numeric part, e.g. "500"
    var strengthUnit: String    // e.g. "mg"
    var count: Int              // supply quantity in the pack, e.g. 30 (0 = not found)
    var form: String            // e.g. "tablet"
    var perDose: Int            // units taken per dose, reasoned from instructions (0 = not found)
    var instructions: String?   // the raw dosing-instruction line, if one was found
    var rawLines: [String]      // all recognised lines (for the manual-pick fallback / debugging)

    /// Which fields the parser managed to populate — drives the live scanner's "captured" tick
    /// list and the "have we got enough to use this?" gate (a name is the minimum).
    var hasName: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }
    var hasStrength: Bool { !strength.isEmpty }
    var hasSupply: Bool { count > 0 }
    var hasPerDose: Bool { perDose > 0 }
}

// MARK: - Live-scan text accumulator

/// Accumulates recognised text across many camera frames for the live scanner, deduping the same
/// line (normalised: lowercased, whitespace-collapsed) and keeping the longest variant seen plus
/// the greatest height it appeared at. This is what lets the live scanner read a cylindrical
/// bottle: the label wraps around the curve so no single frame shows all of it — the user rotates
/// the bottle and each line is captured once and retained, instead of being lost when it scrolls
/// off the current frame. Pure value type so the retention logic is unit-testable without a camera.
struct ScanTextAccumulator {
    private(set) var entries: [String: (text: String, height: CGFloat)] = [:]
    /// Upper bound so a long session can't grow unbounded (real labels have well under this).
    let cap: Int

    init(cap: Int = 200) { self.cap = cap }

    mutating func add(text: String, height: CGFloat) {
        let key = Self.normalize(text)
        guard !key.isEmpty else { return }
        if let existing = entries[key] {
            entries[key] = (
                text: text.count > existing.text.count ? text : existing.text,
                height: max(existing.height, height)
            )
        } else if entries.count < cap {
            entries[key] = (text: text, height: height)
        }
    }

    mutating func removeAll() { entries.removeAll() }

    /// Drop accumulated lines matching a predicate — used by the live scanner's per-field "retry",
    /// which forgets the text behind one field (e.g. the strength lines) so the next frames re-read
    /// just that field instead of the user restarting the whole scan.
    mutating func removeMatching(_ predicate: (String) -> Bool) {
        for (key, value) in entries where predicate(value.text) { entries.removeValue(forKey: key) }
    }

    /// The accumulated text as parser input.
    var lines: [RecognizedLine] {
        entries.values.map { RecognizedLine(text: $0.text, heightFraction: $0.height) }
    }

    static func normalize(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum MedicationParser {

    // MARK: - Entry points

    /// Height-aware parse. Prefers the tallest non-boilerplate line as the name — on real
    /// packaging the brand/generic name is almost always the largest text, a much stronger
    /// signal than casing or position.
    static func parse(lines: [RecognizedLine]) -> MedicationScanResult? {
        guard !lines.isEmpty else { return nil }
        let strings = lines.map(\.text)

        let strength = extractStrength(from: strings)
        let supply = extractSupply(from: strings)
        let form = extractForm(from: strings)
        let name = extractName(from: lines)
        let dosing = extractPerDose(from: strings)

        guard let name, !name.isEmpty else { return nil }

        return MedicationScanResult(
            name: name,
            strength: strength?.value ?? "",
            strengthUnit: strength?.unit ?? "mg",
            count: supply ?? 0,
            form: form ?? "tablet",
            perDose: dosing?.perDose ?? 0,
            instructions: dosing?.line,
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
    // "mg" when both could match. `µg` (the micro glyph) and `mcg` both mean micrograms — real
    // labels use either (e.g. clonidine "100 µg").
    private static let strengthPattern = try! NSRegularExpression(
        pattern: #"(\d+(?:\.\d+)?)\s*(mg\/(?:5ml|ml)|micrograms?|mcg|µg|mg|iu|ml|g|%)"#,
        options: .caseInsensitive
    )

    private static func extractStrength(from lines: [String]) -> StrengthMatch? {
        // Skip dosing-instruction lines: titration wording like "increase the dose by 0.5mg until
        // reaching 4mg" is full of mg numbers that are NOT the medication's strength. The strength
        // lives on the name/pack line, so a non-instruction line is always the right source.
        for line in lines where !isInstructionLine(line) {
            let ns = line as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let match = strengthPattern.firstMatch(in: line, range: range) {
                let value = ns.substring(with: match.range(at: 1))
                var unit = ns.substring(with: match.range(at: 2)).lowercased()
                // Normalise spelled-out / variant units to what the form picker expects.
                if unit.hasPrefix("microgram") || unit == "µg" { unit = "mcg" }
                let full = ns.substring(with: match.range)
                return StrengthMatch(full: full, value: value, unit: unit)
            }
        }
        return nil
    }

    // MARK: - Supply quantity (pack size -> currentCount)

    /// Dose-form words used by both the supply and per-dose patterns.
    private static let formWords = "tablets?|caps?(?:ules?)?|caplets?|softgels?|sachets?|doses?|puffs?|patches?|vials?|ampoules?|lozenges?|pastilles?|gummies|pills?|sprays?|drops?|tabs?"

    /// Explicit pack-size markers: "QTY 30", "Qty: 30", "Quantity 30", "Pack of 30", "30 Pack".
    /// Prioritised over a bare "N tablets" because it's unambiguous.
    private static let qtyPattern = try! NSRegularExpression(
        pattern: #"\b(?:qty|quantity|pack(?:\s+of)?|contents?)\b[^\d]{0,6}(\d+)\b|\b(\d+)\s*(?:'s\b|pack\b)"#,
        options: .caseInsensitive
    )

    /// A bare "30 tablets" / "28 CAPSULES" count. Used for supply only on NON-instruction lines
    /// (so "take 1 tablet three times a day" is never mistaken for a supply of 1).
    private static let countPattern = try! NSRegularExpression(
        pattern: #"(\d+)\s*(?:x\s*)?(?:\#(formWords))\b"#,
        options: .caseInsensitive
    )

    private static func extractSupply(from lines: [String]) -> Int? {
        // 1. Explicit QTY/Quantity/Pack markers win — try these across every line first. But a
        //    "Pack 1 of 2" dispensing marker (which pack this is, out of a repeat set) must NOT be
        //    read as a quantity, so a captured number immediately followed by "of" is rejected.
        for line in lines {
            let ns = line as NSString
            let range = NSRange(location: 0, length: ns.length)
            let lower = line.lowercased() as NSString
            if let match = qtyPattern.firstMatch(in: line, range: range) {
                for groupIndex in 1..<match.numberOfRanges {
                    let r = match.range(at: groupIndex)
                    guard r.location != NSNotFound, let n = Int(ns.substring(with: r)), n > 0, n <= 1000 else { continue }
                    let after = r.location + r.length
                    let ctx = after < ns.length
                        ? lower.substring(with: NSRange(location: after, length: min(4, ns.length - after))).trimmingCharacters(in: .whitespaces)
                        : ""
                    if ctx.hasPrefix("of ") || ctx == "of" { continue }
                    return n
                }
            }
        }
        // 2. A bare "N tablets" / "28 CAPSULES", but only on non-instruction lines.
        for line in lines where !isInstructionLine(line) {
            let ns = line as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let match = countPattern.firstMatch(in: line, range: range) {
                let numStr = ns.substring(with: match.range(at: 1))
                if let n = Int(numStr), n > 0, n <= 1000 { return n }
            }
        }
        // 3. Pharmacy dispensing line, e.g. "100 MINIPRESS 1MG TAB (prazosin)" or
        //    "MELOXICAM TABLETS 15mg 30 (…)". The pack quantity is the standalone integer on a
        //    line that also carries a strength AND a form word — but it's NOT adjacent to a form
        //    word (strategy 2 already handles that), so it's easy to miss. Pull the non-strength
        //    integer from such a line.
        for line in lines where !isInstructionLine(line) {
            if let n = supplyFromDispensingLine(line) { return n }
        }
        return nil
    }

    private static let formWordPattern = try! NSRegularExpression(
        pattern: #"\b(?:\#(formWords))\b"#, options: .caseInsensitive
    )
    private static let integerTokenPattern = try! NSRegularExpression(
        pattern: #"\d+"#, options: []
    )

    /// Extract the pack quantity from a pharmacy dispensing line: a line carrying both a strength
    /// and a dose-form word. The quantity is the standalone integer that is NOT the strength's
    /// number, NOT inside parentheses (that's usually a generic/brand name), and NOT part of a
    /// "Pack 1 of 2" marker. Prefers a plausible pack size (>= a few units).
    private static func supplyFromDispensingLine(_ line: String) -> Int? {
        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)
        // Must look like a dispensing/name line: has a strength and a form word.
        guard let strength = strengthPattern.firstMatch(in: line, range: full),
              formWordPattern.firstMatch(in: line, range: full) != nil else { return nil }

        // Ranges to exclude: the strength's own number, and anything inside parentheses.
        let strengthNumberRange = strength.range(at: 1)
        let parenRanges = parentheticalRanges(in: ns)
        let lower = line.lowercased() as NSString

        var candidates: [(value: Int, location: Int)] = []
        integerTokenPattern.enumerateMatches(in: line, range: full) { m, _, _ in
            guard let m else { return }
            let r = m.range
            if NSIntersectionRange(r, strengthNumberRange).length > 0 { return }
            if parenRanges.contains(where: { NSIntersectionRange(r, $0).length > 0 }) { return }
            // Skip "N of M" pack markers (either side of "of").
            let token = ns.substring(with: r)
            let after = r.location + r.length
            let afterCtx = after < ns.length ? lower.substring(with: NSRange(location: after, length: min(4, ns.length - after))) : ""
            if afterCtx.trimmingCharacters(in: .whitespaces).hasPrefix("of ") || afterCtx.trimmingCharacters(in: .whitespaces) == "of" { return }
            if let n = Int(token), n > 0, n <= 1000 { candidates.append((n, r.location)) }
        }
        guard !candidates.isEmpty else { return nil }
        // Prefer a realistic pack size (>= 4 rules out a stray "1"/"2" from e.g. "MR" tab codes),
        // taking the earliest such; otherwise fall back to the first integer found.
        return candidates.first(where: { $0.value >= 4 })?.value ?? candidates.first?.value
    }

    private static func parentheticalRanges(in ns: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        var depth = 0
        var start = 0
        for i in 0..<ns.length {
            let c = ns.character(at: i)
            if c == UInt16(UnicodeScalar("(").value) {
                if depth == 0 { start = i }
                depth += 1
            } else if c == UInt16(UnicodeScalar(")").value) {
                if depth > 0 {
                    depth -= 1
                    if depth == 0 { ranges.append(NSRange(location: start, length: i - start + 1)) }
                }
            }
        }
        // An unclosed "(" (label truncated at a bottle edge) — treat the rest of the line as paren.
        if depth > 0 { ranges.append(NSRange(location: start, length: ns.length - start)) }
        return ranges
    }

    // MARK: - Per-dose quantity (reasoned from dosing instructions -> quantityAmount)

    /// Words that mark a line as a dosing instruction rather than pack/marketing text.
    private static let dosingVerbs = ["take", "use", "apply", "swallow", "insert", "inhale", "instil", "chew", "dissolve"]

    private static func isInstructionLine(_ line: String) -> Bool {
        let lc = line.lowercased()
        // A leading/space-bounded verb, plus a plausible dosing context, so a brand line that
        // merely contains "use" as a substring isn't misread as an instruction.
        let hasVerb = dosingVerbs.contains { verb in
            lc == verb || lc.hasPrefix(verb + " ") || lc.contains(" " + verb + " ")
        }
        return hasVerb
    }

    private static let numberWords: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
        "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
    ]

    /// The number that immediately precedes a dose-form word ("2 tablets", "one capsule"). This
    /// is the per-dose amount — crucially NOT the frequency number, because the frequency number
    /// precedes "times"/"daily" ("3 times a day"), never a form word. Handles ranges ("1 to 2
    /// tablets") by taking the lower number.
    private static let perDosePattern = try! NSRegularExpression(
        pattern: #"\b(\d+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\b(?:\s+(?:to|-|–|or)\s+(?:\d+|one|two|three|four|five|six|seven|eight|nine|ten))?\s+(?:\#(formWords))\b"#,
        options: .caseInsensitive
    )

    private static func extractPerDose(from lines: [String]) -> (perDose: Int, line: String)? {
        for line in lines where isInstructionLine(line) {
            let ns = line as NSString
            let range = NSRange(location: 0, length: ns.length)
            guard let match = perDosePattern.firstMatch(in: line, range: range) else { continue }
            let token = ns.substring(with: match.range(at: 1)).lowercased()
            let value = Int(token) ?? numberWords[token]
            if let value, value > 0, value <= 12 {
                return (value, (line as String).trimmingCharacters(in: .whitespacesAndNewlines))
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
        "not exceed", "recommended", "if symptoms", "professional", "qty", "quantity",
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
        guard !candidates.isEmpty else {
            // Nothing survived stripping — fall back to the name embedded in a dispensing line
            // (its form word would have flagged it boilerplate above).
            for text in lines.map(\.text) {
                if let n = nameFromDispensingLine(text) { return clean(n) }
            }
            return nil
        }

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

    /// Dose-form descriptors that appear on a dispensing line around the name but aren't part of
    /// it (release-profile codes, form abbreviations, common manufacturer tags).
    private static let dispensingDescriptors: Set<String> = [
        "mr", "sr", "xr", "cr", "er", "ec", "odt", "xl", "hcl",
        "tab", "tabs", "tablet", "tablets", "cap", "caps", "caplet", "caplets",
        "capsule", "capsules", "orally", "wgr",
    ]

    /// The medication name as it appears on a pharmacy dispensing line ("100 MINIPRESS 1MG TAB
    /// (prazosin)" → "MINIPRESS"; "MELOXICAM TABLETS 15mg 30 (…)" → "MELOXICAM"). Only applied to a
    /// qualifying dispensing line (strength + form word), and used as a last-resort name source
    /// when the height/casing heuristics find nothing — e.g. a cylindrical bottle whose only clear
    /// text is the wrapped dispensing line, where the form word would otherwise flag it boilerplate.
    private static func nameFromDispensingLine(_ line: String) -> String? {
        let full = NSRange(location: 0, length: (line as NSString).length)
        guard strengthPattern.firstMatch(in: line, range: full) != nil,
              formWordPattern.firstMatch(in: line, range: full) != nil else { return nil }
        // Drop parenthetical content (alt names / mfr codes), then tokenise.
        var stripped = line
        while let open = stripped.firstIndex(of: "("), let close = stripped[open...].firstIndex(of: ")") {
            stripped.replaceSubrange(open...close, with: " ")
        }
        let tokens = stripped.split(whereSeparator: { $0 == " " || $0 == "-" }).map(String.init)
        for token in tokens {
            let clean = token.trimmingCharacters(in: CharacterSet(charactersIn: "®™©*.,:;()"))
            let lc = clean.lowercased()
            if clean.count < 3 { continue }
            if clean.rangeOfCharacter(from: .decimalDigits) != nil { continue }  // strength/qty
            if dispensingDescriptors.contains(lc) { continue }
            if clean.filter(\.isLetter).count < clean.count / 2 { continue }
            return clean
        }
        return nil
    }

    /// Tidy a chosen name line: collapse whitespace and trim trailing punctuation/®/™.
    private static func clean(_ raw: String) -> String {
        let collapsed = raw
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "®™©*.,:;-–— "))
    }
}
