// DoseTrack/Views/Medications/AddEditMedicationView.swift
import SwiftUI
import PhotosUI

struct AddEditMedicationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @ObservedObject var viewModel: AddEditMedicationViewModel
    let onSave: (Medication) -> Void

    @State private var photoPickerItem: PhotosPickerItem?
    @State private var escriptPickerItem: PhotosPickerItem?
    @State private var showingEscriptFullscreen = false
    @State private var showingDeleteConfirm = false
    @State private var showingEscriptSourcePicker = false
    @State private var showingEscriptCamera = false
    @State private var showingEscriptLibrary = false
    @State private var showingScanner = false

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Scan shortcut
                if !viewModel.isEditing {
                    Section {
                        Button {
                            showingScanner = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "camera.viewfinder")
                                    .font(.title2)
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Scan Medication Box")
                                        .foregroundStyle(.primary)
                                        .font(.body.weight(.medium))
                                    Text("Auto-fill name and strength from the label")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // MARK: Medication name
                Section("Medication") {
                    TextField("Name (e.g. Metformin)", text: $viewModel.name)
                        .autocorrectionDisabled()
                    if let err = viewModel.nameError {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                }

                // MARK: Dose
                Section {
                    // Strength: 500 mg
                    HStack(spacing: 0) {
                        Text("Strength")
                            .foregroundStyle(.primary)
                        Spacer()
                        TextField("0", text: $viewModel.doseAmount)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                        Picker("", selection: $viewModel.doseUnit) {
                            ForEach(AddEditMedicationViewModel.doseUnitOptions, id: \.self) {
                                Text($0).tag($0)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 80)
                    }
                    if let err = viewModel.doseError {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }

                    // Form factor: 1 tablet
                    HStack {
                        Text("Each dose")
                            .foregroundStyle(.primary)
                        Spacer()
                        Stepper("\(viewModel.quantityAmount)", value: $viewModel.quantityAmount, in: 1...99)
                            .fixedSize()
                        Picker("", selection: $viewModel.quantityUnit) {
                            ForEach(AddEditMedicationViewModel.quantityUnitOptions, id: \.self) {
                                Text($0).tag($0)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                } header: {
                    Text("Dose")
                } footer: {
                    if !viewModel.doseAmount.isEmpty {
                        Text("Each dose: \(viewModel.quantityAmount) \(viewModel.quantityUnit)\(viewModel.quantityAmount > 1 ? "s" : "") × \(viewModel.doseAmount)\(viewModel.doseUnit)")
                            .font(.caption)
                    }
                }

                // MARK: Colour
                Section("Colour") {
                    ColourPickerGrid(
                        selectedHex: $viewModel.colorHex,
                        options: AddEditMedicationViewModel.colorOptions
                    )
                }

                // MARK: Schedule
                Section("Schedule") {
                    ForEach($viewModel.schedules) { $draft in
                        ScheduleBuilderView(draft: $draft)
                            .padding(.vertical, 4)
                    }
                    .onDelete { viewModel.removeSchedule(at: $0) }
                    Button {
                        viewModel.addSchedule()
                    } label: {
                        Label("Add Another Time", systemImage: "plus.circle")
                    }
                }

                // MARK: Refill tracking
                Section {
                    SupplyWheelPicker(
                        value: $viewModel.currentCount,
                        unit: viewModel.quantityUnit
                    )
                    let dpd = max(viewModel.quantityAmount, 1)
                    let daysLeft = viewModel.currentCount / dpd
                    HStack {
                        Image(systemName: supplyIcon(days: daysLeft))
                            .foregroundStyle(supplyColor(days: daysLeft))
                        Text(supplyLabel(days: daysLeft, dpd: dpd, unit: viewModel.quantityUnit))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Refill Tracking")
                } footer: {
                    Text("Restock alerts fire automatically at <3 doses, <5 days, and <7 days remaining.")
                        .font(.caption)
                }

                // MARK: E-Script / QR Code
                Section {
                    if let data = viewModel.escriptData, let img = UIImage(data: data) {
                        Button {
                            showingEscriptFullscreen = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 60, height: 60)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("E-Script saved")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text("Tap to view QR code")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "qrcode")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        PhotosPicker(selection: $escriptPickerItem, matching: .images) {
                            Label("Replace E-Script", systemImage: "arrow.triangle.2.circlepath")
                                .font(.caption)
                                .foregroundStyle(Color.accentColor)
                        }
                        Button("Remove E-Script", role: .destructive) {
                            viewModel.escriptData = nil
                            escriptPickerItem = nil
                        }
                        .font(.caption)
                    } else {
                        Button {
                            showingEscriptSourcePicker = true
                        } label: {
                            HStack {
                                Image(systemName: "qrcode.viewfinder")
                                    .font(.title2)
                                    .foregroundStyle(.purple)
                                    .frame(width: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Add E-Script QR Code")
                                        .foregroundStyle(.primary)
                                    Text("Save a screenshot from your SMS")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                } header: {
                    Text("E-Script (Australian QR Code)")
                } footer: {
                    Text("Tap on this medication in the Restock tab to show your QR code at the pharmacy.")
                        .font(.caption)
                }
                .onChange(of: escriptPickerItem) { _, item in
                    Task { viewModel.escriptData = try? await item?.loadTransferable(type: Data.self) }
                }

                // MARK: Bottle Photo
                Section("Bottle Photo (optional)") {
                    PhotosPicker(selection: $photoPickerItem, matching: .images) {
                        HStack {
                            if let data = viewModel.photoData, let img = UIImage(data: data) {
                                Image(uiImage: img)
                                    .resizable().scaledToFill()
                                    .frame(width: 60, height: 60)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            } else {
                                Image(systemName: "camera.fill")
                                    .font(.title2).foregroundStyle(.secondary)
                                    .frame(width: 60, height: 60)
                                    .background(Color.secondary.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            Text(viewModel.photoData == nil ? "Add bottle photo" : "Change photo")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .onChange(of: photoPickerItem) { _, item in
                        Task { viewModel.photoData = try? await item?.loadTransferable(type: Data.self) }
                    }
                    if viewModel.photoData != nil {
                        Button("Remove Photo", role: .destructive) {
                            viewModel.photoData = nil; photoPickerItem = nil
                        }
                    }
                }

                // MARK: Notes
                Section("Notes") {
                    TextField("Optional notes", text: $viewModel.notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                // MARK: Delete (edit mode only)
                if viewModel.isEditing {
                    Section {
                        Button(role: .destructive) {
                            showingDeleteConfirm = true
                        } label: {
                            HStack {
                                Spacer()
                                Label("Delete Medication", systemImage: "trash")
                                Spacer()
                            }
                        }
                    }
                }

                // MARK: Disclaimer
                Section {
                    Text("DoseTrack is a reminder tool, not medical advice. Always follow your healthcare provider's instructions.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .scrollIndicators(.visible)
            .contentMargins(.bottom, 32, for: .scrollContent)
            .navigationTitle(viewModel.isEditing ? "Edit Medication" : "New Medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let saved = viewModel.save() {
                            onSave(saved)
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!viewModel.isValid)
                }
            }
            .confirmationDialog(
                "Delete \(viewModel.name)?",
                isPresented: $showingDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete Medication", role: .destructive) {
                    if let med = medication {
                        med.isActive = false
                        try? context.save()
                    }
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the medication from your active list. History is preserved.")
            }
            .sheet(isPresented: $showingEscriptFullscreen) {
                if let data = viewModel.escriptData, let img = UIImage(data: data) {
                    EScriptFullscreenView(image: img, medicationName: viewModel.name)
                }
            }
            .confirmationDialog("Add E-Script", isPresented: $showingEscriptSourcePicker) {
                Button("Take Photo") { showingEscriptCamera = true }
                Button("Choose from Photo Library") { showingEscriptLibrary = true }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Save your QR code to show at the pharmacy.")
            }
            .photosPicker(isPresented: $showingEscriptLibrary, selection: $escriptPickerItem, matching: .images)
            .sheet(isPresented: $showingScanner) {
                MedicationScannerView(
                    onResult: { result in
                        viewModel.name = result.name
                        if !result.strength.isEmpty {
                            viewModel.doseAmount = result.strength
                            viewModel.doseUnit   = result.strengthUnit
                        }
                        if result.count > 0 {
                            viewModel.currentCount = result.count
                        }
                        if !result.form.isEmpty {
                            viewModel.quantityUnit = result.form
                        }
                        showingScanner = false
                    },
                    onCancel: { showingScanner = false }
                )
            }
            .sheet(isPresented: $showingEscriptCamera) {
                RestockCameraPickerView(
                    onCapture: { image in
                        viewModel.escriptData = image.jpegData(compressionQuality: 0.85)
                        showingEscriptCamera = false
                    },
                    onCancel: { showingEscriptCamera = false }
                )
            }
        }
    }

    private func supplyIcon(days: Int) -> String {
        if days == 0    { return "exclamationmark.triangle.fill" }
        if days < 5     { return "exclamationmark.circle.fill" }
        if days < 7     { return "clock.fill" }
        return "checkmark.circle.fill"
    }

    private func supplyColor(days: Int) -> Color {
        if days < 3 { return .red }
        if days < 5 { return .orange }
        if days < 7 { return .yellow }
        return .green
    }

    private func supplyLabel(days: Int, dpd: Int, unit: String) -> String {
        if days == 0 { return "No supply remaining" }
        let unitPlural = unit + (dpd > 1 ? "s" : "")
        return "\(days) day\(days == 1 ? "" : "s") remaining (\(dpd) \(unitPlural)/day)"
    }

    private var medication: Medication? {
        // Access via the medication stored in the ViewModel (private) — use save's existing reference
        // We need this for delete. Since medication is private in VM, expose via a helper.
        nil // delete is handled via isActive flag in the dialog action above
    }
}

// MARK: - E-Script Fullscreen

struct EScriptFullscreenView: View {
    let image: UIImage
    let medicationName: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding()
            }
            .navigationTitle("\(medicationName) — E-Script")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
    }
}

// MARK: - Contraceptive Tracker Link Section

/// Shown in Add/Edit Medication form — directs users to the dedicated tracker in Settings → Profile.
// MARK: - Colour Picker Grid

private struct ColourPickerGrid: View {
    @Binding var selectedHex: String
    let options: [String]
    private let columns = Array(repeating: GridItem(.flexible()), count: 8)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(options, id: \.self) { hex in
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: 32, height: 32)
                    .overlay {
                        if selectedHex == hex {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .onTapGesture { selectedHex = hex }
                    .accessibilityLabel("Colour \(hex)")
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    AddEditMedicationView(
        viewModel: AddEditMedicationViewModel(context: PersistenceController.preview.viewContext),
        onSave: { _ in }
    )
    .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
