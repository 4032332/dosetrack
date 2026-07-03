// DoseTrack/Views/Settings/ContraceptiveTrackerView.swift
import SwiftUI

struct ContraceptiveTrackerView: View {

    // MARK: - Persisted state

    @AppStorage("contraceptiveName")          private var name: String = ""
    @AppStorage("contraceptiveMethod")        private var methodRaw: String = ""
    @AppStorage("contraceptiveStartInterval") private var startInterval: Double = 0
    @AppStorage("contraceptiveDurationValue") private var durationValue: Int = 1
    @AppStorage("contraceptiveDurationUnit")  private var durationUnit: String = "year"

    // MARK: - Local UI state

    @State private var showClearConfirm = false

    // MARK: - Types

    enum Method: String, CaseIterable, Identifiable {
        case pill      = "Pill"
        case implant   = "Implant"
        case iud       = "IUD"
        case injection = "Injection"
        case ring      = "Ring"
        case patch     = "Patch"
        case other     = "Other"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .pill:      return "pills.fill"
            case .implant:   return "bandage.fill"
            case .iud:       return "staple.fill"
            case .injection: return "syringe.fill"
            case .ring:      return "circle.dotted"
            case .patch:     return "square.on.square.fill"
            case .other:     return "cross.case.fill"
            }
        }

        var startDateLabel: String {
            switch self {
            case .pill:      return "Day started"
            case .implant:   return "Date implanted"
            case .iud:       return "Date inserted"
            case .injection: return "Date injected"
            case .ring:      return "Date started"
            case .patch:     return "Date applied"
            case .other:     return "Start date"
            }
        }

        var durationLabel: String {
            switch self {
            case .pill:             return "Take every"
            case .implant, .iud:   return "Replace every"
            case .injection:        return "Repeat every"
            case .ring:             return "Change every"
            case .patch:            return "Change every"
            case .other:            return "Repeat every"
            }
        }
    }

    enum DurationUnit: String, CaseIterable, Identifiable {
        case day   = "day"
        case week  = "week"
        case month = "month"
        case year  = "year"

        var id: String { rawValue }

        func label(for value: Int) -> String {
            value == 1 ? rawValue : rawValue + "s"
        }
    }

    // MARK: - Computed

    private var selectedMethod: Method {
        Method(rawValue: methodRaw) ?? .pill
    }

    private var startDate: Date {
        startInterval > 0 ? Date(timeIntervalSince1970: startInterval) : Date()
    }

    private var startDateBinding: Binding<Date> {
        Binding(
            get: { startDate },
            set: { startInterval = $0.timeIntervalSince1970 }
        )
    }

    var dueDate: Date? {
        guard startInterval > 0 else { return nil }
        let cal = Calendar.current
        switch DurationUnit(rawValue: durationUnit) ?? .year {
        case .day:   return cal.date(byAdding: .day,        value: durationValue, to: startDate)
        case .week:  return cal.date(byAdding: .weekOfYear, value: durationValue, to: startDate)
        case .month: return cal.date(byAdding: .month,      value: durationValue, to: startDate)
        case .year:  return cal.date(byAdding: .year,       value: durationValue, to: startDate)
        }
    }

    private var daysUntilDue: Int? {
        guard let due = dueDate else { return nil }
        let today = Calendar.current.startOfDay(for: Date())
        return Calendar.current.dateComponents([.day], from: today, to: due).day
    }

    private var isConfigured: Bool { startInterval > 0 && !methodRaw.isEmpty }

    // MARK: - Body

    var body: some View {
        List {
            // MARK: Name
            Section("Contraceptive Name") {
                TextField("e.g. Mirena, Depo-Provera, Microgynon", text: $name)
                    .autocorrectionDisabled()
            }

            // MARK: Method
            Section("Method of Administration") {
                ForEach(Method.allCases) { method in
                    Button {
                        methodRaw = method.rawValue
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: method.icon)
                                .frame(width: 22)
                                .foregroundStyle(selectedMethod == method ? Color.accentColor : .secondary)
                            Text(method.rawValue)
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedMethod == method {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                }
            }

            // MARK: Start date
            if !methodRaw.isEmpty {
                Section(selectedMethod.startDateLabel) {
                    if startInterval > 0 {
                        CollapsibleDatePicker(
                            label: selectedMethod.startDateLabel,
                            systemImage: "calendar",
                            date: startDateBinding,
                            range: ...Date()
                        )
                        Button("Remove date", role: .destructive) {
                            startInterval = 0
                        }
                        .font(.caption)
                    } else {
                        Button {
                            startInterval = Date().timeIntervalSince1970
                        } label: {
                            HStack {
                                Text(selectedMethod.startDateLabel)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("Set date")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }

                // MARK: Frequency / duration
                Section(selectedMethod.durationLabel) {
                    HStack(spacing: 12) {
                        // Numeric stepper
                        HStack {
                            Button {
                                if durationValue > 1 { durationValue -= 1 }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)

                            Text("\(durationValue)")
                                .font(.title3.monospacedDigit())
                                .frame(minWidth: 32, alignment: .center)

                            Button {
                                durationValue += 1
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                            .buttonStyle(.plain)
                        }

                        Divider()

                        // Unit picker
                        Picker("", selection: $durationUnit) {
                            ForEach(DurationUnit.allCases) { unit in
                                Text(unit.label(for: durationValue)).tag(unit.rawValue)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)
                        .frame(height: 80)
                        .clipped()
                    }
                    .padding(.vertical, 4)
                }
            }

            // MARK: Summary card
            if isConfigured, let due = dueDate {
                Section("Summary") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label(name.isEmpty ? selectedMethod.rawValue : name,
                                  systemImage: selectedMethod.icon)
                                .font(.headline)
                            Spacer()
                            statusBadge
                        }

                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Label(startDate.formatted(date: .abbreviated, time: .omitted),
                                      systemImage: "calendar")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Label(due.formatted(date: .abbreviated, time: .omitted),
                                      systemImage: "calendar.badge.exclamationmark")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let days = daysUntilDue {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(days < 0 ? "Overdue" : "\(days) days")
                                        .font(.title3.bold())
                                        .foregroundStyle(urgencyColor)
                                    Text(days < 0 ? "past due date" : "until due")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            // MARK: Clear
            if isConfigured {
                Section {
                    Button("Clear Contraceptive Tracker", role: .destructive) {
                        showClearConfirm = true
                    }
                }
            }
        }
        .scrollIndicators(.visible)
        .contentMargins(.bottom, 32, for: .scrollContent)
        .navigationTitle("Contraceptive Tracker")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Clear all contraceptive tracking data?",
                            isPresented: $showClearConfirm,
                            titleVisibility: .visible) {
            Button("Clear Data", role: .destructive) {
                name = ""
                methodRaw = ""
                startInterval = 0
                durationValue = 1
                durationUnit = "year"
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Helpers

    private var urgencyColor: Color {
        guard let days = daysUntilDue else { return .secondary }
        if days < 0  { return .red }
        if days < 14 { return .orange }
        if days < 30 { return .yellow }
        return .green
    }

    @ViewBuilder
    private var statusBadge: some View {
        if let days = daysUntilDue {
            if days < 0 {
                Text("Overdue").font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.red.opacity(0.15)).foregroundStyle(.red)
                    .clipShape(Capsule())
            } else if days < 30 {
                Text("Due soon").font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.orange.opacity(0.15)).foregroundStyle(.orange)
                    .clipShape(Capsule())
            } else {
                Text("Active").font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.green.opacity(0.15)).foregroundStyle(.green)
                    .clipShape(Capsule())
            }
        }
    }
}

#Preview {
    NavigationStack {
        ContraceptiveTrackerView()
    }
}
