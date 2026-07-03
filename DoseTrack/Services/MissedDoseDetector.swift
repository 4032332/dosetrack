import Foundation

/// Pure logic for deciding which scheduled doses count as "missed" for caregiver
/// alerting purposes. Mirrors the server-side Edge Function logic (a separate task)
/// so it can be unit tested without a live Supabase connection; the Edge Function is
/// the actual source of truth for production alerts.
enum MissedDoseDetector {
    static let overdueThreshold: TimeInterval = 60 * 60 // 60 minutes, per spec (sync-lag safety margin)

    static func overdueOccurrences(scheduledTimes: [Date], loggedTimes: [Date], now: Date) -> [Date] {
        let loggedSet = Set(loggedTimes)
        return scheduledTimes.filter { scheduled in
            !loggedSet.contains(scheduled) && now.timeIntervalSince(scheduled) >= overdueThreshold
        }
    }
}
