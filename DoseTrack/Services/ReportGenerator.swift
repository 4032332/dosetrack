// DoseTrack/Services/ReportGenerator.swift
// Pro feature — gated at the call site before this is invoked.
import PDFKit
import UIKit
import CoreData

final class ReportGenerator {

    static let shared = ReportGenerator()
    private init() {}

    // MARK: - PDF Doctor Report

    func generatePDF(
        logs: [DoseLog],
        medications: [Medication],
        dateRange: DateInterval,
        patientName: String
    ) -> Data {
        let pageWidth: CGFloat = 612   // US Letter points
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 50
        let contentWidth = pageWidth - margin * 2

        let pdfData = NSMutableData()
        UIGraphicsBeginPDFContextToData(pdfData, CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight), nil)
        UIGraphicsBeginPDFPage()

        var yOffset: CGFloat = margin

        func ensureSpace(_ needed: CGFloat) {
            if yOffset + needed > pageHeight - margin {
                UIGraphicsBeginPDFPage()
                yOffset = margin
            }
        }

        // Header
        yOffset = drawText(
            "DoseTrack Medication Adherence Report",
            at: CGPoint(x: margin, y: yOffset),
            width: contentWidth,
            font: .systemFont(ofSize: 18, weight: .bold),
            color: .black
        )
        yOffset += 2
        yOffset = drawText(
            "Generated \(Date().formatted(date: .long, time: .omitted))",
            at: CGPoint(x: margin, y: yOffset),
            width: contentWidth,
            font: .systemFont(ofSize: 10),
            color: .darkGray
        )
        yOffset += 10
        drawHRule(at: yOffset, margin: margin, width: contentWidth)
        yOffset += 10

        // Patient info
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        if !patientName.isEmpty {
            yOffset = drawText(
                "Patient: \(patientName)",
                at: CGPoint(x: margin, y: yOffset),
                width: contentWidth,
                font: .systemFont(ofSize: 12, weight: .medium),
                color: .black
            )
        }
        // dateRange.end is exclusive (start-of-day-after-last-day) — display the inclusive last day.
        let inclusiveEnd = dateRange.end.addingTimeInterval(-1)
        let rangeText = "\(dateFormatter.string(from: dateRange.start)) – \(dateFormatter.string(from: inclusiveEnd))"
        yOffset = drawText(
            "Report period: \(rangeText)",
            at: CGPoint(x: margin, y: yOffset),
            width: contentWidth,
            font: .systemFont(ofSize: 12),
            color: .darkGray
        )
        yOffset += 12

        // Adherence summary
        drawHRule(at: yOffset, margin: margin, width: contentWidth)
        yOffset += 8
        yOffset = drawText(
            "Adherence Summary",
            at: CGPoint(x: margin, y: yOffset),
            width: contentWidth,
            font: .systemFont(ofSize: 14, weight: .bold),
            color: .black
        )
        yOffset += 6

        // The percentage covers SCHEDULED MEDICATION doses only. This is the number a prescriber
        // reads, so conflating it with vitamins (whose absence isn't clinically comparable) or with
        // as-needed doses (which can't be missed, and would only ever inflate it) would misrepresent
        // the patient. As-needed and non-medication activity is reported separately below.
        let scoredLogs = logs.filter { $0.countsTowardAdherence }
        let totalLogs = scoredLogs.count
        let takenLogs = scoredLogs.filter { $0.doseStatus == .taken }.count
        let missedLogs = scoredLogs.filter { $0.doseStatus == .missed }.count
        let skippedLogs = scoredLogs.filter { $0.doseStatus == .skipped }.count
        let overallPct = totalLogs > 0 ? Int(Double(takenLogs) / Double(totalLogs) * 100) : 100

        let asNeededLogs = logs.filter { $0.isAsNeeded }
        let supplementLogs = logs.filter {
            !$0.isAsNeeded && ($0.medication?.medicationKind ?? .medication) != .medication
        }

        yOffset = drawText(
            "Overall adherence: \(overallPct)%  (\(takenLogs) of \(totalLogs) scheduled medication doses taken)",
            at: CGPoint(x: margin, y: yOffset),
            width: contentWidth,
            font: .systemFont(ofSize: 12, weight: .semibold),
            color: .black
        )
        if !asNeededLogs.isEmpty || !supplementLogs.isEmpty {
            let supplementTaken = supplementLogs.filter { $0.doseStatus == .taken }.count
            var parts: [String] = []
            if !asNeededLogs.isEmpty {
                parts.append("As-needed doses taken: \(asNeededLogs.count)")
            }
            if !supplementLogs.isEmpty {
                parts.append("Vitamins/supplements: \(supplementTaken) of \(supplementLogs.count) taken")
            }
            yOffset = drawText(
                parts.joined(separator: "      "),
                at: CGPoint(x: margin, y: yOffset),
                width: contentWidth,
                font: .systemFont(ofSize: 10),
                color: .darkGray
            )
            yOffset = drawText(
                "Not included in the adherence percentage above.",
                at: CGPoint(x: margin, y: yOffset),
                width: contentWidth,
                font: .italicSystemFont(ofSize: 9),
                color: .gray
            )
        }
        yOffset = drawText(
            "Missed doses: \(missedLogs)      Skipped doses: \(skippedLogs)",
            at: CGPoint(x: margin, y: yOffset),
            width: contentWidth,
            font: .systemFont(ofSize: 11),
            color: .darkGray
        )
        yOffset += 14

        // Dose log grid — medications × dates
        drawHRule(at: yOffset, margin: margin, width: contentWidth)
        yOffset += 8
        yOffset = drawText(
            "Dose Log",
            at: CGPoint(x: margin, y: yOffset),
            width: contentWidth,
            font: .systemFont(ofSize: 14, weight: .bold),
            color: .black
        )
        yOffset += 6

        let activeMeds = medications
            .filter { med in logs.contains { $0.medication == med } }
            .sorted { $0.wrappedName < $1.wrappedName }

        if activeMeds.isEmpty {
            yOffset = drawText(
                "No doses logged in this period.",
                at: CGPoint(x: margin, y: yOffset),
                width: contentWidth,
                font: .systemFont(ofSize: 11),
                color: .darkGray
            )
            yOffset += 10
        } else {
            let calendar = Calendar.current

            // Enumerate every day in range (dateRange.end is exclusive)
            var days: [Date] = []
            var cursor = calendar.startOfDay(for: dateRange.start)
            let endDay = calendar.startOfDay(for: dateRange.end)
            while cursor < endDay {
                days.append(cursor)
                cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? endDay
            }

            // Worst-of-day status per medication per day: missed > skipped > taken.
            // A day with no entry means no dose was scheduled for that medication that day.
            func rank(_ s: DoseStatus) -> Int {
                switch s {
                case .missed: return 2
                case .skipped: return 1
                case .taken: return 0
                }
            }
            var statusMap: [NSManagedObjectID: [Date: (status: DoseStatus, isBackdated: Bool)]] = [:]
            for log in logs {
                guard let med = log.medication, let scheduledAt = log.scheduledAt else { continue }
                let day = calendar.startOfDay(for: scheduledAt)
                var dayMap = statusMap[med.objectID] ?? [:]
                if let existing = dayMap[day], rank(existing.status) >= rank(log.doseStatus) {
                    // keep existing (already worse or equal)
                } else {
                    dayMap[day] = (log.doseStatus, log.isBackdated)
                }
                statusMap[med.objectID] = dayMap
            }

            let labelColWidth: CGFloat = 110
            let daysPerPage = 14
            let dateColWidth = (contentWidth - labelColWidth) / CGFloat(daysPerPage)
            let rowHeight: CGFloat = 15

            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "d"
            let monthFormatter = DateFormatter()
            monthFormatter.dateFormat = "MMM yyyy"

            func drawGridHeader(for chunk: [Date]) {
                var x = margin + labelColWidth
                for day in chunk {
                    centeredText(dayFormatter.string(from: day),
                                 in: CGRect(x: x, y: yOffset, width: dateColWidth, height: 12),
                                 font: .systemFont(ofSize: 8, weight: .bold), color: .darkGray)
                    x += dateColWidth
                }
                yOffset += 14
                drawHRule(at: yOffset, margin: margin, width: contentWidth, lineWidth: 0.5, color: .lightGray)
                yOffset += 4
            }

            let chunks = stride(from: 0, to: days.count, by: daysPerPage).map {
                Array(days[$0..<min($0 + daysPerPage, days.count)])
            }

            for chunk in chunks {
                ensureSpace(30)
                if let first = chunk.first {
                    yOffset = drawText(monthFormatter.string(from: first),
                                        at: CGPoint(x: margin, y: yOffset), width: contentWidth,
                                        font: .systemFont(ofSize: 9, weight: .semibold), color: .darkGray)
                }
                drawGridHeader(for: chunk)

                for med in activeMeds {
                    if yOffset + rowHeight > pageHeight - margin {
                        UIGraphicsBeginPDFPage()
                        yOffset = margin
                        drawGridHeader(for: chunk)
                    }

                    drawText(med.wrappedName, at: CGPoint(x: margin, y: yOffset), width: labelColWidth - 6,
                             font: .systemFont(ofSize: 9), color: .black)

                    var x = margin + labelColWidth
                    let dayMap = statusMap[med.objectID] ?? [:]
                    for day in chunk {
                        if let entry = dayMap[day] {
                            let (glyph, color) = glyphAndColor(for: entry.status, isBackdated: entry.isBackdated)
                            centeredText(glyph, in: CGRect(x: x, y: yOffset, width: dateColWidth, height: rowHeight),
                                         font: .boldSystemFont(ofSize: 10), color: color)
                        }
                        x += dateColWidth
                    }
                    yOffset += rowHeight
                }
                yOffset += 10
            }

            ensureSpace(20)
            yOffset = drawLegend(at: yOffset, margin: margin)
            yOffset += 14
        }

        // Notes
        let notedLogs = logs
            .filter { !$0.wrappedNotes.isEmpty }
            .sorted { ($0.scheduledAt ?? .distantPast) < ($1.scheduledAt ?? .distantPast) }

        if !notedLogs.isEmpty {
            ensureSpace(40)
            drawHRule(at: yOffset, margin: margin, width: contentWidth)
            yOffset += 8
            yOffset = drawText(
                "Notes",
                at: CGPoint(x: margin, y: yOffset),
                width: contentWidth,
                font: .systemFont(ofSize: 14, weight: .bold),
                color: .black
            )
            yOffset += 6

            let noteFormatter = DateFormatter()
            noteFormatter.dateStyle = .medium
            for log in notedLogs {
                ensureSpace(24)
                let dateStr = log.scheduledAt.map { noteFormatter.string(from: $0) } ?? ""
                let medName = log.medication?.wrappedName ?? "—"
                yOffset = drawText(
                    "\(dateStr) — \(medName): \(log.wrappedNotes)",
                    at: CGPoint(x: margin, y: yOffset),
                    width: contentWidth,
                    font: .systemFont(ofSize: 10),
                    color: .black
                )
                yOffset += 2
            }
            yOffset += 8
        }

        // Footer disclaimer
        ensureSpace(30)
        drawHRule(at: yOffset, margin: margin, width: contentWidth)
        yOffset += 6
        drawText(
            "This report is a reminder tool record only and does not constitute medical advice. Always follow your healthcare provider's instructions.",
            at: CGPoint(x: margin, y: yOffset),
            width: contentWidth,
            font: .systemFont(ofSize: 8),
            color: .gray
        )

        UIGraphicsEndPDFContext()
        return pdfData as Data
    }

    // MARK: - Grid glyphs

    /// A backdated correction (see `DoseLog.isBackdated`) never renders identically to a
    /// same-day log — an asterisk is appended and the colour is dimmed, so a doctor reading the
    /// report can see at a glance that this entry was corrected after the fact, not recorded on
    /// the day it happened.
    private func glyphAndColor(for status: DoseStatus, isBackdated: Bool) -> (String, UIColor) {
        let (base, color): (String, UIColor) = {
            switch status {
            case .taken:   return ("\u{2713}", .systemGreen)   // ✓
            case .missed:  return ("\u{2715}", .systemRed)     // ✕
            case .skipped: return ("\u{2022}", .systemOrange)  // •
            }
        }()
        guard isBackdated else { return (base, color) }
        return (base + "*", color.withAlphaComponent(0.6))
    }

    private func drawLegend(at y: CGFloat, margin: CGFloat) -> CGFloat {
        let items: [(String, UIColor, String)] = [
            ("\u{2713}", .systemGreen, "Taken"),
            ("\u{2715}", .systemRed, "Missed"),
            ("\u{2022}", .systemOrange, "Skipped")
        ]
        var x = margin
        var maxBottom = y
        let labelFont = UIFont.systemFont(ofSize: 9)
        for (glyph, color, label) in items {
            let glyphAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 10), .foregroundColor: color]
            NSAttributedString(string: glyph, attributes: glyphAttrs).draw(at: CGPoint(x: x, y: y))
            x += 14
            let bottom = drawText(label, at: CGPoint(x: x, y: y), width: 55, font: labelFont, color: .darkGray)
            maxBottom = max(maxBottom, bottom)
            x += 58
        }
        let blankBottom = drawText("(blank) No dose scheduled", at: CGPoint(x: x, y: y), width: 200, font: labelFont, color: .darkGray)
        maxBottom = max(maxBottom, blankBottom)
        maxBottom += 2
        let starBottom = drawText("* Corrected after the fact, not logged on the day", at: CGPoint(x: margin, y: maxBottom), width: 300, font: labelFont, color: .darkGray)
        return max(maxBottom, starBottom)
    }

    // MARK: - Drawing helpers

    @discardableResult
    private func drawText(
        _ text: String,
        at point: CGPoint,
        width: CGFloat,
        font: UIFont,
        color: UIColor
    ) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let rect = CGRect(x: point.x, y: point.y, width: width, height: 1000)
        let bounds = str.boundingRect(with: CGSize(width: width, height: 1000),
                                       options: [.usesLineFragmentOrigin], context: nil)
        str.draw(in: rect)
        return point.y + bounds.height + 2
    }

    private func centeredText(_ text: String, in rect: CGRect, font: UIFont, color: UIColor) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        let point = CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
        str.draw(at: point)
    }

    private func drawHRule(
        at y: CGFloat,
        margin: CGFloat,
        width: CGFloat,
        lineWidth: CGFloat = 1,
        color: UIColor = .black
    ) {
        color.setStroke()
        let path = UIBezierPath()
        path.lineWidth = lineWidth
        path.move(to: CGPoint(x: margin, y: y))
        path.addLine(to: CGPoint(x: margin + width, y: y))
        path.stroke()
    }
}
