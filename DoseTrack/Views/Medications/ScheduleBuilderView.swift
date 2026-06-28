// DoseTrack/Views/Medications/ScheduleBuilderView.swift
import SwiftUI

struct ScheduleBuilderView: View {
    @Binding var draft: ScheduleDraft

    private let dayLabels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Time", systemImage: "clock")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                Spacer()
                DatePicker("", selection: timeBinding, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }

            Picker("Frequency", selection: $draft.frequency) {
                Text("Daily").tag("daily")
                Text("Weekly").tag("weekly")
                Text("Custom").tag("custom")
            }
            .pickerStyle(.segmented)

            if draft.frequency != "daily" {
                HStack(spacing: 6) {
                    ForEach(Array(dayLabels.enumerated()), id: \.offset) { index, label in
                        let weekday = index + 1
                        let selected = draft.daysOfWeek.contains(weekday)
                        Button(label) {
                            if selected {
                                draft.daysOfWeek.removeAll { $0 == weekday }
                            } else {
                                draft.daysOfWeek.append(weekday)
                                draft.daysOfWeek.sort()
                            }
                        }
                        .buttonStyle(DayToggleButtonStyle(selected: selected))
                    }
                }
            }
        }
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                c.hour = draft.hour
                c.minute = draft.minute
                return Calendar.current.date(from: c) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                draft.hour = c.hour ?? 8
                draft.minute = c.minute ?? 0
            }
        )
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
