// DoseTrack/Views/Medications/MedicationDetailView.swift
import SwiftUI

struct MedicationDetailView: View {
    @Environment(\.managedObjectContext) private var context
    let medication: Medication
    @State private var showingEditSheet = false

    var body: some View {
        List {
            // Header
            Section {
                HStack(spacing: 16) {
                    Circle()
                        .fill(medication.color)
                        .frame(width: 48, height: 48)
                    VStack(alignment: .leading) {
                        Text(medication.wrappedName)
                            .font(.title2.weight(.semibold))
                        Text("\(medication.wrappedDosage) · \(medication.wrappedUnit)")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            // Schedules
            Section("Schedules") {
                if medication.schedulesArray.isEmpty {
                    Text("No schedules set").foregroundStyle(.secondary)
                } else {
                    ForEach(medication.schedulesArray, id: \.id) { schedule in
                        HStack {
                            Image(systemName: "clock")
                                .foregroundStyle(Color.accentColor)
                            Text(schedule.timeDescription)
                            Spacer()
                            Text(scheduleLabel(schedule))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !schedule.isEnabled {
                                Text("Off")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
            }

            // Supply / refill
            if medication.currentCount > 0 {
                Section("Supply") {
                    HStack {
                        Label("\(medication.currentCount) remaining", systemImage: "pills.fill")
                        Spacer()
                        if medication.isRefillWarning {
                            Label("Refill soon", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }

            // Notes
            if !medication.wrappedNotes.isEmpty {
                Section("Notes") {
                    Text(medication.wrappedNotes)
                        .foregroundStyle(.secondary)
                }
            }

            // Photo
            if let data = medication.photoData, let img = UIImage(data: data) {
                Section("Photo") {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            Section {
                Text("DoseTrack is a reminder tool, not medical advice. Always follow your healthcare provider's instructions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(medication.wrappedName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showingEditSheet = true }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            AddEditMedicationView(
                viewModel: AddEditMedicationViewModel(context: context, medication: medication),
                onSave: { _ in }
            )
        }
    }

    private func scheduleLabel(_ schedule: Schedule) -> String {
        switch schedule.wrappedFrequency {
        case "daily":
            return "Every day"
        case "weekly", "custom":
            let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            let selected = schedule.daysOfWeekArray.compactMap { d -> String? in
                guard d >= 1, d <= 7 else { return nil }
                return days[d - 1]
            }
            return selected.isEmpty ? "Every day" : selected.joined(separator: ", ")
        default:
            return schedule.wrappedFrequency
        }
    }
}
