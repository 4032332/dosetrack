// DoseTrack/Views/Medications/MedicationsView.swift
import SwiftUI

struct MedicationsView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @EnvironmentObject private var caregiverManager: CaregiverManager
    @EnvironmentObject private var activeAccount: ActiveAccountContext
    @StateObject private var viewModel = MedicationsViewModel(
        context: PersistenceController.shared.viewContext
    )

    @AppStorage("patientGender")                private var patientGender: String = ""
    @AppStorage("contraceptiveStartInterval")   private var contraceptiveStartInterval: Double = 0
    @AppStorage("contraceptiveMethod")          private var contraceptiveMethod: String = ""

    @State private var isEditMode: EditMode = .inactive
    @Binding var showingAccountSwitcher: Bool
    /// Session-only dismissal for the out-of-stock nudge — reappears next time the tab is opened
    /// if the medication is still at 0 supply, so it can't be permanently swept under the rug
    /// without actually resolving it (remove or restock).
    @State private var dismissedOutOfStockIds: Set<UUID> = []

    init(showingAccountSwitcher: Binding<Bool> = .constant(false)) {
        self._showingAccountSwitcher = showingAccountSwitcher
    }

    private var shouldShowContraceptiveHint: Bool {
        let eligibleGenders = ["Female", "Other", "Prefer not to say"]
        guard eligibleGenders.contains(patientGender) else { return false }
        return contraceptiveStartInterval == 0 || contraceptiveMethod.isEmpty
    }

    /// True when the signed-in user is a patient whose caregiver relationship is active — their
    /// caregiver's Pro plan covers them, so the free-tier medication cap shouldn't apply.
    private var patientHasActiveCaregiver: Bool {
        caregiverManager.ownPatientRelationship?.isActive == true
    }

    /// The own-account medication cap is lifted for Pro subscribers and for patients covered by
    /// an active caregiver. (Caregivers viewing a patient are always Pro, handled separately.)
    private var effectivelyUnlimited: Bool {
        subscriptionManager.isProSubscriber || patientHasActiveCaregiver
    }

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
                if !caregiverManager.overseenPatients.isEmpty {
                    ToolbarItem(placement: .principal) {
                        AccountSwitcherPill(isPresented: $showingAccountSwitcher)
                    }
                }
                // Shown on the caregiver's own account AND while a caregiver is viewing an
                // overseen patient — managing the patient's medications (including adding new
                // ones) is the point of caregiver mode. Writes go to the patient's own store
                // and sync under the patient's userId; see AddEditMedicationViewModel.save.
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.requestAddMedication()
                    } label: {
                        Image(systemName: "plus")
                            .accessibilityLabel("Add medication")
                    }
                }
                if !viewModel.medications.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        EditButton()
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Picker("Sort", selection: $viewModel.sortMode) {
                                ForEach(MedicationSort.allCases) { mode in
                                    Label(mode.label, systemImage: mode.systemImage).tag(mode)
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                                .accessibilityLabel("Sort medications")
                        }
                    }
                }
            }
            .environment(\.editMode, $isEditMode)
            .navigationDestination(for: Medication.self) { med in
                MedicationDetailView(medication: med, onDelete: { viewModel.fetchMedications() })
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
        }
        .onAppear {
            viewModel.updateContext(context)
            viewModel.fetchMedications()
        }
        .onChange(of: context) { _, newContext in
            viewModel.updateContext(newContext)
        }
    }

    private var outOfStockMedications: [Medication] {
        viewModel.medications.filter { med in
            guard let id = med.id else { return false }
            return med.isOutOfStockOverADay && !dismissedOutOfStockIds.contains(id)
        }
    }

    private var medicationsList: some View {
        List {
            ForEach(outOfStockMedications) { med in
                OutOfStockNudgeCard(
                    medication: med,
                    onUpdateSupply: { viewModel.requestEdit(med) },
                    onRemove: { viewModel.requestDelete(med) },
                    onDismiss: {
                        if let id = med.id { dismissedOutOfStockIds.insert(id) }
                    }
                )
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            ForEach(viewModel.medications) { med in
                Button {
                    viewModel.requestEdit(med)
                } label: {
                    MedicationRowView(medication: med)
                }
                .foregroundStyle(.primary)
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
            .onDelete { offsets in
                for index in offsets {
                    viewModel.requestDelete(viewModel.medications[index])
                }
            }
            .onMove { viewModel.moveItems(from: $0, to: $1) }

            if shouldShowContraceptiveHint {
                Section {
                    NavigationLink(destination: ContraceptiveTrackerView()) {
                        HStack(spacing: 12) {
                            Image(systemName: "calendar.badge.clock")
                                .foregroundStyle(.purple)
                                .font(.body)
                                .frame(width: 28)
                            Text("Add a long term birth control reminder")
                                .font(.subheadline)
                                .foregroundStyle(.purple)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listRowBackground(Color.purple.opacity(0.08))
            }

            // Free-tier counter only applies to an uncovered user viewing their own account.
            // Hidden for Pro users, for patients covered by an active caregiver, and while a
            // caregiver is viewing a patient (whose meds aren't bound by the caregiver's own cap).
            if !effectivelyUnlimited && !activeAccount.isViewingOtherAccount {
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
        .scrollIndicators(.visible)
        .refreshable { viewModel.fetchMedications() }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            // SplashHero (the enthusiastic, arms-up mascot) rather than a plain SF Symbol — this
            // is the most commonly seen empty state (any fresh install, before adding a first
            // medication), and the previous placeholder icon never reflected the mascot at all.
            Image("SplashHero")
                .resizable()
                .scaledToFit()
                .frame(width: 130, height: 130)
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
        HStack(spacing: 14) {
            // Tinted squircle tile with the form icon — the same treatment used on the Restock
            // list (via MedicationColorTile) so the two screens share one visual language
            // instead of one using a bare 12pt dot and the other a big tile.
            MedicationColorTile(medication: medication)

            VStack(alignment: .leading, spacing: 3) {
                Text(medication.wrappedName)
                    .font(.body.weight(.medium))
                Text("\(medication.wrappedDosage) · \(medication.wrappedUnit)")
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
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// Shared 44pt tinted squircle showing a medication's colour + form icon. Used by both the
/// Medications and Restock lists so their rows look identical.
struct MedicationColorTile: View {
    @ObservedObject var medication: Medication
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                .fill(medication.color.opacity(0.16))
            Image(systemName: medication.unitIconName)
                .font(.system(size: size * 0.4))
                .foregroundStyle(medication.color)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Out-of-stock nudge

/// Shown at the top of the Medications list for any medication that's been sitting at 0 supply
/// for more than a day — a gentle nudge to either restock it or take it off the active list,
/// rather than a schedule silently reminding the user to take doses that don't exist. Non-
/// blocking: the rest of the list stays fully usable underneath it.
private struct OutOfStockNudgeCard: View {
    let medication: Medication
    let onUpdateSupply: () -> Void
    let onRemove: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(medication.wrappedName) is out of stock")
                        .font(.subheadline.weight(.semibold))
                    Text("It's been at 0 supply for over a day. Remove it or update your supply?")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                Button(action: onUpdateSupply) {
                    Text("Update Supply")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button(role: .destructive, action: onRemove) {
                    Text("Remove")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

#Preview {
    MedicationsView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
        .environmentObject(SubscriptionManager())
        .environmentObject(CaregiverManager.shared)
        .environmentObject(ActiveAccountContext(ownUserId: UUID(), ownDisplayName: "Preview User"))
}
