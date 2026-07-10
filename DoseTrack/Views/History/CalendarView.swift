// DoseTrack/Views/History/CalendarView.swift
import SwiftUI

/// Monthly calendar grid showing adherence dots for each day.
struct CalendarView: View {
    let days: [DayAdherence]
    @Binding var displayedMonth: Date
    /// Called when a non-future day is tapped, so the History screen can show that day's doses.
    var onSelectDay: (Date) -> Void = { _ in }

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

                // Always exactly 42 cells (6 weeks × 7 days) — a FIXED item count regardless of
                // which month is displayed, padding with blank cells before day 1 and after the
                // month's last day. Previously this used two variable-length ForEach ranges
                // (0..<firstWeekday for leading blanks, 1...daysInMonth for real days), so the
                // grid's total item count changed on every month navigation. SwiftUI's List is
                // UICollectionView-backed on modern iOS, and changing a nested grid's item count
                // while it's inside a List row is a known trigger for a
                // "_UICollectionViewFeedbackLoop" internal UIKit assertion crash — exactly the
                // crash TestFlight reported, reproducible specifically (and only) on this screen.
                // A constant cell count regardless of month removes the trigger at the root.
                ForEach(0..<42, id: \.self) { index in
                    dayCell(forCellIndex: index)
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(forCellIndex index: Int) -> some View {
        let day = index - firstWeekday + 1
        if day < 1 || day > daysInMonth {
            Color.clear.frame(height: 36)
        } else {
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
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isFuture else { return }
                onSelectDay(dayStart)
            }
        }
    }

    private func isSameMonth(_ a: Date, as b: Date) -> Bool {
        calendar.isDate(a, equalTo: b, toGranularity: .month)
    }
}
