// DoseTrack/Utilities/TimeFormatting.swift
// Central place every screen goes through to render a clock time, so the
// Preferences > Time Format setting ("System Default" / "12-hour" / "24-hour")
// actually takes effect everywhere instead of only in the setting itself.
import Foundation

enum TimeFormatPreference {
    static let userDefaultsKey = "timeFormat"

    /// Formats `date`'s time-of-day per the user's stored preference (`"system"`, `"12h"`,
    /// or `"24h"`), reading `UserDefaults` directly so it can be called from model code
    /// and other non-View contexts, not just SwiftUI views with `@AppStorage`.
    static func string(for date: Date, preference: String? = nil) -> String {
        let pref = preference ?? UserDefaults.standard.string(forKey: userDefaultsKey) ?? "system"
        switch pref {
        case "12h":
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "h:mm a"
            return f.string(from: date)
        case "24h":
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "HH:mm"
            return f.string(from: date)
        default:
            return date.formatted(date: .omitted, time: .shortened)
        }
    }
}

extension Date {
    /// Time-of-day formatted per the user's Preferences > Time Format setting.
    var appFormattedTime: String { TimeFormatPreference.string(for: self) }
}
