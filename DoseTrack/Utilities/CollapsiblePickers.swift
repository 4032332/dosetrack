// DoseTrack/Utilities/CollapsiblePickers.swift
import SwiftUI

// MARK: - CollapsibleDatePicker

/// A tappable row that expands to a wheel DatePicker and collapses when Done is tapped.
struct CollapsibleDatePicker: View {
    let label: String
    let systemImage: String
    @Binding var date: Date
    var range: PartialRangeThrough<Date>? = nil
    var displayedComponents: DatePickerComponents = .date

    @AppStorage("timeFormat") private var timeFormat: String = "system"
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            // Tappable summary row
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack {
                    Label(label, systemImage: systemImage)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(formattedValue)
                        .foregroundStyle(isExpanded ? Color.accentColor : .secondary)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            // Expanded wheel + Done button
            if isExpanded {
                if let range = range {
                    DatePicker("", selection: $date, in: range, displayedComponents: displayedComponents)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                } else {
                    DatePicker("", selection: $date, displayedComponents: displayedComponents)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                }

                Button("Done") {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded = false }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 4)
            }
        }
    }

    private var formattedValue: String {
        if displayedComponents == .hourAndMinute {
            return TimeFormatPreference.string(for: date, preference: timeFormat)
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

// MARK: - CollapsibleTimePicker

/// Convenience wrapper for time-only wheel picker.
struct CollapsibleTimePicker: View {
    let label: String
    let systemImage: String
    @Binding var date: Date

    @AppStorage("timeFormat") private var timeFormat: String = "system"
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack {
                    Label(label, systemImage: systemImage)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(TimeFormatPreference.string(for: date, preference: timeFormat))
                        .foregroundStyle(isExpanded ? Color.accentColor : .secondary)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                DatePicker("", selection: $date, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()

                Button("Done") {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded = false }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 4)
            }
        }
    }
}
