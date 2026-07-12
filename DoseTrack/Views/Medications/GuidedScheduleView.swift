// DoseTrack/Views/Medications/GuidedScheduleView.swift
import SwiftUI

struct GuidedScheduleView: View {
    @Binding var schedules: [ScheduleDraft]
    let medicationName: String
    let doseDescription: String // e.g. "500mg" — used in the Q1 prompt text
    /// Passed straight through from `AddEditMedicationViewModel.isEditing` rather than
    /// inferred from the schedule data — see `seedStateFromExistingSchedules()` below,
    /// this is the reliable signal an editing session already has, no heuristic needed.
    let isEditingExistingMedication: Bool

    private enum Step: Equatable {
        case collapsed
        case howOften
        case specificDays
        case timesPerDay
        case spacing
        case intervalDetails
        case mealSelection
        case manualTimes
        case review
    }

    @AppStorage("timeFormat") private var timeFormat: String = "system"
    @State private var step: Step = .collapsed
    /// Guards `seedStateFromExistingSchedules()` so it runs exactly once. `.onAppear` can fire
    /// repeatedly (row scrolling on/off screen, DatePicker popovers re-laying-out the row); the
    /// seed unconditionally forced `step = .collapsed`, so every re-fire yanked the user out of
    /// the review editor the instant they tried to change a time — this was why editing an
    /// existing medication's schedule "did nothing."
    @State private var hasSeeded = false
    @State private var everyDay = true
    @State private var daysOfWeek: [Int] = []
    @State private var timesPerDay = 1
    @State private var spacingChoice: SpacingChoice = .manual
    @State private var intervalFirstTime = defaultTime(hour: 8, minute: 0)
    @State private var intervalHours = 8
    @State private var selectedRoutineIDs: Set<UUID> = []
    @State private var routineStore: RoutineStore = RoutineStore.load()
    @State private var manualTimes: [Date] = [defaultTime(hour: 8, minute: 0)]

    private enum SpacingChoice { case fixedInterval, meals, manual }

    /// The routines offered on the selection step, in chronological order.
    private var availableRoutines: [Routine] { routineStore.sorted }

    private static func defaultTime(hour: Int, minute: Int) -> Date {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = hour; c.minute = minute
        return Calendar.current.date(from: c) ?? Date()
    }

    var body: some View {
        Group {
            switch step {
            case .collapsed:      collapsedRow
            case .howOften:       howOftenQuestion
            case .specificDays:   specificDaysQuestion
            case .timesPerDay:    timesPerDayQuestion
            case .spacing:        spacingQuestion
            case .intervalDetails: intervalDetailsQuestion
            case .mealSelection:  mealSelectionQuestion
            case .manualTimes:    manualTimesQuestion
            case .review:         reviewStep
            }
        }
        .animation(.default, value: step)
        .onAppear { seedStateFromExistingSchedules() }
    }

    // MARK: - Collapsed summary

    private var collapsedRow: some View {
        Button {
            // `isEditingExistingMedication`, not `schedules.count > 1` — a fresh
            // once-daily draft and a genuinely-edited once-daily schedule both have
            // exactly 1 entry, so count alone can't distinguish them. Any existing
            // medication (even once-daily) should open on Review, not restart at Q1;
            // any new medication should always start the question flow.
            step = isEditingExistingMedication ? .review : .howOften
        } label: {
            HStack {
                Text("Taken: \(summaryText)")
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            // .buttonStyle(.plain) drops the implicit "whole row is tappable" hit-testing a
            // List row normally gets — without this, only the rendered text/icon glyphs are
            // tappable, and the Spacer gap between them (most of the row, visually) is dead
            // space. That's exactly what made this look broken: tapping the row anywhere
            // except directly on the text or chevron did nothing.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var summaryText: String {
        guard let first = schedules.first else { return "Not scheduled" }
        let timeText = formattedTime(hour: first.hour, minute: first.minute)
        if schedules.count > 1 {
            return "\(schedules.count) times daily, starting \(timeText)"
        }
        return first.daysOfWeek.isEmpty
            ? "Once daily at \(timeText)"
            : "Once on selected days at \(timeText)"
    }

    private func formattedTime(hour: Int, minute: Int) -> String {
        var c = DateComponents()
        c.hour = hour; c.minute = minute
        let date = Calendar.current.date(from: c) ?? Date()
        return TimeFormatPreference.string(for: date, preference: timeFormat)
    }

    // MARK: - Q1: How often

    private var howOftenQuestion: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How often is \(doseDescription) of \(medicationName) taken?")
                .font(.headline)
            Picker("", selection: $everyDay) {
                Text("Every day").tag(true)
                Text("Specific days").tag(false)
            }
            .pickerStyle(.segmented)
            Button("Next") {
                step = everyDay ? .timesPerDay : .specificDays
            }
        }
    }

    // MARK: - Specific days (reuses the existing day-toggle pattern)

    private let dayLabels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    private var specificDaysQuestion: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Which days?")
                .font(.headline)
            HStack(spacing: 6) {
                ForEach(Array(dayLabels.enumerated()), id: \.offset) { index, label in
                    let weekday = index + 1
                    let selected = daysOfWeek.contains(weekday)
                    Button(label) {
                        if selected {
                            daysOfWeek.removeAll { $0 == weekday }
                        } else {
                            daysOfWeek.append(weekday)
                            daysOfWeek.sort()
                        }
                    }
                    .buttonStyle(DayToggleButtonStyle(selected: selected))
                }
            }
            Button("Next") { step = .timesPerDay }
                .disabled(daysOfWeek.isEmpty)
        }
    }

    // MARK: - Q2: Times per day

    private var timesPerDayQuestion: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How many times per day?")
                .font(.headline)
            Stepper("\(timesPerDay) time\(timesPerDay == 1 ? "" : "s") per day", value: $timesPerDay, in: 1...12)
            Button("Next") {
                // Always go to the timing choice ("Set time" vs "Link to routine"), including
                // for once-daily meds — that's what lets a single bedtime pill be linked to the
                // Bedtime routine in one tap instead of scrolling a wheel. The spacing step's
                // chosen branch resizes `manualTimes` to `timesPerDay` before showing pickers.
                step = .spacing
            }
        }
    }

    // MARK: - Q3: Spacing (only reached when timesPerDay > 1)

    private var spacingQuestion: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(timesPerDay == 1 ? "When is it taken?" : "How are the times set?")
                .font(.headline)
            Picker("", selection: $spacingChoice) {
                Text(timesPerDay == 1 ? "Set time" : "Set times").tag(SpacingChoice.manual)
                Text("Link to routine").tag(SpacingChoice.meals)
                // Even intervals only makes sense for more than one dose a day.
                if timesPerDay > 1 {
                    Text("Even intervals").tag(SpacingChoice.fixedInterval)
                }
            }
            .pickerStyle(.segmented)
            .onAppear {
                // "Even intervals" isn't offered for a single daily dose; if a prior selection
                // left it set, fall back to "Set time" so the segmented control has a valid tag.
                if timesPerDay == 1 && spacingChoice == .fixedInterval { spacingChoice = .manual }
            }
            Text(spacingChoice == .meals
                 ? "Pick from your Daily Routine Times — Wake up, meals, or Bedtime. Adjust the actual clock times in Settings › Daily Routine Times."
                 : "Choose the exact clock time\(timesPerDay > 1 ? "s" : "") on the next step.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Next") {
                switch spacingChoice {
                case .fixedInterval: step = .intervalDetails
                case .meals:         step = .mealSelection
                case .manual:        manualTimes = Array(repeating: manualTimes.first ?? Self.defaultTime(hour: 8, minute: 0), count: timesPerDay); step = .manualTimes
                }
            }
        }
    }

    // MARK: - Fixed interval details

    private var intervalDetailsQuestion: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("First dose time, and hours between doses")
                .font(.headline)
            DatePicker("First dose", selection: $intervalFirstTime, displayedComponents: .hourAndMinute)
            Stepper("Every \(intervalHours) hour\(intervalHours == 1 ? "" : "s")", value: $intervalHours, in: 1...24)
            Button("Next") { applyGeneratedSchedulesFromInterval(); step = .review }
        }
    }

    private func applyGeneratedSchedulesFromInterval() {
        let c = Calendar.current.dateComponents([.hour, .minute], from: intervalFirstTime)
        let first = MealTime(hour: c.hour ?? 8, minute: c.minute ?? 0)
        let generated = ScheduleGenerator.intervalTimes(first: first, intervalHours: intervalHours, count: timesPerDay)
        schedules = generated.map { makeDraft(hour: $0.hour, minute: $0.minute) }
    }

    // MARK: - Meal selection

    private var mealSelectionQuestion: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Which routine times? (\(selectedRoutineIDs.count) of \(timesPerDay) selected)")
                .font(.headline)
            ForEach(availableRoutines) { routine in
                Toggle(isOn: Binding(
                    get: { selectedRoutineIDs.contains(routine.id) },
                    set: { isOn in
                        if isOn { selectedRoutineIDs.insert(routine.id) } else { selectedRoutineIDs.remove(routine.id) }
                    }
                )) {
                    HStack {
                        Text(routine.name)
                        Spacer()
                        Text(formattedTime(hour: routine.hour, minute: routine.minute))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Button("Next") { applyGeneratedSchedulesFromMeals(); step = .review }
                .disabled(selectedRoutineIDs.count != timesPerDay)
        }
    }

    private func applyGeneratedSchedulesFromMeals() {
        let chosen = availableRoutines.filter { selectedRoutineIDs.contains($0.id) }
        schedules = chosen
            .sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
            .map { makeDraft(hour: $0.hour, minute: $0.minute, routineLabel: $0.name) }
    }

    // MARK: - Manual times (used for timesPerDay == 1 too, as a single-item case)

    private var manualTimesQuestion: some View {
        VStack(alignment: .leading, spacing: 16) {
            // `.id(timesPerDay)` forces SwiftUI to discard cached row identity when the array
            // is resized (see the `$schedules` comment in reviewStep above for the underlying
            // stale-DatePicker-state bug this prevents).
            ForEach(manualTimes.indices, id: \.self) { i in
                DatePicker("Dose \(i + 1) time", selection: Binding(
                    get: { manualTimes[i] },
                    set: { manualTimes[i] = $0 }
                ), displayedComponents: .hourAndMinute)
            }
            .id(timesPerDay)
            Button("Next") { applyGeneratedSchedulesFromManual(); step = .review }
        }
    }

    private func applyGeneratedSchedulesFromManual() {
        schedules = manualTimes.map { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            return makeDraft(hour: c.hour ?? 8, minute: c.minute ?? 0)
        }
    }

    // MARK: - Review

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Schedule").font(.headline)
            // `ForEach($schedules)` keyed by `ScheduleDraft.id` (not `schedules.indices, id:
            // \.self`) — index-based identity let SwiftUI reuse a DatePicker's internal wheel
            // state across renders whenever the array was regenerated (interval/meal presets,
            // or re-adding a schedule after Change Schedule Type), so the picker sometimes kept
            // showing a stale cached time instead of the fresh value — this is the "sometimes
            // defaults back to 08:00 no matter what you enter" bug. A stable per-row identity
            // forces SwiftUI to treat a regenerated array as genuinely new rows.
            ForEach($schedules) { $draft in
                HStack {
                    DatePicker("", selection: Binding(
                        get: {
                            var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                            c.hour = draft.hour; c.minute = draft.minute
                            return Calendar.current.date(from: c) ?? Date()
                        },
                        set: { date in
                            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                            draft.hour = c.hour ?? 8
                            draft.minute = c.minute ?? 0
                            // Hand-editing the time detaches it from whatever routine it was
                            // linked to — Today should go back to showing the clock time, since
                            // it's no longer guaranteed to match that routine's own time.
                            draft.routineLabel = nil
                        }
                    ), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                }
            }
            HStack {
                // `.borderless` is essential here: two buttons in a single Form row without an
                // explicit button style makes SwiftUI treat the WHOLE row as one tap target and
                // fire BOTH closures. Tapping "Change Schedule Type" therefore also ran "Done"
                // (step = .collapsed), collapsing the editor — which is exactly why the button
                // "did nothing." Borderless makes each button its own independent hit target.
                Button("Change Schedule Type") { resetWizardToFreshStart() }
                    .buttonStyle(.borderless)
                Spacer()
                Button("Done") { step = .collapsed }
                    .fontWeight(.semibold)
                    .buttonStyle(.borderless)
            }
        }
    }

    // MARK: - Helpers

    /// Restarts the wizard from Q1 exactly as if creating a brand-new schedule — all local
    /// wizard state reset to defaults, not just `step` jumped back. Previously this only changed
    /// `step`, leaving `everyDay`/`daysOfWeek`/`timesPerDay`/`spacingChoice`/`manualTimes` however
    /// they'd been left by the ORIGINAL schedule this view was seeded from, so re-answering the
    /// questions could silently regenerate the same schedule the user was trying to replace —
    /// which read as "the button doesn't let you change the schedule."
    private func resetWizardToFreshStart() {
        everyDay = true
        daysOfWeek = []
        timesPerDay = 1
        spacingChoice = .manual
        intervalFirstTime = Self.defaultTime(hour: 8, minute: 0)
        intervalHours = 8
        selectedRoutineIDs = []
        manualTimes = [Self.defaultTime(hour: 8, minute: 0)]
        step = .howOften
    }

    private func makeDraft(hour: Int, minute: Int, routineLabel: String? = nil) -> ScheduleDraft {
        ScheduleDraft(
            hour: hour, minute: minute,
            frequency: everyDay ? "daily" : "custom",
            daysOfWeek: everyDay ? [] : daysOfWeek,
            routineLabel: routineLabel
        )
    }

    /// If editing an existing medication (per `isEditingExistingMedication`, passed
    /// straight through from `AddEditMedicationViewModel.isEditing` — not inferred
    /// from the schedule data, since a genuinely-edited once-daily-8am-every-day
    /// schedule is indistinguishable from a fresh unedited draft by data alone),
    /// seed the local flow state and jump straight to the collapsed summary per the
    /// spec's re-entry rule — never restart at Q1 for an existing schedule.
    private func seedStateFromExistingSchedules() {
        guard !hasSeeded else { return }
        hasSeeded = true
        guard isEditingExistingMedication, let first = schedules.first else { return }
        everyDay = first.daysOfWeek.isEmpty
        daysOfWeek = first.daysOfWeek
        timesPerDay = schedules.count
        step = .collapsed
    }
}

private struct DayToggleButtonStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(selected ? Color.accentColor : Color.secondary.opacity(0.15))
            .foregroundStyle(selected ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}

#Preview {
    Form {
        GuidedScheduleView(schedules: .constant([ScheduleDraft()]), medicationName: "Metformin", doseDescription: "500mg", isEditingExistingMedication: false)
    }
}
