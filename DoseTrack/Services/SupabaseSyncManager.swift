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
            async let meds    = fetchRemoteMedications(userId: targetUserId)
            async let scheds  = fetchRemoteSchedules(userId: targetUserId)
            async let logs    = fetchRemoteDoseLogs(userId: targetUserId)
            async let settings = fetchRemoteSettings(userId: targetUserId)
            let (m, s, l, st) = try await (meds, scheds, logs, settings)
            mergeMedications(m, context: context)
            mergeSchedules(s, context: context)
            mergeDoseLogs(l, context: context)
            // Only apply settings when syncing the signed-in user's own account — applying a
            // linked patient's UserDefaults onto the caregiver's own device would silently
            // overwrite the caregiver's theme/name/preferences. See risk note above.
            if forUserId == nil, let st { applySettings(st) }
            try? context.save()
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            print("SupabaseSync pullAll error: \(error)")
        }
    }

    // MARK: - Push individual records

    func pushMedication(_ med: Medication, forUserId: UUID? = nil) async {
        guard AuthManager.shared.isSignedIn, !AuthManager.shared.isGuest,
              let id = med.id,
              let targetUserId = forUserId ?? AuthManager.shared.session?.user.id else { return }
        let row = MedicationRow(medication: med, userId: targetUserId)
        do {
            try await client.from("medications").upsert(row).execute()
            for schedule in med.schedulesArray {
                await pushSchedule(schedule, medicationId: id, userId: targetUserId)
            }
        } catch { print("pushMedication error: \(error)") }
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
    private func fetchRemoteDoseLogs(userId: UUID) async throws -> [DoseLogRow] {
        try await client.from("dose_logs").select().eq("user_id", value: userId.uuidString).execute().value
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
            let sched = existing ?? Schedule(context: context)
            sched.id           = uuid
            sched.hour         = row.hour
            sched.minute       = row.minute
            sched.frequency    = row.frequency
            sched.daysOfWeek   = row.daysOfWeek as NSArray
            sched.intervalDays = row.intervalDays
            sched.isEnabled    = row.isEnabled
            sched.medication   = med
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
            let log = existing ?? DoseLog(context: context)
            log.id          = uuid
            log.scheduledAt = row.scheduledAt
            log.loggedAt    = row.loggedAt
            log.status      = row.status
            log.notes       = row.notes
            log.medication  = med
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
        if let dob = row.patientDob {
            let ts = ISO8601DateFormatter().date(from: dob)?.timeIntervalSince1970 ?? 0
            d.set(ts, forKey: "patientDOBInterval")
        }
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
    }
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

    enum CodingKeys: String, CodingKey {
        case id, hour, minute, frequency
        case userId = "user_id"
        case medicationId = "medication_id"
        case daysOfWeek = "days_of_week"
        case intervalDays = "interval_days"
        case isEnabled = "is_enabled"
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

    enum CodingKeys: String, CodingKey {
        case id, status, notes
        case userId = "user_id"
        case medicationId = "medication_id"
        case scheduledAt = "scheduled_at"
        case loggedAt = "logged_at"
    }

    init(log: DoseLog, userId: UUID) {
        id           = log.id?.uuidString ?? UUID().uuidString
        self.userId  = userId.uuidString
        medicationId = (log.medication as? Medication)?.id?.uuidString ?? ""
        scheduledAt  = log.scheduledAt ?? Date()
        loggedAt     = log.loggedAt ?? Date()
        status       = log.status ?? "taken"
        notes        = log.notes ?? ""
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
    }

    init(userId: UUID) {
        let d = UserDefaults.standard
        self.userId      = userId.uuidString
        colorTheme       = d.string(forKey: "colorTheme") ?? "Ocean Blue"
        appearance       = d.string(forKey: "appearanceOverride") ?? "system"
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
            patientDob = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: dobInterval))
        }
    }
}

private extension Int {
    func nonZeroOr(_ fallback: Int) -> Int { self == 0 ? fallback : self }
}
