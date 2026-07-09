// DoseTrack/App/ScreenshotSeeder.swift
#if DEBUG
import CoreData
import Foundation

/// Populates realistic-looking sample data for App Store screenshots. Only runs when
/// launched with "-SeedScreenshotData" (set via a dedicated Xcode scheme, never present
/// in a normal run or a release build), so it can never affect real users or TestFlight.
enum ScreenshotSeeder {

    /// Reads "-ScreenshotTab <name>" from launch arguments and jumps MainTabView there,
    /// so each screenshot can be captured with a fresh launch instead of needing UI
    /// automation to tap through tabs.
    static func selectTabIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-ScreenshotTab"), idx + 1 < args.count else { return }
        let name = args[idx + 1]
        let tab: MainTabView.Tab
        switch name {
        case "medications": tab = .medications
        case "restock":     tab = .restock
        case "history":     tab = .history
        case "settings":    tab = .settings
        default:            tab = .today
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            TabNavigator.shared.selectedTab = tab
        }
    }

    static func seedIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-SeedScreenshotData") else { return }

        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        UserDefaults.standard.set(true, forKey: "guestMode")

        let context = PersistenceController.shared.viewContext

        // Idempotent: re-launching with the same flag (e.g. once per screenshot tab)
        // shouldn't duplicate the sample data every time.
        let existingCount = (try? context.count(for: Medication.fetchRequest())) ?? 0
        guard existingCount == 0 else { return }

        let calendar = Calendar.current
        let now = Date()

        func time(hour: Int, minute: Int, daysAgo: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }

        // Metformin — twice daily, taken this morning, due again tonight.
        let metformin = Medication.create(in: context, name: "Metformin", dosage: "500mg",
                                           unit: "pill", colorHex: "#5B8AF0")
        metformin.currentCount = 42
        metformin.refillThreshold = 10
        metformin.totalDosesPerDay = 2
        let metforminAM = Schedule.create(in: context, medication: metformin, hour: 8, minute: 0)
        let metforminPM = Schedule.create(in: context, medication: metformin, hour: 20, minute: 0)
        DoseLog.create(in: context, medication: metformin, scheduledAt: time(hour: 8, minute: 0), status: .taken)
        _ = metforminAM; _ = metforminPM

        // Lisinopril — once daily, taken.
        let lisinopril = Medication.create(in: context, name: "Lisinopril", dosage: "10mg",
                                            unit: "pill", colorHex: "#4CAF50")
        lisinopril.currentCount = 18
        lisinopril.refillThreshold = 7
        lisinopril.totalDosesPerDay = 1
        Schedule.create(in: context, medication: lisinopril, hour: 9, minute: 0)
        DoseLog.create(in: context, medication: lisinopril, scheduledAt: time(hour: 9, minute: 0), status: .taken)

        // Vitamin D — once daily, missed yesterday (shows adherence chart variety).
        let vitaminD = Medication.create(in: context, name: "Vitamin D3", dosage: "2000 IU",
                                          unit: "supplement", colorHex: "#FFB300")
        vitaminD.currentCount = 55
        vitaminD.refillThreshold = 14
        vitaminD.totalDosesPerDay = 1
        Schedule.create(in: context, medication: vitaminD, hour: 8, minute: 30)
        DoseLog.create(in: context, medication: vitaminD, scheduledAt: time(hour: 8, minute: 30), status: .taken)

        // Atorvastatin — evening dose, still upcoming today.
        let atorvastatin = Medication.create(in: context, name: "Atorvastatin", dosage: "20mg",
                                              unit: "pill", colorHex: "#AB47BC")
        atorvastatin.currentCount = 5
        atorvastatin.refillThreshold = 7
        atorvastatin.totalDosesPerDay = 1
        Schedule.create(in: context, medication: atorvastatin, hour: 21, minute: 0)

        // Two weeks of varied history across all four medications for the History chart.
        let meds = [metformin, lisinopril, vitaminD, atorvastatin]
        for daysAgo in 1...14 {
            for med in meds {
                let roll = Int.random(in: 0..<10)
                let status: DoseStatus = roll < 7 ? .taken : (roll < 9 ? .skipped : .missed)
                DoseLog.create(in: context, medication: med,
                                scheduledAt: time(hour: 8, minute: 0, daysAgo: daysAgo), status: status)
            }
        }

        context.saveOrReport()
    }
}
#endif
