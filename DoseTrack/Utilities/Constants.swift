// DoseTrack/Utilities/Constants.swift
import Foundation

enum Constants {
    enum AppGroup {
        static let identifier = "group.com.robbrown.dosetrack"
    }

    enum StoreKit {
        static let proMonthly = "com.robbrown.dosetrack.pro.monthly"
        static let proAnnual = "com.robbrown.dosetrack.pro.annual"
    }

    enum UserDefaultsKeys {
        static let isProSubscriber = "isProSubscriber"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let lastNotificationRefresh = "lastNotificationRefresh"
    }

    enum FreeTier {
        static let maxMedications = 5
    }

    enum DeveloperOptions {
        /// Tap the Settings > About > Version row this many times to reveal the passcode
        /// prompt for the hidden Developer Options screen (Pro / caregiver override toggles).
        static let unlockTapCount = 7
        /// Not meant to be cryptographically secure — this only needs to keep casual
        /// TestFlight testers and App Review from stumbling into dev-only toggles, not
        /// resist a determined attacker. Change it if it leaks.
        static let passcode = "milli2026"
    }

    enum ExternalLinks {
        /// Pre-launch placeholder — swap for the real App Store listing URL once live.
        static let appStoreFallback = URL(string: "https://dosetrack.app/get-the-app")!

        /// Hosted privacy policy (GitHub Pages) — same URL registered in App Store Connect.
        static let privacyPolicy = URL(string: "https://4032332.github.io/dosetrack/privacy.html")!
    }

    enum Notification {
        static let categoryMedicationDue = "MEDICATION_DUE"
        static let actionTakeDose = "TAKE_DOSE"
        static let actionSkipDose = "SKIP_DOSE"
        static let actionSnooze30 = "SNOOZE_30"
    }

    enum Contraceptive {
        struct Preset: Identifiable {
            let id = UUID()
            let name: String
            let commonName: String       // Short label shown in the picker
            let intervalDays: Int        // How often it needs replacing/repeating
            let colorHex: String
        }

        static let presets: [Preset] = [
            Preset(name: "Nexplanon Implant", commonName: "Nexplanon (implant, 3 yrs)", intervalDays: 1095, colorHex: "#DDA0DD"),
            Preset(name: "Mirena IUD", commonName: "Mirena (IUD, 8 yrs)", intervalDays: 2920, colorHex: "#96CEB4"),
            Preset(name: "Kyleena IUD", commonName: "Kyleena (IUD, 5 yrs)", intervalDays: 1825, colorHex: "#4ECDC4"),
            Preset(name: "Liletta IUD", commonName: "Liletta (IUD, 8 yrs)", intervalDays: 2920, colorHex: "#96CEB4"),
            Preset(name: "Paragard IUD", commonName: "Paragard (copper IUD, 10 yrs)", intervalDays: 3650, colorHex: "#45B7D1"),
            Preset(name: "Depo-Provera Injection", commonName: "Depo-Provera (injection, 3 mo)", intervalDays: 91, colorHex: "#FF6B6B"),
            Preset(name: "Depo-SubQ Provera", commonName: "Depo-SubQ (injection, 3 mo)", intervalDays: 91, colorHex: "#FF6B6B"),
            Preset(name: "NuvaRing", commonName: "NuvaRing (ring, monthly)", intervalDays: 28, colorHex: "#FFEAA7"),
            Preset(name: "Annovera Ring", commonName: "Annovera (ring, 1 yr)", intervalDays: 365, colorHex: "#FFEAA7"),
            Preset(name: "Xulane Patch", commonName: "Xulane Patch (weekly)", intervalDays: 7, colorHex: "#98D8C8"),
            Preset(name: "Skyla IUD", commonName: "Skyla (IUD, 3 yrs)", intervalDays: 1095, colorHex: "#4ECDC4"),
        ]

        /// How far in advance to fire a lead-time warning notification.
        /// Returns 0 if no lead notification is needed.
        static func leadDays(for intervalDays: Int) -> Int {
            if intervalDays > 365 { return 30 }   // >1 year  → 1 month warning
            if intervalDays > 30  { return 14 }   // >1 month → 2 week warning
            return 0
        }
    }
}
