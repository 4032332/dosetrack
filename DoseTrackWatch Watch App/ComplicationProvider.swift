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

struct ComplicationCircularView: View {
    let nextDose: WatchMedication?

    var body: some View {
        ZStack {
            if let dose = nextDose {
                Circle()
                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 2)
                VStack(spacing: 0) {
                    Image(systemName: "pills.fill")
                        .font(.system(size: 10))
                    Text(dose.scheduledAt, style: .time)
                        .font(.system(size: 8))
                        .minimumScaleFactor(0.6)
                }
            } else {
                Circle()
                    .stroke(Color.green.opacity(0.5), lineWidth: 2)
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.green)
            }
        }
    }
}
