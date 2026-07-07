// DoseTrack/Views/History/CalendarView.swift
import SwiftUI

/// Monthly calendar grid showing adherence dots for each day.
struct CalendarView: View {
    let days: [DayAdherence]
    @Binding var displayedMonth: Date

    private let columns = Array(repeating: GridItem(.flexible()), count: 7)
    private let weekdaySymbols = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]

    private var calendar: Calendar { Calendar.current }

    private var monthStart: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)) ?? displayedMonth
    }

    private var daysInMonth: Int {
        calendar.range(of: .day, in: .month, for: displayedMonth)?.count ?? 30
    }

    private var firstWeekday: Int {
        // 0-based offset (0=Sunday)
        (calendar.component(.weekday, from: monthStart) - 1 + 7) % 7
    }

    private var dayMap: [Date: DayAdherence] {
        Dictionary(uniqueKeysWithValues: days.map { ($0.id, $0) })
    }

    var body: some View {
        VStack(spacing: 8) {
            // Month navigation header
            HStack {
                Button {
                    displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("Previous month")

                Spacer()

                Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.headline)

                Spacer()

                Button {
                    let next = calendar.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
                    if next <= Date() {
                        displayedMonth = next
                    }
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(isSameMonth(displayedMonth, as: Date()))
                .accessibilityLabel("Next month")
            }
            .padding(.horizontal, 4)

            // Weekday headers
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                // Empty leading cells
                ForEach(0..<firstWeekday, id: \.self) { _ in
                    Color.clear.frame(height: 36)
                }

                // Day cells
                ForEach(1...daysInMonth, id: \.self) { day in
                    dayCell(for: day)
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(for day: Int) -> some View {
        let date = calendar.date(bySetting: .day, value: day, of: monthStart) ?? monthStart
        let dayStart = calendar.startOfDay(for: date)
        let adherence = dayMap[dayStart]
        let isToday = calendar.isDateInToday(date)
        let isFuture = date > Date()

        VStack(spacing: 2) {
            Text("\(day)")
                .font(.caption)
                .fontWeight(isToday ? .bold : .regular)
                .foregroundStyle(isToday ? .white : isFuture ? .secondary : .primary)
                .frame(width: 26, height: 26)
                .background(isToday ? Color.accentColor : Color.clear)
                .clipShape(Circle())

            // Adherence dot
            if let ad = adherence, ad.total > 0, !isFuture {
                Circle()
                    .fill(ad.color)
                    .frame(width: 5, height: 5)
            } else {
                Color.clear.frame(width: 5, height: 5)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func isSameMonth(_ a: Date, as b: Date) -> Bool {
        calendar.isDate(a, equalTo: b, toGranularity: .month)
    }
}
