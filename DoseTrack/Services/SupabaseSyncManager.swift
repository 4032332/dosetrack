// DoseTrack/Services/SupabaseSyncManager.swift
// Bidirectional sync between CoreData (local) and Supabase (remote).
// Strategy: upsert on every local change; pull-and-merge on login.
// Photos are stored in Supabase Storage; paths are saved on the medication row.

import Foundation
import CoreData
import Supabase
import WidgetKit

@MainActor
final class SupabaseSyncManager: ObservableObject {

    static let shared = SupabaseSyncManager()
    private init() {}

    private var client: SupabaseClient { AuthManager.shared.client }

    // MARK: - Full pull on login

    /// Called after a successful sign-in. Pulls all remote data and merges into CoreData.
    func pullAll(context: NSManagedObjectContext, forUserId: UUID? = nil) async {
        guard AuthManager.shared.isSignedIn, !AuthManager.shared.isGuest else { return }
        guard let targetUserId = forUserId ?? AuthManager.shared.session?.user.id else { return }
        do {
            let pullStartedAt = Date()
            async let meds    = fetchRemoteMedications(userId: targetUserId)
            async let scheds  = fetchRemoteSchedules(userId: targetUserId)
            async let logs    = fetchRemoteDoseLogs(userId: targetUserId, since: Self.lastDoseLogSyncAt(for: targetUserId))
            async let settings = fetchRemoteSettings(userId: targetUserId)
            let (m, s, l, st) = try await (meds, scheds, logs, settings)
            mergeMedications(m, context: context)
            mergeSchedules(s, context: context)
            mergeDoseLogs(l, context: context)
            // Heal any duplicate schedules that a past edit left behind before orphan cleanup
            // existed — collapses same-signature schedules so Today stops showing repeats.
            dedupeSchedules(context: context)
            // Only apply settings when syncing the signed-in user's own account — applying a
            // linked patient's UserDefaults onto the caregiver's own device would silently
            // overwrite the caregiver's theme/name/preferences. See risk note above.
            if forUserId == nil, let st { applySettings(st) }
            try? context.save()
            WidgetCenter.shared.reloadAllTimelines()
            Self.setLastDoseLogSyncAt(pullStartedAt, for: targetUserId)
        } catch {
            print("SupabaseSync pullAll error: \(error)")
        }
    }

    // MARK: - Incremental dose-log sync bookkeeping

    private static func lastDoseLogSyncKey(for userId: UUID) -> String {
        "lastDoseLogSyncAt.\(userId.uuidString)"
    }

    /// `nil` on a user's first sync — `fetchRemoteDoseLogs` then falls back to a 90-day window
    /// instead of pulling every dose log the user has ever logged on every launch.
    private static func lastDoseLogSyncAt(for userId: UUID) -> Date? {
        let interval = UserDefaults.standard.double(forKey: lastDoseLogSyncKey(for: userId))
        return interval > 0 ? Date(timeIntervalSince1970: interval) : nil
    }

    private static func setLastDoseLogSyncAt(_ date: Date, for userId: UUID) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: lastDoseLogSyncKey(for: userId))
    }

    // MARK: - Push individual records

    func pushMedication(_ med: Medication, forUserId: UUID? = nil) async {
        guard AuthManager.shared.isSignedIn, !AuthManager.shared.isGuest,
              let id = med.id,
              let targetUserId = forUserId ?? AuthManager.shared.session?.user.id else { return }
        let row = MedicationRow(medication: med, userId: targetUserId)
        do {
            try await client.from("medications").upsert(row).execute()
            let currentIds = med.schedulesArray.compactMap { $0.id?.uuidString }
            for schedule in med.schedulesArray {
                await pushSchedule(schedule, medicationId: id, userId: targetUserId)
            }
            // Delete any remote schedule rows for this medication that no longer exist locally.
            // Editing a medication replaces its schedules with new-UUID rows; without this the
            // old rows were left orphaned in Supabase and re-materialized as DUPLICATE schedules
            // on the next pull (one extra Today row per past edit, and stale-time reminders).
            var deleteQuery = client.from("schedules").delete().eq("medication_id", value: id.uuidString)
            if !currentIds.isEmpty {
                deleteQuery = deleteQuery.not("id", operator: .in, value: "(\(currentIds.joined(separator: ",")))")
            }
            try await deleteQuery.execute()
        } catch { print("pushMedication error: \(error)") }
    }

    /// Deletes a single schedule row remotely (best-effort; guests/unauth'd are no-ops).
    func deleteSchedule(id: UUID) async {
        guard AuthManager.shared.isSignedIn, !AuthManager.shared.isGuest else { return }
        do {
            try await client.from("schedules").delete().eq("id", value: id.uuidString).execute()
        } catch { print("deleteSchedule error: \(error)") }
    }

    /// Collapses duplicate schedules — same time / frequency / days / interval on one medication —
    /// that accumulated before orphaned remote rows were cleaned up. Keeps one per signature and
    /// deletes the rest locally and remotely. Idempotent; safe to run on every pull.
    @discardableResult
    func dedupeSchedules(context: NSManagedObjectContext) -> Int {
        let req = Medication.fetchRequest()
        guard let meds = try? context.fetch(req) else { return 0 }
        var removedRemoteIds: [UUID] = []
        for med in meds {
            var seen = Set<String>()
            for sched in med.schedulesArray {
                let key = "\(sched.hour):\(sched.minute):\(sched.wrappedFrequency):\(sched.daysOfWeekArray.sorted())\(sched.intervalDays):\(sched.isEnabled)"
                if seen.contains(key) {
                    if let sid = sched.id { removedRemoteIds.append(sid) }
                    context.delete(sched)
                } else {
                    seen.insert(key)
                }
            }
        }
        guard !removedRemoteIds.isEmpty else { return 0 }
        if context.hasChanges { try? context.save() }
        Task { for sid in removedRemoteIds { await deleteSchedule(id: sid) } }
        return removedRemoteIds.count
    }

    func pushSchedule(_ schedule: Schedule, medicationId: UUID, userId: UUID) async {
        let row = ScheduleRow(schedule: schedule, medicationId: medicationId, userId: userId)
        do {
            try await client.from("schedules").upsert(row).execute()
        } catch { print("pushSchedule error: \(error)") }
    }

    func pushDoseLog(_ log: DoseLog, forUserId: UUID? = nil) async {
        guard AuthManager.shared.isSignedIn, !AuthManager.shared.isGuest,
              let targetUserId = forUserId ?? AuthManager.shared.session?.user.id else { return }
        let row = DoseLogRow(log: log, userId: targetUserId)
        do {
            try await client.from("dose_logs").upsert(row).execute()
        } catch { print("pushDoseLog error: \(error)") }
    }

    /// Dose logs updated after `since` (nil = push everything). Pure selection logic, split
    /// out for testing since `NSManagedObject` fetches aren't easily unit-testable directly.
    static func unsyncedLogs(_ logs: [DoseLog], since: Date?) -> [DoseLog] {
        guard let since else { return logs }
        return logs.filter { ($0.updatedAt ?? .distantPast) > since }
    }

    private static func lastPushSyncKey(for userId: UUID) -> String {
        "lastDoseLogPushAt.\(userId.uuidString)"
    }

    /// Pushes any locally-updated dose logs that haven't been pushed since the last successful
    /// call — covers doses logged while the app was closed (e.g. the widget's Mark Taken
    /// intent), which otherwise only ever get written locally and never reach Supabase.
    func pushUnsyncedLocalChanges(context: NSManagedObjectContext, forUserId: UUID? = nil) async {
        guard AuthManager.shared.isSignedIn, !AuthManager.shared.isGuest,
              let targetUserId = forUserId ?? AuthManager.shared.session?.user.id else { return }
        let sinceInterval = UserDefaults.standard.double(forKey: Self.lastPushSyncKey(for: targetUserId))
        let since = sinceInterval > 0 ? Date(timeIntervalSince1970: sinceInterval) : nil

        let logs = (try? context.fetch(DoseLog.fetchRequest())) ?? []
        let toPush = Self.unsyncedLogs(logs, since: since)
        let pushStartedAt = Date()
        for log in toPush {
            await pushDoseLog(log, forUserId: forUserId)
        }
        UserDefaults.standard.set(pushStartedAt.timeIntervalSince1970, forKey: Self.lastPushSyncKey(for: targetUserId))
    }

    func pushSettings() async {
        guard AuthManager.shared.isSignedIn, !AuthManager.shared.isGuest,
              let userId = AuthManager.shared.session?.user.id else { return }
        let row = UserSettingsRow(userId: userId)
        do {
            try await client.from("user_settings").upsert(row).execute()
        } catch { print("pushSettings error: \(error)") }
    }

    func deleteMedication(id: UUID) async {
        guard AuthManager.shared.isSignedIn, !AuthManager.shared.isGuest else { return }
        do {
            try await client.from("medications")
                .delete().eq("id", value: id.uuidString).execute()
        } catch { print("deleteMedication error: \(error)") }
    }

    /// Deletes all of the signed-in user's rows from Supabase. Best-effort; guarded so guests
    /// (no server data) and unauth'd states are no-ops. Called by Settings > Delete All Data —
    /// without this, the local wipe alone was undone by the very next pullAll() on relaunch.
    func deleteAllRemoteData() async {
        guard AuthManager.shared.isSignedIn, !AuthManager.shared.isGuest,
              let userId = AuthManager.shared.session?.user.id else { return }
        let uid = userId.uuidString
        for table in ["dose_logs", "schedules", "medications"] {
            do { try await client.from(table).delete().eq("user_id", value: uid).execute() }
            catch { print("deleteAllRemoteData(\(table)) error: \(error)") }
        }
    }

    // MARK: - Photo upload / download

    func uploadPhoto(_ data: Data, forMedicationId medId: UUID, type: PhotoType) async -> String? {
        guard let userId = AuthManager.shared.session?.user.id else { return nil }
        let path = "\(userId)/medications/\(medId)/\(type.rawValue).jpg"
        do {
            try await client.storage.from("dosetrack-media")
                .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
            return path
        } catch { print("uploadPhoto error: \(error)"); return nil }
    }

    func downloadPhoto(path: String) async -> Data? {
        do {
            return try await client.storage.from("dosetrack-media").download(path: path)
        } catch { print("downloadPhoto error: \(error)"); return nil }
    }

    enum PhotoType: String { case bottle, escript }

    // MARK: - Remote fetch helpers

    private func fetchRemoteMedications(userId: UUID) async throws -> [MedicationRow] {
        try await client.from("medications").select().eq("user_id", value: userId.uuidString).execute().value
    }
    private func fetchRemoteSchedules(userId: UUID) async throws -> [ScheduleRow] {
        try await client.from("schedules").select().eq("user_id", value: userId.uuidString).execute().value
    }
    /// - Parameter since: only rows updated after this date are pulled. `nil` (a user's first
    ///   sync on this device) falls back to a 90-day window rather than the full history —
    ///   older logs are still available on demand via History/export, which read the local
    ///   store directly and aren't affected by this window.
    private func fetchRemoteDoseLogs(userId: UUID, since: Date?) async throws -> [DoseLogRow] {
        let cutoff = since ?? Date(timeIntervalSinceNow: -90 * 86400)
        return try await client.from("dose_logs")
            .select()
            .eq("user_id", value: userId.uuidString)
            .gte("updated_at", value: ISO8601DateFormatter().string(from: cutoff))
            .execute().value
    }
    private func fetchRemoteSettings(userId: UUID) async throws -> UserSettingsRow? {
        let rows: [UserSettingsRow] = try await client.from("user_settings").select().eq("user_id", value: userId.uuidString).execute().value
        return rows.first
    }

    // MARK: - CoreData merge helpers

    private func mergeMedications(_ rows: [MedicationRow], context: NSManagedObjectContext) {
        for row in rows {
            guard let uuid = UUID(uuidString: row.id) else { continue }
            let req = Medication.fetchRequest()
            req.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
            let existing = (try? context.fetch(req))?.first

            // Newer-wins conflict resolution: if the local record was touched more recently
            // than this remote row, keep it as-is rather than blindly overwriting from a stale
            // pull — this is what previously let a stale remote row resurrect a medication the
            // user had just soft-deleted, and more generally clobbered any offline edit.
            if let existing, let localUpdatedAt = existing.updatedAt, localUpdatedAt >= row.updatedAt {
                continue
            }

            let med = existing ?? Medication(context: context)
            med.id           = uuid
            med.name         = row.name
            med.dosage       = row.dosage
            med.unit         = row.unit
            med.colorHex     = row.colorHex
            med.notes        = row.notes
            med.isActive     = row.isActive
            med.currentCount = Int32(row.currentCount)
            med.refillThreshold = Int32(row.refillThreshold)
            med.sortOrder    = Int32(row.sortOrder)
            med.updatedAt    = row.updatedAt
            // Download photos lazily — store path in a transient or re-download on demand
            if let path = row.photoPath {
                Task {
                    if let data = await self.downloadPhoto(path: path) {
                        await MainActor.run { med.photoData = data; try? context.save() }
                    }
                }
            }
            if let path = row.escriptPath {
                Task {
                    if let data = await self.downloadPhoto(path: path) {
                        await MainActor.run { med.escriptData = data; try? context.save() }
                    }
                }
            }
        }
    }

    #if DEBUG
    /// Test-only entry point into the private merge logic. Never compiled into release builds.
    func mergeMedicationsForTesting(_ rows: [MedicationRow], context: NSManagedObjectContext) {
        mergeMedications(rows, context: context)
    }
    #endif

    private func mergeSchedules(_ rows: [ScheduleRow], context: NSManagedObjectContext) {
        for row in rows {
            guard let uuid = UUID(uuidString: row.id),
                  let medUUID = UUID(uuidString: row.medicationId) else { continue }
            let medReq = Medication.fetchRequest()
            medReq.predicate = NSPredicate(format: "id == %@", medUUID as CVarArg)
            guard let med = (try? context.fetch(medReq))?.first else { continue }

            let req = Schedule.fetchRequest()
            req.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
            let existing = (try? context.fetch(req))?.first

            if let existing, let localUpdatedAt = existing.updatedAt, localUpdatedAt >= row.updatedAt {
                continue
            }

            let sched = existing ?? Schedule(context: context)
            sched.id           = uuid
            sched.hour         = row.hour
            sched.minute       = row.minute
            sched.frequency    = row.frequency
            sched.daysOfWeek   = row.daysOfWeek as NSArray
            sched.intervalDays = row.intervalDays
            sched.isEnabled    = row.isEnabled
            sched.medication   = med
            sched.updatedAt    = row.updatedAt
        }
    }

    private func mergeDoseLogs(_ rows: [DoseLogRow], context: NSManagedObjectContext) {
        for row in rows {
            guard let uuid = UUID(uuidString: row.id),
                  let medUUID = UUID(uuidString: row.medicationId) else { continue }
            let medReq = Medication.fetchRequest()
            medReq.predicate = NSPredicate(format: "id == %@", medUUID as CVarArg)
            guard let med = (try? context.fetch(medReq))?.first else { continue }

            let req = DoseLog.fetchRequest()
            req.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
            let existing = (try? context.fetch(req))?.first

            if let existing, let localUpdatedAt = existing.updatedAt, localUpdatedAt >= row.updatedAt {
                continue
            }

            let log = existing ?? DoseLog(context: context)
            log.id          = uuid
            log.scheduledAt = row.scheduledAt
            log.loggedAt    = row.loggedAt
            log.status      = row.status
            log.notes       = row.notes
            log.medication  = med
            log.updatedAt   = row.updatedAt
        }
    }

    private func applySettings(_ row: UserSettingsRow) {
        let d = UserDefaults.standard
        d.set(row.colorTheme,      forKey: "colorTheme")
        d.set(row.appearance,      forKey: "appearanceOverride")
        d.set(row.timeFormat,      forKey: "timeFormat")
        d.set(row.snoozeDuration,  forKey: "defaultSnoozeDuration")
        d.set(row.hapticsEnabled,  forKey: "hapticsEnabled")
        d.set(row.showDoseBadge,   forKey: "showDoseBadge")
        d.set(row.compactRows,     forKey: "compactRows")
        d.set(row.selectedAvatar,  forKey: "selectedAvatar")
        d.set(row.patientName,     forKey: "patientName")
        d.set(row.patientGender,   forKey: "patientGender")
        d.set(row.patientPhone,    forKey: "patientPhone")
        d.set(row.patientCountry,  forKey: "patientCountry")
        d.set(row.patientState,    forKey: "patientState")
        // `patient_dob` is a Postgres `date`, so it comes back as "yyyy-MM-dd" — NOT a full
        // ISO8601 timestamp. The previous code parsed it with ISO8601DateFormatter (which
        // returns nil for a date-only string) and then wrote `?? 0`, zeroing out the saved
        // date of birth on every pull. That was the DOB "won't save" bug: the save worked
        // fine, but the very next launch's pull clobbered it. Parse date-only (with an
        // ISO8601 fallback for any legacy full-timestamp rows), and if it somehow still
        // can't be parsed, leave the existing local value untouched rather than wiping it.
        if let dob = row.patientDob, let ts = DOBFormat.timestamp(from: dob) {
            d.set(ts, forKey: "patientDOBInterval")
        }
        let meals = MealTimes(
            wakeUp: MealTime(hour: row.mealWakeUpHour ?? MealTimes.default.wakeUp.hour, minute: row.mealWakeUpMinute ?? MealTimes.default.wakeUp.minute),
            breakfast: MealTime(hour: row.mealBreakfastHour ?? MealTimes.default.breakfast.hour, minute: row.mealBreakfastMinute ?? MealTimes.default.breakfast.minute),
            morningTea: MealTime(hour: row.mealMorningTeaHour ?? MealTimes.default.morningTea.hour, minute: row.mealMorningTeaMinute ?? MealTimes.default.morningTea.minute),
            lunch: MealTime(hour: row.mealLunchHour ?? MealTimes.default.lunch.hour, minute: row.mealLunchMinute ?? MealTimes.default.lunch.minute),
            afternoonTea: MealTime(hour: row.mealAfternoonTeaHour ?? MealTimes.default.afternoonTea.hour, minute: row.mealAfternoonTeaMinute ?? MealTimes.default.afternoonTea.minute),
            dinner: MealTime(hour: row.mealDinnerHour ?? MealTimes.default.dinner.hour, minute: row.mealDinnerMinute ?? MealTimes.default.dinner.minute),
            dessert: MealTime(hour: row.mealDessertHour ?? MealTimes.default.dessert.hour, minute: row.mealDessertMinute ?? MealTimes.default.dessert.minute),
            midnightSnack: MealTime(hour: row.mealMidnightSnackHour ?? MealTimes.default.midnightSnack.hour, minute: row.mealMidnightSnackMinute ?? MealTimes.default.midnightSnack.minute),
            bedtime: MealTime(hour: row.mealBedtimeHour ?? MealTimes.default.bedtime.hour, minute: row.mealBedtimeMinute ?? MealTimes.default.bedtime.minute)
        )
        meals.save(to: d)
    }
}

// MARK: - Codable row types (match Supabase column names exactly)

struct MedicationRow: Codable {
    var id: String
    var userId: String
    var name: String
    var dosage: String
    var unit: String
    var colorHex: String
    var notes: String
    var isActive: Bool
    var currentCount: Int
    var refillThreshold: Int
    var sortOrder: Int
    var photoPath: String?
    var escriptPath: String?
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, dosage, unit, notes
        case userId = "user_id"
        case colorHex = "color_hex"
        case isActive = "is_active"
        case currentCount = "current_count"
        case refillThreshold = "refill_threshold"
        case sortOrder = "sort_order"
        case photoPath = "photo_path"
        case escriptPath = "escript_path"
        case updatedAt = "updated_at"
    }

    init(medication: Medication, userId: UUID) {
        id             = medication.id?.uuidString ?? UUID().uuidString
        self.userId    = userId.uuidString
        name           = medication.wrappedName
        dosage         = medication.wrappedDosage
        unit           = medication.wrappedUnit
        colorHex       = medication.wrappedColorHex
        notes          = medication.wrappedNotes
        isActive       = medication.isActive
        currentCount   = Int(medication.currentCount)
        refillThreshold = Int(medication.refillThreshold)
        sortOrder      = Int(medication.sortOrder)
        photoPath      = nil   // set separately after upload
        escriptPath    = nil
        updatedAt      = medication.updatedAt ?? Date()
    }

    #if DEBUG
    /// Test-only factory — lets merge-logic tests construct a remote row without a real
    /// Medication/upload round-trip. Never compiled into release builds.
    static func testRow(id: String, isActive: Bool, name: String = "Remote", updatedAt: Date = Date()) -> MedicationRow {
        MedicationRow(
            id: id, userId: UUID().uuidString, name: name, dosage: "1", unit: "pill",
            colorHex: "#000000", notes: "", isActive: isActive, currentCount: 0,
            refillThreshold: 7, sortOrder: 0, updatedAt: updatedAt
        )
    }

    private init(
        id: String, userId: String, name: String, dosage: String, unit: String,
        colorHex: String, notes: String, isActive: Bool, currentCount: Int,
        refillThreshold: Int, sortOrder: Int, updatedAt: Date
    ) {
        self.id = id; self.userId = userId; self.name = name; self.dosage = dosage
        self.unit = unit; self.colorHex = colorHex; self.notes = notes; self.isActive = isActive
        self.currentCount = currentCount; self.refillThreshold = refillThreshold
        self.sortOrder = sortOrder; self.photoPath = nil; self.escriptPath = nil
        self.updatedAt = updatedAt
    }
    #endif
}

struct ScheduleRow: Codable {
    var id: String
    var userId: String
    var medicationId: String
    var hour: Int16
    var minute: Int16
    var frequency: String
    var daysOfWeek: [Int]
    var intervalDays: Int16
    var isEnabled: Bool
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, hour, minute, frequency
        case userId = "user_id"
        case medicationId = "medication_id"
        case daysOfWeek = "days_of_week"
        case intervalDays = "interval_days"
        case isEnabled = "is_enabled"
        case updatedAt = "updated_at"
    }

    init(schedule: Schedule, medicationId: UUID, userId: UUID) {
        id               = schedule.id?.uuidString ?? UUID().uuidString
        self.userId      = userId.uuidString
        self.medicationId = medicationId.uuidString
        hour             = schedule.hour
        minute           = schedule.minute
        frequency        = schedule.wrappedFrequency
        daysOfWeek       = schedule.daysOfWeekArray
        intervalDays     = schedule.intervalDays
        isEnabled        = schedule.isEnabled
        updatedAt        = schedule.updatedAt ?? Date()
    }
}

struct DoseLogRow: Codable {
    var id: String
    var userId: String
    var medicationId: String
    var scheduledAt: Date
    var loggedAt: Date
    var status: String
    var notes: String
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, status, notes
        case userId = "user_id"
        case medicationId = "medication_id"
        case scheduledAt = "scheduled_at"
        case loggedAt = "logged_at"
        case updatedAt = "updated_at"
    }

    init(log: DoseLog, userId: UUID) {
        id           = log.id?.uuidString ?? UUID().uuidString
        self.userId  = userId.uuidString
        medicationId = log.medication?.id?.uuidString ?? ""
        scheduledAt  = log.scheduledAt ?? Date()
        loggedAt     = log.loggedAt ?? Date()
        status       = log.status ?? "taken"
        notes        = log.notes ?? ""
        updatedAt    = log.updatedAt ?? Date()
    }
}

struct UserSettingsRow: Codable {
    var userId: String
    var colorTheme: String
    var appearance: String
    var timeFormat: String
    var snoozeDuration: Int
    var hapticsEnabled: Bool
    var showDoseBadge: Bool
    var compactRows: Bool
    var selectedAvatar: String
    var patientName: String
    var patientGender: String
    var patientDob: String?
    var patientPhone: String
    var patientCountry: String
    var patientState: String
    var mealBreakfastHour: Int?
    var mealBreakfastMinute: Int?
    var mealMorningTeaHour: Int?
    var mealMorningTeaMinute: Int?
    var mealLunchHour: Int?
    var mealLunchMinute: Int?
    var mealAfternoonTeaHour: Int?
    var mealAfternoonTeaMinute: Int?
    var mealDinnerHour: Int?
    var mealDinnerMinute: Int?
    var mealDessertHour: Int?
    var mealDessertMinute: Int?
    var mealMidnightSnackHour: Int?
    var mealMidnightSnackMinute: Int?
    var mealWakeUpHour: Int?
    var mealWakeUpMinute: Int?
    var mealBedtimeHour: Int?
    var mealBedtimeMinute: Int?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case colorTheme = "color_theme"
        case appearance
        case timeFormat = "time_format"
        case snoozeDuration = "snooze_duration"
        case hapticsEnabled = "haptics_enabled"
        case showDoseBadge = "show_dose_badge"
        case compactRows = "compact_rows"
        case selectedAvatar = "selected_avatar"
        case patientName = "patient_name"
        case patientGender = "patient_gender"
        case patientDob = "patient_dob"
        case patientPhone = "patient_phone"
        case patientCountry = "patient_country"
        case patientState = "patient_state"
        case mealBreakfastHour = "meal_breakfast_hour"
        case mealBreakfastMinute = "meal_breakfast_minute"
        case mealMorningTeaHour = "meal_morning_tea_hour"
        case mealMorningTeaMinute = "meal_morning_tea_minute"
        case mealLunchHour = "meal_lunch_hour"
        case mealLunchMinute = "meal_lunch_minute"
        case mealAfternoonTeaHour = "meal_afternoon_tea_hour"
        case mealAfternoonTeaMinute = "meal_afternoon_tea_minute"
        case mealDinnerHour = "meal_dinner_hour"
        case mealDinnerMinute = "meal_dinner_minute"
        case mealDessertHour = "meal_dessert_hour"
        case mealDessertMinute = "meal_dessert_minute"
        case mealMidnightSnackHour = "meal_midnight_snack_hour"
        case mealMidnightSnackMinute = "meal_midnight_snack_minute"
        case mealWakeUpHour = "meal_wake_up_hour"
        case mealWakeUpMinute = "meal_wake_up_minute"
        case mealBedtimeHour = "meal_bedtime_hour"
        case mealBedtimeMinute = "meal_bedtime_minute"
    }

    init(userId: UUID) {
        let d = UserDefaults.standard
        self.userId      = userId.uuidString
        colorTheme       = d.string(forKey: "colorTheme") ?? "Ocean Blue"
        appearance       = d.string(forKey: "appearanceOverride") ?? "light"
        timeFormat       = d.string(forKey: "timeFormat") ?? "system"
        snoozeDuration   = d.integer(forKey: "defaultSnoozeDuration").nonZeroOr(30)
        hapticsEnabled   = d.bool(forKey: "hapticsEnabled")
        showDoseBadge    = d.bool(forKey: "showDoseBadge")
        compactRows      = d.bool(forKey: "compactRows")
        selectedAvatar   = d.string(forKey: "selectedAvatar") ?? "milli"
        patientName      = d.string(forKey: "patientName") ?? ""
        patientGender    = d.string(forKey: "patientGender") ?? ""
        patientPhone     = d.string(forKey: "patientPhone") ?? ""
        patientCountry   = d.string(forKey: "patientCountry") ?? ""
        patientState     = d.string(forKey: "patientState") ?? ""
        let dobInterval  = d.double(forKey: "patientDOBInterval")
        if dobInterval > 0 {
            // Write "yyyy-MM-dd" to match the Postgres `date` column. Writing a full ISO8601
            // timestamp here previously let the day drift by one across the UTC boundary and
            // couldn't be parsed back (see applySettings).
            patientDob = DOBFormat.string(from: Date(timeIntervalSince1970: dobInterval))
        }
        let meals = MealTimes.load(from: d)
        mealBreakfastHour = meals.breakfast.hour
        mealBreakfastMinute = meals.breakfast.minute
        mealMorningTeaHour = meals.morningTea.hour
        mealMorningTeaMinute = meals.morningTea.minute
        mealLunchHour = meals.lunch.hour
        mealLunchMinute = meals.lunch.minute
        mealAfternoonTeaHour = meals.afternoonTea.hour
        mealAfternoonTeaMinute = meals.afternoonTea.minute
        mealDinnerHour = meals.dinner.hour
        mealDinnerMinute = meals.dinner.minute
        mealDessertHour = meals.dessert.hour
        mealDessertMinute = meals.dessert.minute
        mealMidnightSnackHour = meals.midnightSnack.hour
        mealMidnightSnackMinute = meals.midnightSnack.minute
        mealWakeUpHour = meals.wakeUp.hour
        mealWakeUpMinute = meals.wakeUp.minute
        mealBedtimeHour = meals.bedtime.hour
        mealBedtimeMinute = meals.bedtime.minute
    }
}

private extension Int {
    func nonZeroOr(_ fallback: Int) -> Int { self == 0 ? fallback : self }
}

/// Date-of-birth <-> string conversion for the Postgres `date` column `user_settings.patient_dob`.
/// A birth date is a calendar day, not an instant, so it's stored/parsed as "yyyy-MM-dd" in the
/// device's current calendar/timezone (so the day the user picked is the day that round-trips).
enum DOBFormat {
    private static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func string(from date: Date) -> String {
        dateOnly.string(from: date)
    }

    /// Parses a stored value, tolerating both the current "yyyy-MM-dd" form and any legacy
    /// full ISO8601 timestamp. Returns nil (rather than a bogus 0) if neither parses.
    static func timestamp(from string: String) -> Double? {
        if let d = dateOnly.date(from: string) { return d.timeIntervalSince1970 }
        if let d = ISO8601DateFormatter().date(from: string) { return d.timeIntervalSince1970 }
        return nil
    }
}
