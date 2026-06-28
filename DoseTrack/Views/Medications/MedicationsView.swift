// DoseTrack/Views/Medications/MedicationsView.swift
import SwiftUI

struct MedicationsView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @StateObject private var viewModel = MedicationsViewModel(
        context: PersistenceController.shared.viewContext
    )

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.medications.isEmpty {
                    emptyState
                } else {
                    medicationsList
                }
            }
            .navigationTitle("Medications")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.requestAddMedication()
                    } label: {
                        Image(systemName: "plus")
                            .accessibilityLabel("Add medication")
                    }
                }
            }
            .navigationDestination(for: Medication.self) { med in
                MedicationDetailView(medication: med)
            }
            .sheet(isPresented: $viewModel.showingAddForm, onDismiss: { viewModel.fetchMedications() }) {
                AddEditMedicationView(
                    viewModel: AddEditMedicationViewModel(context: context),
                    onSave: { _ in viewModel.fetchMedications() }
                )
            }
            .sheet(item: $viewModel.medicationToEdit, onDismiss: { viewModel.fetchMedications() }) { med in
                AddEditMedicationView(
                    viewModel: AddEditMedicationViewModel(context: context, medication: med),
                    onSave: { _ in viewModel.fetchMedications() }
                )
            }
            .sheet(isPresented: $viewModel.showingPaywall) {
                PaywallView()
            }
            .confirmationDialog(
                "Delete \(viewModel.medicationToDelete?.wrappedName ?? "medication")?",
                isPresented: $viewModel.showingDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { viewModel.confirmSoftDelete() }
                Button("Cancel", role: .cancel) { viewModel.cancelDelete() }
            } message: {
                Text("This removes the medication from your active list. History is preserved.")
            }
        }
        .onAppear { viewModel.fetchMedications() }
    }

    private var medicationsList: some View {
        List {
            ForEach(viewModel.medications) { med in
                NavigationLink(value: med) {
                    MedicationRowView(medication: med)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        viewModel.requestDelete(med)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }

                    Button {
                        viewModel.requestEdit(med)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
            }
            .onMove { viewModel.moveItems(from: $0, to: $1) }

            if !subscriptionManager.isProSubscriber {
                Section {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                        Text("\(viewModel.medications.count) of \(Constants.FreeTier.maxMedications) medications (free tier)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if viewModel.medications.count >= Constants.FreeTier.maxMedications {
                            Button("Upgrade") { viewModel.showingPaywall = true }
                                .font(.caption.weight(.semibold))
                        }
                    }
                }
            }
        }
        .environment(\.editMode, .constant(.active))
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "pill.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary.opacity(0.5))
            Text("No Medications Yet")
                .font(.title2.weight(.semibold))
            Text("Add your first medication to get started.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                viewModel.requestAddMedication()
            } label: {
                Label("Add Medication", systemImage: "plus")
                    .padding(.horizontal)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

private struct MedicationRowView: View {
    @ObservedObject var medication: Medication

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(medication.color)
                .frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(medication.wrappedName)
                    .font(.body.weight(.medium))
                Text("\(medication.wrappedDosage) \(medication.wrappedUnit)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if medication.isRefillWarning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Refill warning")
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    MedicationsView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
        .environmentObject(SubscriptionManager())
}
