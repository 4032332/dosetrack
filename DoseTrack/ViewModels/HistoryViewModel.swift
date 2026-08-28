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
    let kind: MedicationKind
    /// Count of ad-hoc doses in range, shown alongside the rate rather than folded into it —
    /// "12 as needed" is useful information for a doctor, but it isn't an adherence figure.
    let asNeededCount: Int

    var percent: Double {
        guard total > 0 else { return 1.0 }
        return Double(taken) / Double(total)
    }

    /// Vitamins and supplements still get a take-rate here, but the UI marks it as excluded from
    /// the headline score (see `HistoryView`) so the two numbers never look contradictory.
    var countsTowardOverall: Bool { kind.affectsAdherence }

    /// True when this row has nothing but as-needed doses — there's no rate to show, only a count.
    var isAsNeededOnly: Bool { total == 0 && asNeededCount > 0 }
}

/// A single logged dose, for the drill-down detail views (per medication / per day).
struct DoseHistoryEntry: Identifiable {
    let id: NSManagedObjectID
    let medicationName: String
    let colorHex: String
    let scheduledAt: Date
    let loggedAt: Date?
    let status: DoseStatus
    let isBackdated: Bool
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

    private var context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
        updateDateRange()
        refresh()
    }

    // MARK: - Public

    /// Swaps the underlying store this view model reads against (e.g. when a caregiver
    /// switches between their own account and an overseen patient's separate local store) and
    /// refreshes immediately so the UI reflects the new store's data.
    func updateContext(_ newContext: NSManagedObjectContext) {
        guard newContext !== context else { return }
        context = newContext
        refresh()
    }

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

    // MARK: - Drill-down detail

    /// Every logged dose for one medication over the current range, newest first — used by the
    /// per-medication detail so the user can see exactly when each dose was taken/skipped/missed.
    func entries(forMedication objectID: NSManagedObjectID) -> [DoseHistoryEntry] {
        guard let med = try? context.existingObject(with: objectID) as? Medication else { return [] }
        return fetchLogs(in: effectiveDateInterval())
            .filter { $0.medication == med }
            .sorted { ($0.scheduledAt ?? .distantPast) > ($1.scheduledAt ?? .distantPast) }
            .map {
                DoseHistoryEntry(id: $0.objectID, medicationName: med.wrappedName, colorHex: med.wrappedColorHex,
                                 scheduledAt: $0.scheduledAt ?? Date(), loggedAt: $0.loggedAt, status: $0.doseStatus,
                                 isBackdated: $0.isBackdated)
            }
    }

    /// Every logged dose on a single calendar day, earliest first — used by the calendar day tap.
    func entries(forDay day: Date) -> [DoseHistoryEntry] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return fetchLogs(in: DateInterval(start: start, end: end))
            .sorted { ($0.scheduledAt ?? .distantPast) < ($1.scheduledAt ?? .distantPast) }
            .map { log in
                DoseHistoryEntry(id: log.objectID, medicationName: log.medication?.wrappedName ?? "—",
                                 colorHex: log.medication?.wrappedColorHex ?? "#5B8AF0",
                                 scheduledAt: log.scheduledAt ?? Date(), loggedAt: log.loggedAt, status: log.doseStatus,
                                 isBackdated: log.isBackdated)
            }
    }

    // MARK: - Backdated correction

    /// Corrects a past dose's status from the History detail view — see
    /// `DoseLoggingService.backdateEdit` for why this is tracked distinctly from a same-day log.
    func backdateEdit(entryId: NSManagedObjectID, newStatus: DoseStatus, pushUserId: UUID?) {
        guard let log = try? context.existingObject(with: entryId) as? DoseLog else { return }
        DoseLoggingService.shared.backdateEdit(
            log: log, newStatus: newStatus, notes: nil, context: context, pushUserId: pushUserId
        )
        refresh()
    }

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

            // Only scheduled medication doses are scored — as-needed doses and vitamins/supplements
            // are filtered out here (see DoseLog.countsTowardAdherence for why), which is what keeps
            // the daily bars and the headline percentage consistent with each other.
            let dayLogs = logs.filter { log in
                guard let scheduled = log.scheduledAt else { return false }
                guard scheduled >= cursor && scheduled < dayEnd else { return false }
                return log.countsTowardAdherence
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

            // Split rather than filter: as-needed doses are reported as a separate count so the
            // rate stays a true scheduled-dose rate, while the PRN activity is still visible.
            let scheduledLogs = medLogs.filter { !$0.isAsNeeded }
            let asNeededCount = medLogs.count - scheduledLogs.count

            let taken = scheduledLogs.filter { $0.doseStatus == .taken }.count
            return MedicationAdherence(
                id: med.objectID,
                name: med.wrappedName,
                colorHex: med.wrappedColorHex,
                taken: taken,
                total: scheduledLogs.count,
                kind: med.medicationKind,
                asNeededCount: asNeededCount
            )
        }
        // Group by kind first so the breakdown reads Medications → Vitamins → Supplements, matching
        // the Medications tab's grouping, then alphabetically within each group.
        .sorted { lhs, rhs in
            if lhs.kind != rhs.kind {
                return kindOrder(lhs.kind) < kindOrder(rhs.kind)
            }
            return lhs.name < rhs.name
        }
    }

    private func kindOrder(_ kind: MedicationKind) -> Int {
        switch kind {
        case .medication: return 0
        case .vitamin:    return 1
        case .supplement: return 2
        }
    }

    /// Derived from `dayAdherences`, which has already excluded as-needed doses and
    /// vitamins/supplements — so the headline number and the daily bars can never disagree about
    /// what they're measuring.
    private func calculateOverallPercent() -> Double {
        let total = dayAdherences.reduce(0) { $0 + $1.total }
        let taken = dayAdherences.reduce(0) { $0 + $1.taken }
        guard total > 0 else { return 1.0 }
        return Double(taken) / Double(total)
    }
}
