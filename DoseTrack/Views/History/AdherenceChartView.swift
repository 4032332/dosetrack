// DoseTrack/Views/History/AdherenceChartView.swift
import SwiftUI
import Charts

struct AdherenceChartView: View {
    let days: [DayAdherence]

    private var showXLabels: Bool { days.count <= 14 }

    var body: some View {
        Chart(days) { day in
            BarMark(
                x: .value("Date", day.date, unit: .day),
                y: .value("Adherence", day.percent * 100)
            )
            .foregroundStyle(barColor(for: day))
            .cornerRadius(3)
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                AxisGridLine()
                AxisValueLabel { Text("\(value.as(Int.self) ?? 0)%") }
            }
        }
        .chartXAxis {
            // Week view (short range): a single narrow weekday letter reads as the
            // familiar M T W T F S S strip. Longer ranges keep numeric day/month —
            // weekday letters would be ambiguous once a range spans multiple weeks.
            if showXLabels {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
            } else {
                AxisMarks(values: .stride(by: .weekOfYear)) { value in
                    AxisValueLabel(format: .dateTime.day().month(.defaultDigits))
                }
            }
        }
        .frame(height: 180)
    }

    private func barColor(for day: DayAdherence) -> Color {
        if day.total == 0 { return .gray.opacity(0.3) }
        return day.color
    }
}

#Preview {
    let calendar = Calendar.current
    let today = Date()
    let days: [DayAdherence] = (0..<7).map { offset in
        let date = calendar.date(byAdding: .day, value: -offset, to: today)!
        let taken = Int.random(in: 0...3)
        return DayAdherence(id: date, date: date, taken: taken, total: 3)
    }
    return AdherenceChartView(days: days)
        .padding()
}
