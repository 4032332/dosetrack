// DoseTrack/Services/NotificationCopy.swift
import Foundation

/// Generates the body text for a "time to take X" notification. The patient already knows their
/// own dose — the notification's only job is to prompt, so it names the medication and nothing
/// else (no strength, no pill count). Picked randomly from a large pool each time so reminders
/// feel alive rather than robotic; several pools are gated on trigger variables (medication form,
/// time of day) so the line can be more specific when it's true — e.g. an inhaler joke only ever
/// fires for an inhaler, a bedtime line only for a schedule that actually falls near bedtime.
/// Gated pools are additive, not exclusive — every draw always includes the full general pool
/// too, so even a bedtime inhaler dose can still land a plain general line. That's deliberate:
/// a sub-list that always wins would make its lines predictable rather than a fun surprise.
enum NotificationCopy {

    /// Picks one line at random from the general pool plus whichever gated pools apply
    /// (medication form, and time-of-day relative to the user's Wake Up / Bedtime routine
    /// times), and substitutes the medication name in for every `{name}` placeholder.
    static func randomLine(medicationName: String, unit: String, hour: Int) -> String {
        var pool = general
        pool += typeLines(for: unit)
        let routines = RoutineStore.load()
        if isNear(hour: hour, to: routines.wakeUp.hour) { pool += wakeUpLines }
        if isNear(hour: hour, to: routines.bedtime.hour) { pool += bedtimeLines }
        let template = pool.randomElement() ?? "Time to take your {name}."
        return template.replacingOccurrences(of: "{name}", with: medicationName)
    }

    private static func typeLines(for unit: String) -> [String] {
        switch unit.lowercased() {
        case "inhaler":   return inhalerLines
        case "spray":     return sprayLines
        case "injection": return injectionLines
        case "patch":     return patchLines
        case "drop":      return dropLines
        case "ml":        return liquidLines
        case "tablet":    return tabletLines
        case "capsule":   return capsuleLines
        case "pill":      return pillLines
        default:          return []
        }
    }

    /// True when `hour` falls within `window` hours of `reference`, wrapping around midnight —
    /// so a Bedtime routine time of 23:00 correctly still matches an hour of 1am, not just the
    /// hours before midnight.
    private static func isNear(hour: Int, to reference: Int, window: Int = 2) -> Bool {
        let diff = abs(hour - reference)
        return min(diff, 24 - diff) <= window
    }

    // MARK: - General pool (110 lines)

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
        "One small step for you, one big win for your health: {name} time.",
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
        "Pill-ease tell me you remembered to take your {name}.",
        "I'm not trying to be meddlesome, but it's {name} time again.",
        "Let's get this {name} party started!",
        "I know {name} is a bitter pill to swallow, but it's time to dose up!",
        "Knock knock. Who's there? Your {name}!",
        "Ahem. {name}. Now, please.",
        "Breaking news: {name} time has arrived.",
        "Your {name} called — it wants to see you.",
        "Reminder from your favourite app: {name} time!",
        "Every hero needs their {name}. Cue yours.",
        "Let's keep the streak alive — {name} time.",
        "Your health thanks you in advance for taking {name}.",
        "{name}: it's a date.",
        "No excuses — {name} o'clock.",
        "Take a beat, take your {name}.",
        "Fresh reminder, same great {name}.",
        "All roads lead to {name} right now.",
        "Level up your day with {name}.",
        "Achievement unlocked: remembering your {name}.",
        "High five for taking your {name} on time.",
        "Your streak needs you — {name} time.",
        "Consistency is key: {name} time.",
        "Your {name} is patiently waiting.",
        "Time to check off {name}.",
        "Little things matter — {name} time.",
        "It's that time again: {name}.",
        "Keep calm and take your {name}.",
        "Your wellbeing says hi — and asks for {name}.",
        "Ping! {name} is due.",
        "A moment for {name}, then back to your day.",
        "Your {name} awaits your arrival.",
        "Cross {name} off your list.",
        "Health check: {name} time.",
        "Your routine calls for {name}.",
        "Onward to a healthier you — {name} time.",
        "Reminder, delivered with love: {name}.",
        "Time to be your own hero — take {name}.",
        "Whatever you're doing, pause for {name}.",
        "{name} says hello — time to take it.",
        "Your commitment to you: {name} time.",
        "Let's not forget {name} today.",
        "One tap of a reminder, one step closer to healthy — {name}.",
        "This message will self-destruct... after you take your {name}.",
        "Fun fact: it's {name} time.",
        "Drumroll... it's {name} time!",
        "Your {name} has entered the chat.",
        "Cheers to taking care of you — {name} time.",
        "In case you were wondering, it's {name} time.",
        "A quick favour: take your {name}.",
        "Because you're worth it — {name} time.",
        "Your {name} is due for its moment.",
        "Reminder unlocked: {name}.",
        "Stay on track — {name} time.",
        "Your {name} — right on cue.",
        "Small step, big difference: {name} time.",
        "You, me, and your {name} — let's do this.",
        "Consider this a gentle tap on the shoulder: {name} time.",
        "Your {name} would love some attention right now.",
        "Keeping promises starts with {name}.",
        "It's showtime for {name}.",
        "Your {name} is due — no snoozing forever!",
        "Circle back to {name} now.",
        "A little reminder never hurt anybody — {name} time.",
        "Make today count — start with {name}.",
        "You're one {name} away from staying on track.",
        "Your {name} — present and accounted for, please.",
        "Reminder engaged: {name}.",
        "Give yourself the gift of {name}, right now.",
        "Your body called. It wants {name}.",
        "Interrupting this moment to say: {name} time.",
        "{name} is on standby — go get it.",
        "Your dedication is showing — {name} time.",
        "A round of applause for taking your {name} on time.",
        "Consider your {name} officially due.",
        "Your health streak is counting on you — {name}.",
        "Quietly but firmly: {name} time.",
    ]

    // MARK: - Wake Up window (22 lines, ±2h of the user's Wake Up routine time)

    private static let wakeUpLines: [String] = [
        "Morning! Time for your {name}.",
        "Rise, shine, and take your {name}.",
        "Good morning — kick things off with {name}.",
        "First things first: {name}.",
        "Start your day right with {name}.",
        "Eyes open? Time for {name}.",
        "Morning routine, step one: {name}.",
        "Wakey wakey — and don't forget your {name}.",
        "Before coffee, there's {name}.",
        "Rise and remember your {name}.",
        "Your day starts with {name}.",
        "Good morning! Don't forget {name}.",
        "Sun's up — so is your {name} reminder.",
        "New day, same great habit: {name}.",
        "Morning has broken — and so has your {name} reminder.",
        "Fresh start, fresh {name}.",
        "Top of the morning to you — and your {name}.",
        "Kickstart your morning with {name}.",
        "Before the day runs away with you — {name}.",
        "A great morning begins with {name}.",
        "Rise and shine, then take your {name}.",
        "Morning mission: take your {name}.",
    ]

    // MARK: - Bedtime window (22 lines, ±2h of the user's Bedtime routine time)

    private static let bedtimeLines: [String] = [
        "Don't fall asleep on me without taking your {name}.",
        "Before you drift off — {name} time.",
        "One last thing before bed: {name}.",
        "Sweet dreams start with your {name}.",
        "Lights out soon — take your {name} first.",
        "Tuck yourself in after your {name}.",
        "Last call before bed: {name}.",
        "Wind down with your {name} first.",
        "Nighty night — but {name} comes first.",
        "Before the pillow, there's {name}.",
        "End your day on the right note: {name}.",
        "Almost bedtime — don't forget {name}.",
        "Your bed can wait a moment for {name}.",
        "Nightcap time — a {name}, not a drink.",
        "Set tomorrow up right — take {name} tonight.",
        "Sleepy time is coming — {name} first.",
        "Say goodnight to today with {name}.",
        "Close out the day with {name}.",
        "Before you count sheep, count on {name}.",
        "Time to wind down — starting with {name}.",
        "Your pillow's ready. Is your {name}?",
        "One more thing before dreamland: {name}.",
    ]

    // MARK: - Medication form pools

    private static let tabletLines: [String] = [
        "Your {name} tablet is ready when you are.",
        "One tablet, one step closer to feeling great — {name}.",
        "Tablet time: {name}.",
        "Your {name} tablet won't take itself.",
        "Down the hatch — {name} time.",
        "Grab some water, it's {name} tablet time.",
        "Small tablet, big difference: {name}.",
        "Your {name} tablet is on standby.",
        "Quick swallow, big win: {name} time.",
        "Time to take your {name} tablet.",
    ]

    private static let capsuleLines: [String] = [
        "Capsule time: {name}.",
        "Your {name} capsule is ready for takeoff.",
        "Pop your {name} capsule now.",
        "One capsule, coming right up — {name}.",
        "Your {name} capsule is patiently waiting.",
        "Capsule check: {name} time.",
        "A capsule a day — starting with {name}.",
        "Time to take your {name} capsule.",
        "Your {name} capsule has cleared for takeoff.",
        "Quick capsule stop: {name}.",
    ]

    private static let pillLines: [String] = [
        "Your {name} pill is calling your name.",
        "Pop that {name} pill now.",
        "Pill time: {name}.",
        "One pill, zero excuses — {name}.",
        "Your {name} pill is ready and waiting.",
        "Quick pill stop: {name}.",
        "Time to take your {name} pill.",
        "Your {name} pill won't take itself.",
        "A pill a day keeps the reminders away — starting with {name}.",
        "Small pill, big impact: {name}.",
    ]

    private static let sprayLines: [String] = [
        "Spritz time — your {name} is ready.",
        "One spray closer to feeling better: {name}.",
        "Your {name} spray is calling.",
        "Time for a quick spray of {name}.",
        "Spray it, don't delay it — {name} time.",
        "Your {name} spray is on standby.",
        "A quick mist of {name}, right now.",
        "Spray time: {name}.",
        "Your {name} spray won't use itself.",
        "Time to take your {name} spray.",
    ]

    private static let inhalerLines: [String] = [
        "You take my breath away, but you need your {name}.",
        "Breathe easy — it's {name} time.",
        "Take a puff of {name} and carry on.",
        "Your lungs are calling for {name}.",
        "Deep breath — then your {name}.",
        "Inhale confidence, exhale worry: {name} time.",
        "One puff for you, one win for your lungs — {name}.",
        "Your {name} inhaler is ready when you are.",
        "Time to breathe easy with {name}.",
        "Puff, puff — don't forget your {name}.",
    ]

    private static let injectionLines: [String] = [
        "Your {name} injection is due.",
        "Time for your {name} shot.",
        "A quick jab and you're done — {name} time.",
        "Your {name} injection won't give itself.",
        "Steady hands, quick moment — {name} time.",
        "Time to take your {name} injection.",
        "Your {name} shot is on the schedule now.",
        "A small pinch for a big benefit — {name}.",
    ]

    private static let patchLines: [String] = [
        "Time to change your {name} patch.",
        "Your {name} patch is due for a refresh.",
        "Fresh patch, fresh start — {name}.",
        "Patch time: {name}.",
        "Your {name} patch is ready and waiting.",
        "Time to apply your {name} patch.",
        "Stick with it — {name} patch time.",
        "Your {name} patch needs a swap.",
    ]

    private static let dropLines: [String] = [
        "Time for your {name} drops.",
        "Your {name} drops are ready and waiting.",
        "A drop or two of {name}, right now.",
        "Drop time: {name}.",
        "Your {name} drops won't administer themselves.",
        "Quick drop stop: {name}.",
        "Time to take your {name} drops.",
        "Steady hand, quick drop — {name} time.",
    ]

    private static let liquidLines: [String] = [
        "Time for your {name} dose.",
        "Your {name} is measured and ready.",
        "A quick sip of {name}, right now.",
        "Your {name} liquid is on standby.",
        "Time to take your {name}.",
        "Measure, sip, done — {name} time.",
        "Your {name} won't pour itself.",
        "Quick liquid stop: {name}.",
    ]
}
