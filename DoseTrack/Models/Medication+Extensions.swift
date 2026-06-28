// DoseTrack/Models/Medication+Extensions.swift
import CoreData
import SwiftUI

extension Medication {

    // MARK: - Factory

    @discardableResult
    static func create(
        in context: NSManagedObjectContext,
        name: String,
        dosage: String,
        unit: String = "pill",
        colorHex: String = "#5B8AF0"
    ) -> Medication {
        let med = Medication(context: context)
        med.id = UUID()
        med.name = name
        med.dosage = dosage
        med.unit = unit
        med.colorHex = colorHex
        med.isActive = true
        med.currentCount = 0
        med.refillThreshold = 7
        med.totalDosesPerDay = 1
        med.sortOrder = 0
        med.createdAt = Date()
        return med
    }

    // MARK: - Computed

    var color: Color {
        Color(hex: colorHex ?? "#5B8AF0")
    }

    var isRefillWarning: Bool {
        currentCount > 0 && currentCount <= refillThreshold
    }

    var wrappedName: String { name ?? "" }
    var wrappedDosage: String { dosage ?? "" }
    var wrappedUnit: String { unit ?? "pill" }
    var wrappedColorHex: String { colorHex ?? "#5B8AF0" }
    var wrappedNotes: String { notes ?? "" }

    var schedulesArray: [Schedule] {
        (schedules as? Set<Schedule>)?.sorted { $0.hour < $1.hour } ?? []
    }

    var doseLogsArray: [DoseLog] {
        (doseLogs as? Set<DoseLog>)?.sorted {
            ($0.scheduledAt ?? .distantPast) < ($1.scheduledAt ?? .distantPast)
        } ?? []
    }
}
