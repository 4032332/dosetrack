// DoseTrackWatch Watch App/ComplicationProvider.swift
import ClockKit
import SwiftUI

// MARK: - Complication Data Source

class ComplicationDataSource: NSObject, CLKComplicationDataSource {

    // MARK: - Timeline

    func getSupportedTimeTravelDirections(
        for complication: CLKComplication,
        withHandler handler: @escaping (CLKComplicationTimeTravelDirections) -> Void
    ) {
        handler([])
    }

    func getCurrentTimelineEntry(
        for complication: CLKComplication,
        withHandler handler: @escaping (CLKComplicationTimelineEntry?) -> Void
    ) {
        let meds = WatchConnectivityReceiver.shared.medications
        let next = meds.first(where: { !$0.isTaken && $0.scheduledAt > Date() })
            ?? meds.first(where: { !$0.isTaken })

        let template = makeTemplate(for: complication.family, nextDose: next)
        let entry = template.map { CLKComplicationTimelineEntry(date: Date(), complicationTemplate: $0) }
        handler(entry)
    }

    func getTimelineEndDate(
        for complication: CLKComplication,
        withHandler handler: @escaping (Date?) -> Void
    ) {
        handler(Calendar.current.date(byAdding: .hour, value: 24, to: Date()))
    }

    func getLocalizableSampleTemplate(
        for complication: CLKComplication,
        withHandler handler: @escaping (CLKComplicationTemplate?) -> Void
    ) {
        handler(makeSampleTemplate(for: complication.family))
    }

    // MARK: - Template Builders

    private func makeTemplate(
        for family: CLKComplicationFamily,
        nextDose: WatchMedication?
    ) -> CLKComplicationTemplate? {
        let name = nextDose?.name ?? "No doses"
        let timeText = nextDose.map {
            CLKRelativeDateTextProvider(
                date: $0.scheduledAt,
                style: .natural,
                units: [.hour, .minute]
            )
        }

        switch family {
        case .modularSmall:
            let template = CLKComplicationTemplateModularSmallStackText()
            template.line1TextProvider = CLKSimpleTextProvider(text: "💊")
            template.line2TextProvider = CLKSimpleTextProvider(text: timeText != nil ? "" : "✓")
            return template

        case .circularSmall:
            let template = CLKComplicationTemplateCircularSmallStackText()
            template.line1TextProvider = CLKSimpleTextProvider(text: "💊")
            template.line2TextProvider = timeText ?? CLKSimpleTextProvider(text: "✓")
            return template

        case .graphicCorner:
            let template = CLKComplicationTemplateGraphicCornerStackText()
            template.innerTextProvider = CLKSimpleTextProvider(text: name)
            template.outerTextProvider = timeText ?? CLKSimpleTextProvider(text: "All done")
            return template

        case .graphicCircular:
            let template = CLKComplicationTemplateGraphicCircularView(
                ComplicationCircularView(nextDose: nextDose)
            )
            return template

        default:
            return nil
        }
    }

    private func makeSampleTemplate(for family: CLKComplicationFamily) -> CLKComplicationTemplate? {
        let sampleMed = WatchMedication(
            id: "sample",
            name: "Metformin",
            dosage: "500mg",
            colorHex: "#5B8AF0",
            scheduledAt: Date(timeIntervalSinceNow: 3600),
            isTaken: false,
            scheduleId: "sample"
        )
        return makeTemplate(for: family, nextDose: sampleMed)
    }
}

// MARK: - Graphic Circular Complication View
// Shows Milli image transitioning from greyscale to full colour as doses are completed.

struct ComplicationCircularView: View {
    let nextDose: WatchMedication?

    private var takenCount: Int {
        WatchConnectivityReceiver.shared.medications.filter(\.isTaken).count
    }
    private var totalCount: Int {
        WatchConnectivityReceiver.shared.medications.count
    }
    private var completionFraction: Double {
        guard totalCount > 0 else { return 0 }
        return min(Double(takenCount) / Double(totalCount), 1.0)
    }

    var body: some View {
        ZStack {
            // Progress ring
            Circle()
                .stroke(Color.primary.opacity(0.15), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: completionFraction)
                .stroke(
                    completionFraction >= 1 ? Color.green : Color.accentColor,
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut, value: completionFraction)

            // Milli mascot — greyscale base with coloured overlay
            if let img = UIImage(named: "OnboardingWelcome") {
                ZStack {
                    Image(uiImage: img)
                        .resizable().scaledToFit()
                        .grayscale(1.0)
                        .opacity(0.5)
                        .padding(6)

                    if completionFraction > 0 {
                        Image(uiImage: img)
                            .resizable().scaledToFit()
                            .padding(6)
                            .mask(alignment: .bottom) {
                                GeometryReader { geo in
                                    Rectangle()
                                        .frame(height: geo.size.height * completionFraction)
                                        .frame(maxHeight: .infinity, alignment: .bottom)
                                }
                            }
                    }
                }
            } else {
                Text(completionFraction >= 1 ? "✓" : "💊")
                    .font(.system(size: 14))
            }
        }
    }
}
