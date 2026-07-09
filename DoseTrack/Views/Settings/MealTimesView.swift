// DoseTrack/Views/Settings/MealTimesView.swift
import SwiftUI

/// Settings → Preferences → Daily Routine Times. Lets the user adjust the app-wide
/// routine times (Wake up, meals, Bedtime) a medication's schedule can be linked to
/// (see `GuidedScheduleView`). Global, not per-medication.
struct MealTimesView: View {
    @State private var meals: MealTimes = MealTimes.load()

    private let slots: [(name: String, keyPath: WritableKeyPath<MealTimes, MealTime>)] = [
        ("Wake up", \.wakeUp),
        ("Breakfast", \.breakfast),
        ("Morning Tea", \.morningTea),
        ("Lunch", \.lunch),
        ("Afternoon Tea", \.afternoonTea),
        ("Dinner", \.dinner),
        ("Dessert", \.dessert),
        ("Midnight Snack", \.midnightSnack),
        ("Bedtime", \.bedtime),
    ]

    var body: some View {
        List {
            ForEach(slots, id: \.name) { slot in
                DatePicker(
                    slot.name,
                    selection: timeBinding(for: slot.keyPath),
                    displayedComponents: .hourAndMinute
                )
            }
        }
        .navigationTitle("Daily Routine Times")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func timeBinding(for keyPath: WritableKeyPath<MealTimes, MealTime>) -> Binding<Date> {
        Binding(
            get: {
                let meal = meals[keyPath: keyPath]
                var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                c.hour = meal.hour
                c.minute = meal.minute
                return Calendar.current.date(from: c) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                meals[keyPath: keyPath] = MealTime(hour: c.hour ?? 0, minute: c.minute ?? 0)
                meals.save()
                Task { await SupabaseSyncManager.shared.pushSettings() }
            }
        )
    }
}

#Preview {
    NavigationStack { MealTimesView() }
}
