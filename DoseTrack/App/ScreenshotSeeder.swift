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
        GuestMode.activate()

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

        // Panadeine Forte — as-needed ONLY (no schedule). Exercises Today's "As Needed" section and
        // confirms a PRN item never appears in the timed lists.
        let panadeine = Medication.create(in: context, name: "Panadeine Forte", dosage: "500mg",
                                          unit: "tablet", colorHex: "#E63946")
        panadeine.currentCount = 24
        panadeine.refillThreshold = 5
        panadeine.allowsAsNeeded = true
        panadeine.storedQuantityPerDose = 1
        panadeine.totalDosesPerDay = 0

        // Ibuprofen — scheduled AND as-needed, the "both" case: it shows in the morning list and in
        // As Needed, so extra doses can be logged on top of the regular one.
        let ibuprofen = Medication.create(in: context, name: "Ibuprofen", dosage: "200mg",
                                          unit: "tablet", colorHex: "#F97316")
        ibuprofen.currentCount = 30
        ibuprofen.refillThreshold = 10
        ibuprofen.allowsAsNeeded = true
        ibuprofen.storedQuantityPerDose = 1
        ibuprofen.totalDosesPerDay = 1
        Schedule.create(in: context, medication: ibuprofen, hour: 7, minute: 30)

        // A vitamin and a supplement, each with a missed dose — proves missing them leaves the
        // headline adherence percentage untouched.
        let vitaminC = Medication.create(in: context, name: "Vitamin C", dosage: "1000mg",
                                         unit: "tablet", colorHex: "#FFC93C", kind: .vitamin)
        vitaminC.currentCount = 60
        vitaminC.storedQuantityPerDose = 1
        vitaminC.totalDosesPerDay = 1
        Schedule.create(in: context, medication: vitaminC, hour: 8, minute: 15)

        let magnesium = Medication.create(in: context, name: "Magnesium Glycinate", dosage: "",
                                          unit: "scoop", colorHex: "#14B8A6", kind: .supplement)
        magnesium.currentCount = 40
        magnesium.storedQuantityPerDose = 1
        magnesium.totalDosesPerDay = 1
        Schedule.create(in: context, medication: magnesium, hour: 21, minute: 30)

        // Ad-hoc doses already logged today, so the As Needed row shows its "2 taken today" state.
        for _ in 0..<2 {
            DoseLog.create(in: context, medication: panadeine, scheduledAt: now,
                           status: .taken, isAsNeeded: true).notes = "Headache"
        }

        // Two weeks of history across all items for the History chart.
        // Includes the vitamin and supplement so History's per-item breakdown actually exercises
        // the "not counted in score" path — without logs they'd be filtered out of the breakdown
        // entirely and that labelling would never render.
        let meds = [metformin, lisinopril, vitaminD, atorvastatin, vitaminC, magnesium]

        // "-MarketingScreenshots" seeds a clean SUCCESS state instead of the usual varied one.
        //
        // The App Store screenshots previously showed the app failing — the lead image had
        // "0 of 5 doses taken", 0%, and three red "Missed" badges, on a listing whose whole promise
        // is "Never miss a dose". A store screenshot has to show the outcome someone wants, not a
        // realistic-but-discouraging middle state, so this mode logs every scheduled dose as taken
        // (today included) to produce a full green week and a 100% ring.
        let marketing = ProcessInfo.processInfo.arguments.contains("-MarketingScreenshots")

        for daysAgo in 1...14 {
            for med in meds {
                let status: DoseStatus
                if marketing {
                    status = .taken
                } else {
                    let roll = Int.random(in: 0..<10)
                    status = roll < 7 ? .taken : (roll < 9 ? .skipped : .missed)
                }
                DoseLog.create(in: context, medication: med,
                                scheduledAt: time(hour: 8, minute: 0, daysAgo: daysAgo), status: status)
            }
        }

        if marketing {
            // Today's doses too, so the Today tab reads "all done" rather than a list of misses.
            // Any already-logged dose is skipped so the earlier per-medication seeding above
            // (e.g. Metformin's morning dose) doesn't get duplicated.
            //
            // Iterates EVERY active medication rather than the `meds` history array: Ibuprofen is
            // both scheduled and as-needed, so it isn't in that array, and leaving it out left one
            // dose unticked — the ring read "7 of 8", which is exactly the not-quite-succeeding
            // state these marketing shots exist to avoid.
            let calendar = Calendar.current
            let startOfToday = calendar.startOfDay(for: now)
            let allActive = (try? context.fetch(Medication.fetchRequest()))?.filter { $0.isActive } ?? []
            for med in allActive {
                for schedule in med.schedulesArray where schedule.isEnabled {
                    guard let scheduledAt = calendar.date(
                        bySettingHour: Int(schedule.hour), minute: Int(schedule.minute),
                        second: 0, of: now
                    ) else { continue }
                    let alreadyLogged = med.doseLogsArray.contains { log in
                        guard let logged = log.scheduledAt else { return false }
                        return logged >= startOfToday &&
                               calendar.isDate(logged, equalTo: scheduledAt, toGranularity: .minute)
                    }
                    guard !alreadyLogged else { continue }
                    DoseLog.create(in: context, medication: med,
                                   scheduledAt: scheduledAt, status: .taken)
                }
            }
        }

        context.saveOrReport()
    }
}
#endif
