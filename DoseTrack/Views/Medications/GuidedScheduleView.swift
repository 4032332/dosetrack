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

    @State private var step: Step = .collapsed
    @State private var everyDay = true
    @State private var daysOfWeek: [Int] = []
    @State private var timesPerDay = 1
    @State private var spacingChoice: SpacingChoice = .manual
    @State private var intervalFirstTime = defaultTime(hour: 8, minute: 0)
    @State private var intervalHours = 8
    @State private var selectedMeals: Set<MealSlot> = []
    @State private var mealTimes: MealTimes = MealTimes.load()
    @State private var manualTimes: [Date] = [defaultTime(hour: 8, minute: 0)]

    private enum SpacingChoice { case fixedInterval, meals, manual }

    private enum MealSlot: String, CaseIterable, Identifiable {
        case breakfast, morningTea, lunch, afternoonTea, dinner, dessert, midnightSnack
        var id: String { rawValue }
        var label: String {
            switch self {
            case .breakfast: return "Breakfast"
            case .morningTea: return "Morning Tea"
            case .lunch: return "Lunch"
            case .afternoonTea: return "Afternoon Tea"
            case .dinner: return "Dinner"
            case .dessert: return "Dessert"
            case .midnightSnack: return "Midnight Snack"
            }
        }
        func time(in meals: MealTimes) -> MealTime {
            switch self {
            case .breakfast: return meals.breakfast
            case .morningTea: return meals.morningTea
            case .lunch: return meals.lunch
            case .afternoonTea: return meals.afternoonTea
            case .dinner: return meals.dinner
            case .dessert: return meals.dessert
            case .midnightSnack: return meals.midnightSnack
            }
        }
    }

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
        return date.formatted(date: .omitted, time: .shortened)
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
                // `manualTimes` only ever gets resized in `spacingQuestion`'s `.manual`
                // branch (for timesPerDay > 1); the timesPerDay == 1 path relies on
                // `manualTimes`'s `@State` default already being a 1-element array, so
                // it's correct as-is here without a resize — don't add one, and don't
                // let a future change to `timesPerDay` after this point skip that resize.
                step = timesPerDay == 1 ? .manualTimes : .spacing
            }
        }
    }

    // MARK: - Q3: Spacing (only reached when timesPerDay > 1)

    private var spacingQuestion: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How are doses spaced?")
                .font(.headline)
            Picker("", selection: $spacingChoice) {
                Text("Fixed intervals").tag(SpacingChoice.fixedInterval)
                Text("Tied to meals").tag(SpacingChoice.meals)
                Text("Set each manually").tag(SpacingChoice.manual)
            }
            .pickerStyle(.inline)
            .labelsHidden()
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
            Text("Which meals? (\(selectedMeals.count) of \(timesPerDay) selected)")
                .font(.headline)
            ForEach(MealSlot.allCases) { meal in
                let time = meal.time(in: mealTimes)
                Toggle(isOn: Binding(
                    get: { selectedMeals.contains(meal) },
                    set: { isOn in
                        if isOn { selectedMeals.insert(meal) } else { selectedMeals.remove(meal) }
                    }
                )) {
                    HStack {
                        Text(meal.label)
                        Spacer()
                        Text(formattedTime(hour: time.hour, minute: time.minute))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Button("Next") { applyGeneratedSchedulesFromMeals(); step = .review }
                .disabled(selectedMeals.count != timesPerDay)
        }
    }

    private func applyGeneratedSchedulesFromMeals() {
        schedules = selectedMeals.sorted { a, b in
            let ta = a.time(in: mealTimes); let tb = b.time(in: mealTimes)
            return (ta.hour, ta.minute) < (tb.hour, tb.minute)
        }.map { meal in
            let t = meal.time(in: mealTimes)
            return makeDraft(hour: t.hour, minute: t.minute)
        }
    }

    // MARK: - Manual times (used for timesPerDay == 1 too, as a single-item case)

    private var manualTimesQuestion: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(manualTimes.indices, id: \.self) { i in
                DatePicker("Dose \(i + 1) time", selection: Binding(
                    get: { manualTimes[i] },
                    set: { manualTimes[i] = $0 }
                ), displayedComponents: .hourAndMinute)
            }
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
            ForEach(schedules.indices, id: \.self) { i in
                HStack {
                    DatePicker("", selection: Binding(
                        get: {
                            var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                            c.hour = schedules[i].hour; c.minute = schedules[i].minute
                            return Calendar.current.date(from: c) ?? Date()
                        },
                        set: { date in
                            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                            schedules[i].hour = c.hour ?? 8
                            schedules[i].minute = c.minute ?? 0
                        }
                    ), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                }
            }
            HStack {
                Button("Change Schedule Type") { step = .howOften }
                Spacer()
                Button("Done") { step = .collapsed }
                    .fontWeight(.semibold)
            }
        }
    }

    // MARK: - Helpers

    private func makeDraft(hour: Int, minute: Int) -> ScheduleDraft {
        ScheduleDraft(
            hour: hour, minute: minute,
            frequency: everyDay ? "daily" : "custom",
            daysOfWeek: everyDay ? [] : daysOfWeek
        )
    }

    /// If editing an existing medication (per `isEditingExistingMedication`, passed
    /// straight through from `AddEditMedicationViewModel.isEditing` — not inferred
    /// from the schedule data, since a genuinely-edited once-daily-8am-every-day
    /// schedule is indistinguishable from a fresh unedited draft by data alone),
    /// seed the local flow state and jump straight to the collapsed summary per the
    /// spec's re-entry rule — never restart at Q1 for an existing schedule.
    private func seedStateFromExistingSchedules() {
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
