// DoseTrack/Views/Medications/MedicationDetailView.swift
import SwiftUI
import WidgetKit

struct MedicationDetailView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    let medication: Medication
    /// Called after a successful delete (before/around `dismiss()`) so the caller
    /// (the Medications list) can refetch — its own `.onAppear` is attached to the
    /// outer NavigationStack and does NOT refire when popping back from a pushed
    /// detail view, so without this callback the list would silently show stale
    /// data (the just-deleted medication) until the tab was fully re-entered.
    var onDelete: () -> Void = {}
    @State private var showingEditSheet = false
    @State private var showingDeleteConfirm = false

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
        .scrollIndicators(.visible)
        .navigationTitle(medication.wrappedName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingEditSheet = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            AddEditMedicationView(
                viewModel: AddEditMedicationViewModel(context: context, medication: medication),
                onSave: { _ in }
            )
        }
        .confirmationDialog(
            "Delete \(medication.wrappedName)?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { softDeleteAndDismiss() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the medication from your active list. History is preserved.")
        }
    }

    /// Soft-delete (isActive = false, preserving history — same convention as
    /// MedicationsViewModel.confirmSoftDelete), then pop back to the list, whose
    /// own .onAppear re-fetches and reflects the removal.
    private func softDeleteAndDismiss() {
        medication.isActive = false
        try? context.save()
        WidgetCenter.shared.reloadAllTimelines()
        // Push the tombstone, or a stale remote row keeps this medication looking active on
        // the next pull.
        let pushUserId = ActiveAccountResolver.shared.activeUserId
        Task { await SupabaseSyncManager.shared.pushMedication(medication, forUserId: pushUserId) }
        onDelete()
        dismiss()
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
