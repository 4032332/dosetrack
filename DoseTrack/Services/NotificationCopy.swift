// DoseTrack/Services/NotificationCopy.swift
import Foundation

/// Generates the body text for a "time to take X" notification. The patient already knows their
/// own dose — the notification's only job is to prompt, so it names the medication and nothing
/// else (no strength, no pill count). Picked randomly from a large pool each time so reminders
/// feel alive rather than robotic; a few pools are gated on trigger variables (medication form,
/// time of day) so the line can be more specific when it's true — e.g. an inhaler joke only ever
/// fires for an inhaler, a bedtime line only for a schedule that actually falls at night.
enum NotificationCopy {

    /// Picks one line at random from the general pool plus whichever gated pools apply, and
    /// substitutes the medication name in for every `{name}` placeholder.
    static func randomLine(medicationName: String, unit: String, hour: Int) -> String {
        var pool = general
        if isInhaler(unit) { pool += inhalerLines }
        if isBedtime(hour) { pool += bedtimeLines }
        let template = pool.randomElement() ?? "Time to take your {name}."
        return template.replacingOccurrences(of: "{name}", with: medicationName)
    }

    private static func isInhaler(_ unit: String) -> Bool {
        unit.lowercased() == "inhaler"
    }

    /// Matches the "Bedtime" routine slot's default hour range (see GuidedScheduleView /
    /// MealTimes) — a schedule fired late evening through early morning reads as a bedtime dose.
    private static func isBedtime(_ hour: Int) -> Bool {
        hour >= 21 || hour < 5
    }

    private static let general: [String] = [
        "Don't forget to take your {name}.",
        "It's {name} time!",
        "Your {name} is calling!",
        "If you're happy and you know it, take your {name}.",
        "Time for your {name}.",
        "Quick reminder: {name} is due.",
        "Psst — {name} time.",
        "Your body is waiting on that {name}.",
        "{name} o'clock!",
        "Hey! Time to take your {name}.",
        "Don't keep your {name} waiting.",
        "A gentle nudge: take your {name} now.",
        "Consider this your {name} alarm.",
        "Your {name} would like a word.",
        "Tick tock — {name} time.",
        "This is your friendly {name} reminder.",
        "{name} is on the schedule right now.",
        "Time flies — so does your {name} window. Take it now!",
        "You plus {name} equals a healthier you. Go on.",
        "One small dose for you, one big win for your health: {name} time.",
        "Ding ding! {name} is due.",
        "Your future self says thanks for taking {name} now.",
        "Not to nag, but... {name} time.",
        "The stars have aligned for your {name}.",
        "Cue the {name} fanfare — it's time!",
        "Beep boop, {name} reminder incoming.",
        "Your {name} misses you. Reunite now.",
        "Right on schedule: {name}.",
        "Little reminder, big impact: take your {name}.",
        "Chop chop — {name} time!",
        "Here's your nudge for {name}.",
        "Don't skip it — {name} is due.",
        "Take a second for your {name}.",
        "Time check: it's {name} time.",
        "You've got this — take your {name}.",
        "{name} is ready when you are.",
        "A small habit, a big difference: {name} time.",
        "Your daily {name} check-in has arrived.",
        "Onwards! But first, {name}.",
        "Plot twist: it's {name} time again.",
        "Just a friendly poke — {name} time.",
    ]

    private static let inhalerLines: [String] = [
        "You take my breath away, but you need your {name}.",
        "Breathe easy — it's {name} time.",
        "Take a puff of {name} and carry on.",
        "Your lungs are calling for {name}.",
        "Deep breath — then your {name}.",
        "Inhale confidence, exhale worry: {name} time.",
    ]

    private static let bedtimeLines: [String] = [
        "Don't fall asleep on me without taking your {name}.",
        "Before you drift off — {name} time.",
        "One last thing before bed: {name}.",
        "Sweet dreams start with your {name}.",
        "Lights out soon — take your {name} first.",
        "Tuck yourself in after your {name}.",
    ]
}
