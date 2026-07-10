// DoseTrack/Models/ColorTagStore.swift
import Foundation

/// A user-defined label attached to one colour from `Constants.MedicationColors.palette` —
/// e.g. "#FFEAA7" → "Morning Batch". Purely a personal legend: it doesn't change how a
/// medication behaves, just gives the colour swatches meaning the user chose (by time of day,
/// by drug class, medication vs. vitamin vs. supplement, etc.).
struct ColorTag: Identifiable, Codable, Equatable {
    var id = UUID()
    var colorHex: String
    var name: String
}

/// App-wide (not per-medication) colour → tag assignments. Same UserDefaults-backed,
/// JSON-encoded persistence pattern as `MealTimes`.
struct ColorTagStore: Equatable {
    var tags: [ColorTag]

    static let empty = ColorTagStore(tags: [])

    /// Common starting suggestions shown as quick-add chips — not pre-assigned to any colour,
    /// since the user picks the colour first, then names it.
    static let suggestedNames: [String] = [
        "Medication", "Vitamin", "Supplement",
        "Morning Batch", "Night Batch",
        "Pain Relief", "Mental Health", "Heart & Blood Pressure", "Other",
    ]

    private static let defaultsKey = "colorTagAssignments"

    static func load(from defaults: UserDefaults = .standard) -> ColorTagStore {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([ColorTag].self, from: data)
        else { return .empty }
        return ColorTagStore(tags: decoded)
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(tags) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    /// The tag name assigned to a colour, if any — used to label swatches in the medication
    /// colour picker.
    func name(forHex hex: String) -> String? {
        tags.first { $0.colorHex.caseInsensitiveCompare(hex) == .orderedSame }?.name
    }
}
