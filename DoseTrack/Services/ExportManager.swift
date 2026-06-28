// DoseTrack/Services/ExportManager.swift
import Foundation
import CoreData

final class ExportManager {

    static let shared = ExportManager()
    private init() {}

    // MARK: - CSV Export (always free)

    func generateCSV(from logs: [DoseLog], dateRange: DateInterval) -> Data {
        var rows: [String] = [
            "Date,Time,Medication,Dose,Unit,Status,Notes"
        ]

        let sortedLogs = logs
            .filter { log in
                guard let scheduled = log.scheduledAt else { return false }
                return dateRange.contains(scheduled)
            }
            .sorted { ($0.scheduledAt ?? .distantPast) < ($1.scheduledAt ?? .distantPast) }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .none

        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short

        for log in sortedLogs {
            let scheduled = log.scheduledAt ?? Date()
            let med = log.medication
            let name = csvEscape(med?.wrappedName ?? "")
            let dose = csvEscape(med?.wrappedDosage ?? "")
            let unit = csvEscape(med?.wrappedUnit ?? "")
            let status = log.doseStatus.displayName
            let notes = csvEscape(log.wrappedNotes)

            let row = "\(dateFormatter.string(from: scheduled)),\(timeFormatter.string(from: scheduled)),\(name),\(dose),\(unit),\(status),\(notes)"
            rows.append(row)
        }

        let csv = rows.joined(separator: "\n")
        return Data(csv.utf8)
    }

    func fetchAllLogs(context: NSManagedObjectContext, in interval: DateInterval) -> [DoseLog] {
        let request = DoseLog.fetchRequest()
        request.predicate = NSPredicate(
            format: "scheduledAt >= %@ AND scheduledAt < %@",
            interval.start as NSDate,
            interval.end as NSDate
        )
        request.sortDescriptors = [NSSortDescriptor(key: "scheduledAt", ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

    // MARK: - Private

    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}
