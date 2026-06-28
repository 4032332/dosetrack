// DoseTrack/Views/Medications/AddEditMedicationView.swift
import SwiftUI
import PhotosUI

struct AddEditMedicationView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: AddEditMedicationViewModel
    let onSave: (Medication) -> Void

    @State private var photoPickerItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Form {
                // Basic info
                Section("Medication") {
                    TextField("Name (e.g. Metformin)", text: $viewModel.name)
                        .autocorrectionDisabled()
                    if let err = viewModel.nameError {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }

                    HStack {
                        TextField("Dose (e.g. 500)", text: $viewModel.dosage)
                            .keyboardType(.decimalPad)
                        Picker("Unit", selection: $viewModel.unit) {
                            ForEach(AddEditMedicationViewModel.unitOptions, id: \.self) {
                                Text($0).tag($0)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    if let err = viewModel.dosageError {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                }

                // Colour picker
                Section("Colour") {
                    ColourPickerGrid(
                        selectedHex: $viewModel.colorHex,
                        options: AddEditMedicationViewModel.colorOptions
                    )
                }

                // Schedules
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

                // Refill tracking
                Section("Refill Tracking") {
                    Stepper(
                        "Current supply: \(viewModel.currentCount)",
                        value: $viewModel.currentCount,
                        in: 0...9999
                    )
                    Stepper(
                        "Alert when below: \(viewModel.refillThreshold)",
                        value: $viewModel.refillThreshold,
                        in: 1...999
                    )
                }

                // Photo
                Section("Photo (optional)") {
                    PhotosPicker(selection: $photoPickerItem, matching: .images) {
                        HStack {
                            if let data = viewModel.photoData, let img = UIImage(data: data) {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 60, height: 60)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            } else {
                                Image(systemName: "camera.fill")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 60, height: 60)
                                    .background(Color.secondary.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            Text(viewModel.photoData == nil ? "Add bottle photo" : "Change photo")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .onChange(of: photoPickerItem) { _, item in
                        Task {
                            viewModel.photoData = try? await item?.loadTransferable(type: Data.self)
                        }
                    }

                    if viewModel.photoData != nil {
                        Button("Remove Photo", role: .destructive) {
                            viewModel.photoData = nil
                            photoPickerItem = nil
                        }
                    }
                }

                // Notes
                Section("Notes") {
                    TextField("Optional notes", text: $viewModel.notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                // Disclaimer
                Section {
                    Text("DoseTrack is a reminder tool, not medical advice. Always follow your healthcare provider's instructions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
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
        }
    }
}

private struct ColourPickerGrid: View {
    @Binding var selectedHex: String
    let options: [String]

    private let columns = Array(repeating: GridItem(.flexible()), count: 8)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(options, id: \.self) { hex in
                colorCircle(hex: hex)
            }
        }
        .padding(.vertical, 4)
    }

    private func colorCircle(hex: String) -> some View {
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

#Preview {
    AddEditMedicationView(
        viewModel: AddEditMedicationViewModel(
            context: PersistenceController.preview.viewContext
        ),
        onSave: { _ in }
    )
}
