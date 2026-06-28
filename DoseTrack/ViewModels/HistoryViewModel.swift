// DoseTrack/ViewModels/HistoryViewModel.swift
import CoreData
import SwiftUI

enum DateRangeMode: String, CaseIterable {
    case week = "Week"
    case month = "Month"
    case custom = "Custom"
}

struct DayAdherence: Identifiable {
    let id: Date         // The calendar day (start-of-day)
    let date: Date
    let taken: Int
    let total: Int

    var percent: Double {
        guard total > 0 else { return 1.0 }
        return Double(taken) / Double(total)
    }

    var color: Color {
        switch percent {
        case 0.9...: return .green
        case 0.5..<0.9: return .orange
        default: return .red
        }
    }
}

struct MedicationAdherence: Identifiable {
    let id: NSManagedObjectID
    let name: String
    let colorHex: String
    let taken: Int
    let total: Int

    var percent: Double {
        guard total > 0 else { return 1.0 }
        return Double(taken) / Double(total)
    }
}

@MainActor
final class HistoryViewModel: ObservableObject {

    // MARK: - State

    @Published var rangeMode: DateRangeMode = .week {
        didSet { updateDateRange(); refresh() }
    }
    @Published var customStart: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date() {
        didSet { if rangeMode == .custom { refresh() } }
    }
    @Published var customEnd: Date = Date() {
        didSet { if rangeMode == .custom { refresh() } }
    }

    @Published var dayAdherences: [DayAdherence] = []
    @Published var medicationAdherences: [MedicationAdherence] = []
    @Published var overallPercent: Double = 1.0

    // Derived from rangeMode
    @Published var startDate: Date = Date()
    @Published var endDate: Date = Date()

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
        updateDateRange()
        refresh()
    }

    // MARK: - Public

    func refresh() {
        let interval = effectiveDateInterval()
        let logs = fetchLogs(in: interval)
        let medications = fetchActiveMedications()

        dayAdherences = buildDayAdherences(logs: logs, medications: medications, interval: interval)
        medicationAdherences = buildMedicationAdherences(logs: logs, medications: medications, interval: interval)
        overallPercent = calculateOverallPercent()
    }

    var effectiveStart: Date { rangeMode == .custom ? customStart : startDate }
    var effectiveEnd: Date { rangeMode == .custom ? customEnd : endDate }

    // MARK: - Private: date range

    private func updateDateRange() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        switch rangeMode {
        case .week:
            startDate = calendar.date(byAdding: .day, value: -6, to: today) ?? today
            endDate = today
        case .month:
            startDate = calendar.date(byAdding: .day, value: -29, to: today) ?? today
            endDate = today
        case .custom:
            break // Controlled by customStart/customEnd
        }
    }

    private func effectiveDateInterval() -> DateInterval {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: effectiveStart)
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: effectiveEnd)) ?? effectiveEnd
        return DateInterval(start: start, end: end)
    }

    // MARK: - Private: data fetching

    private func fetchLogs(in interval: DateInterval) -> [DoseLog] {
        let request = DoseLog.fetchRequest()
        request.predicate = NSPredicate(
            format: "scheduledAt >= %@ AND scheduledAt < %@",
            interval.start as NSDate,
            interval.end as NSDate
        )
        return (try? context.fetch(request)) ?? []
    }

    private func fetchActiveMedications() -> [Medication] {
        let request = Medication.fetchRequest()
        request.predicate = NSPredicate(format: "isActive == YES")
        return (try? context.fetch(request)) ?? []
    }

    // MARK: - Private: adherence building

    private func buildDayAdherences(
        logs: [DoseLog],
        medications: [Medication],
        interval: DateInterval
    ) -> [DayAdherence] {
        let calendar = Calendar.current
        var days: [DayAdherence] = []

        var cursor = calendar.startOfDay(for: interval.start)
        let end = calendar.startOfDay(for: interval.end)

        while cursor < end {
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor

            let dayLogs = logs.filter { log in
                guard let scheduled = log.scheduledAt else { return false }
                return scheduled >= cursor && scheduled < dayEnd
            }

            let taken = dayLogs.filter { $0.doseStatus == .taken }.count
            let total = dayLogs.count

            days.append(DayAdherence(id: cursor, date: cursor, taken: taken, total: total))
            cursor = dayEnd
        }

        return days
    }

    private func buildMedicationAdherences(
        logs: [DoseLog],
        medications: [Medication],
        interval: DateInterval
    ) -> [MedicationAdherence] {
        return medications.compactMap { med in
            let medLogs = logs.filter { $0.medication == med }
            guard !medLogs.isEmpty else { return nil }

            let taken = medLogs.filter { $0.doseStatus == .taken }.count
            return MedicationAdherence(
                id: med.objectID,
                name: med.wrappedName,
                colorHex: med.wrappedColorHex,
                taken: taken,
                total: medLogs.count
            )
        }
        .sorted { $0.name < $1.name }
    }

    private func calculateOverallPercent() -> Double {
        let total = dayAdherences.reduce(0) { $0 + $1.total }
        let taken = dayAdherences.reduce(0) { $0 + $1.taken }
        guard total > 0 else { return 1.0 }
        return Double(taken) / Double(total)
    }
}
