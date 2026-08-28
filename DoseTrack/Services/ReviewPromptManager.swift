// DoseTrack/Services/ReviewPromptManager.swift
// Decides when it's worth asking Apple to show the native "rate this app" prompt.
//
// ## Why this only *asks* — and can't know the answer
//
// `SKStoreReviewController` / `RequestReviewAction` deliberately returns nothing. There is no
// callback, no completion handler, and no API to ask whether the user has already rated. That means
// "don't keep pestering someone who already rated" is impossible to implement here — but it *is*
// implemented, by iOS itself:
//
//   * iOS silently suppresses the prompt if the user already rated this version.
//   * iOS hard-caps display at 3 times per 365 days per app, regardless of how often we ask.
//
// So the division of responsibility is: this type decides when a request is *worth making*, and the
// system decides whether anything is actually shown. Because we can't observe the outcome, we count
// "we asked" rather than "they saw it", and space asks out generously — a request spent on a poor
// moment is genuinely wasted, since it may consume one of only three annual displays.
//
// The Settings → "Rate DoseTrack" row is deliberately NOT routed through here: that's an explicit
// user action, so it opens the App Store review page directly and always works (see
// `Constants.ExternalLinks.appStoreWriteReview`). Throttling a button someone deliberately tapped
// would look broken.
import Foundation

@MainActor
final class ReviewPromptManager: ObservableObject {

    static let shared = ReviewPromptManager()

    private let defaults: UserDefaults

    /// Injectable so tests get an isolated suite rather than mutating `.standard`, which otherwise
    /// leaks state between tests and between the test host and the app.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Tuning
    //
    // Deliberately conservative. Someone still evaluating the app is more likely to dismiss or rate
    // poorly, and with only three system displays a year available, a premature ask is expensive.

    /// Lifetime scheduled doses marked taken before we'll consider asking.
    static let doseThreshold = 30
    /// Minimum days since first launch, so a burst of first-day logging can't trigger a prompt.
    static let minimumDaysSinceFirstLaunch = 14
    /// Gap before asking again when a previous request didn't lead to a rating (or we can't tell —
    /// which is the normal case, see the note above).
    static let daysBetweenRequests = 120
    /// Our own ceiling on lifetime requests. iOS enforces its own 3-per-year cap independently;
    /// this simply stops us asking indefinitely across multiple years.
    static let maximumRequests = 3

    // MARK: - Stored state

    private enum Key {
        static let dosesTaken = "reviewPrompt.lifetimeDosesTaken"
        static let firstLaunch = "reviewPrompt.firstLaunchAt"
        static let lastRequested = "reviewPrompt.lastRequestedAt"
        static let requestCount = "reviewPrompt.requestCount"
        static let optedOut = "reviewPrompt.optedOut"
    }

    /// Records first launch if not already set. Safe to call on every launch.
    func recordLaunchIfNeeded(now: Date = Date()) {
        guard defaults.object(forKey: Key.firstLaunch) == nil else { return }
        defaults.set(now.timeIntervalSince1970, forKey: Key.firstLaunch)
    }

    /// Counts a scheduled dose marked taken. As-needed doses deliberately don't count: someone
    /// could log a dozen PRN doses in one bad afternoon, and that's not the sustained engagement
    /// this threshold is trying to detect — nor a moment to ask for a favour.
    func recordDoseTaken(count: Int = 1) {
        let current = defaults.integer(forKey: Key.dosesTaken)
        defaults.set(current + count, forKey: Key.dosesTaken)
    }

    /// Permanently stops automatic prompts. Used when someone taps Settings → Rate DoseTrack: they
    /// have gone to the store deliberately, so continuing to interrupt them is just noise.
    func optOutOfAutomaticPrompts() {
        defaults.set(true, forKey: Key.optedOut)
    }

    var lifetimeDosesTaken: Int { defaults.integer(forKey: Key.dosesTaken) }
    var requestCount: Int { defaults.integer(forKey: Key.requestCount) }
    var hasOptedOut: Bool { defaults.bool(forKey: Key.optedOut) }

    // MARK: - Eligibility

    /// Whether it's worth asking the system to show the prompt right now.
    ///
    /// Callers should only invoke this at a genuinely positive moment (see `TodayView` — it fires on
    /// the "all done for today" celebration, never mid-routine with doses still outstanding).
    func shouldRequestReview(now: Date = Date()) -> Bool {
        guard !hasOptedOut else { return false }
        guard requestCount < Self.maximumRequests else { return false }
        guard lifetimeDosesTaken >= Self.doseThreshold else { return false }

        // No recorded first launch means recordLaunchIfNeeded hasn't run yet — treat as ineligible
        // rather than assuming a long tenure.
        let firstLaunchInterval = defaults.double(forKey: Key.firstLaunch)
        guard firstLaunchInterval > 0 else { return false }
        let firstLaunch = Date(timeIntervalSince1970: firstLaunchInterval)
        guard daysBetween(firstLaunch, now) >= Self.minimumDaysSinceFirstLaunch else { return false }

        let lastRequestedInterval = defaults.double(forKey: Key.lastRequested)
        if lastRequestedInterval > 0 {
            let lastRequested = Date(timeIntervalSince1970: lastRequestedInterval)
            guard daysBetween(lastRequested, now) >= Self.daysBetweenRequests else { return false }
        }

        return true
    }

    /// Marks that a request was made. Called immediately after asking the system, NOT after any
    /// confirmation — because no confirmation exists.
    func recordRequestMade(now: Date = Date()) {
        defaults.set(now.timeIntervalSince1970, forKey: Key.lastRequested)
        defaults.set(requestCount + 1, forKey: Key.requestCount)
    }

    private func daysBetween(_ earlier: Date, _ later: Date) -> Int {
        Calendar.current.dateComponents([.day], from: earlier, to: later).day ?? 0
    }

    #if DEBUG
    /// Test/Developer-Options helper: clears all prompt state so the flow can be exercised again.
    func resetForTesting() {
        [Key.dosesTaken, Key.firstLaunch, Key.lastRequested, Key.requestCount, Key.optedOut]
            .forEach { defaults.removeObject(forKey: $0) }
    }
    #endif
}
