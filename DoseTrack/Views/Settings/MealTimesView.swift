// DoseTrack/Views/Settings/MealTimesView.swift
import SwiftUI

/// Settings → Preferences → Daily Routine Times. Lets the user adjust the app-wide
/// routine times (Wake up, meals, Bedtime) a medication's schedule can be linked to
/// (see `GuidedScheduleView`). Global, not per-medication.
struct MealTimesView: View {
    @State private var meals: MealTimes = MealTimes.load()
    @State private var isSaving = false
    @State private var toast: ToastMessage? = nil

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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await save(showToast: true) }
                } label: {
                    if isSaving {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Text("Save").fontWeight(.semibold)
                    }
                }
                .disabled(isSaving)
            }
        }
        .toast($toast)
        // Each field already saves locally + pushes remotely the instant it changes (see
        // timeBinding below), but leaving the screen — via the back button or a swipe — used
        // to skip any pending push still in flight. Saving again on disappear (same pattern as
        // ProfileView's DOB fix) guarantees the final state is written and pushed before the
        // screen closes, not just "probably already sent."
        .onDisappear {
            Task { await save(showToast: false) }
        }
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
            }
        )
    }

    private func save(showToast: Bool) async {
        isSaving = true
        defer { isSaving = false }
        meals.save()
        await SupabaseSyncManager.shared.pushSettings()
        if showToast {
            toast = ToastMessage(text: "Saved", systemImage: "checkmark.circle.fill")
        }
    }
}

#Preview {
    NavigationStack { MealTimesView() }
}
