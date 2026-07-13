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

        /// Terms of Use (EULA). Apple's standard EULA satisfies the auto-renewable-subscription
        /// requirement; swap for a hosted custom Terms page (neurotrocity.com/dosetrack/terms) once live.
        static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    }

    enum MedicationColors {
        /// The full colour palette offered when picking a medication's colour, and in the
        /// Colour Coding preferences screen where a colour can be assigned a tag (e.g.
        /// "Morning Batch", "Pain Relief"). The picker that shows these scrolls horizontally
        /// (see AddEditMedicationView.ColourPickerGrid).
        ///
        /// Curated deliberately to ~16 entries rather than a larger set: the goal is that
        /// every colour reads as visibly DIFFERENT from every other one at a small swatch
        /// size (a ~30pt filled tile or dot), not just different in hex value. The previous
        /// 24-colour palette had several near-duplicate blues/greens/oranges that were
        /// impossible to tell apart at a glance, which defeats the point of a colour tag —
        /// fewer, more distinct colours make a better legend than more, muddier ones. Each
        /// hue is also chosen to stay separable under common colour-vision deficiencies
        /// (no pair that relies solely on a red/green distinction, and warm/cool tones are
        /// paired with brightness or saturation differences, not hue alone). Spans: brand
        /// blue, a second clearly-different blue, red, orange, amber/yellow, warm green,
        /// teal/cyan, purple, magenta/pink, and a neutral brown/slate for a non-primary
        /// option. Reducing the count is intentional — do not re-expand this back toward
        /// two dozen without re-checking pairwise distinctness.
        static let palette: [String] = [
            "#5B8AF0", // brand blue
            "#0EA5E9", // sky blue — clearly distinct from brand blue (lighter, more cyan)
            "#E63946", // red
            "#F97316", // orange
            "#FFC93C", // amber / yellow
            "#588157", // warm green
            "#14B8A6", // teal / cyan
            "#7C5CD6", // purple
            "#EC4899", // magenta / pink
            "#264653", // deep slate — neutral, dark, non-primary option
            "#B5838D", // dusty rose — distinct from both red and pink by desaturation
            "#8B5E34", // brown — neutral warm option
            "#2E86AB", // steel blue — third, deeper blue distinct from the two above
            "#E76F51", // burnt coral — distinct from red/orange by warmth and saturation
            "#A78BFA", // lavender — distinct from purple by lightness
            "#84CC16", // lime — distinct from warm green and teal by hue and brightness
        ]
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
