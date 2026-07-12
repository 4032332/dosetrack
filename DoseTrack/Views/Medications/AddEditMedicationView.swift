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
    @State private var showingPhotoSourcePicker = false
    @State private var showingPhotoCamera = false
    @State private var showingPhotoLibrary = false
    @State private var escriptToCrop: CropItem?
    @State private var showingScanner = false
    @State private var showingScanPaywall = false
    /// True once this add session was populated from a scan — used to count the scan against the
    /// free-tier allowance only if the medication is actually saved.
    @State private var cameFromScan = false
    @ObservedObject private var scanUsage = ScanUsageManager.shared

    /// Entry-point subtitle: entitled users just see the feature blurb; free users see how many of
    /// their 3 lifetime scans remain, or a Plus prompt once they're spent.
    private var scanShortcutSubtitle: String {
        if SubscriptionManager.shared.isProSubscriber
            || CaregiverManager.shared.ownPatientRelationship?.isActive == true {
            return "Auto-fill name and strength from the label"
        }
        let left = scanUsage.freeScansRemaining
        if left > 0 {
            return "\(left) free scan\(left == 1 ? "" : "s") left, then DoseTrack Plus"
        }
        return "DoseTrack Plus feature — tap to upgrade"
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Scan shortcut
                if !viewModel.isEditing {
                    Section {
                        Button {
                            if scanUsage.canScan() {
                                showingScanner = true
                            } else {
                                showingScanPaywall = true
                            }
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
                                    Text(scanShortcutSubtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                // Lock when the free allowance is spent (tap opens the paywall).
                                Image(systemName: scanUsage.canScan() ? "chevron.right" : "lock.fill")
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
                        // A wide, right-aligned tap area: tapping anywhere between the label and
                        // the unit picker focuses the field, and focusing selects all so backspace
                        // clears and typing overwrites (see SelectAllTextField).
                        SelectAllTextField(text: $viewModel.doseAmount, placeholder: "0")
                            .frame(maxWidth: .infinity)
                            .frame(height: 24)
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
                    GuidedScheduleView(
                        schedules: $viewModel.schedules,
                        medicationName: viewModel.name.isEmpty ? "this medication" : viewModel.name,
                        doseDescription: viewModel.doseAmount.isEmpty ? "a dose" : "\(viewModel.doseAmount)\(viewModel.doseUnit)",
                        isEditingExistingMedication: viewModel.isEditing
                    )
                }

                // MARK: Refill tracking
                Section {
                    SupplyWheelPicker(
                        value: $viewModel.currentCount,
                        unit: viewModel.quantityUnit
                    )
                    // Daily consumption = quantity per dose × how many times a day the schedule
                    // fires — not just `quantityAmount` on its own, which is only the per-dose
                    // amount (e.g. "1 tablet") and ignores a 4-times-daily schedule entirely.
                    let dosesPerDay = max(viewModel.schedules.filter { $0.isEnabled }.count, 1)
                    let dpd = max(viewModel.quantityAmount * dosesPerDay, 1)
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
                    Task { @MainActor in
                        if let data = try? await item?.loadTransferable(type: Data.self),
                           let img = UIImage(data: data) {
                            escriptToCrop = CropItem(image: img)   // route through the crop step
                        }
                    }
                }

                // MARK: Reference Photo
                Section {
                    let currentPhotoData = viewModel.photoData
                    Button {
                        showingPhotoSourcePicker = true
                    } label: {
                        HStack {
                            if let data = currentPhotoData, let img = UIImage(data: data) {
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
                            Text(currentPhotoData == nil ? "Add a photo" : "Change photo")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    if viewModel.photoData != nil {
                        Button("Remove Photo", role: .destructive) {
                            viewModel.photoData = nil; photoPickerItem = nil
                        }
                    }
                } header: {
                    Text("Reference Photo (optional)")
                } footer: {
                    Text("Add a photo of the pills, the box, or the bottle for easy identification.")
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
                            // Count a scanner-originated add against the free allowance only now
                            // that it's actually saved (cancelling a scan never costs a scan).
                            if cameFromScan { scanUsage.recordScanSaved() }
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
                // Deferred to the next run loop turn — presenting a sheet in the same turn
                // as this dialog's dismissal can be silently dropped by SwiftUI (see the
                // matching fix/comment in RestockView).
                Button("Take Photo") { DispatchQueue.main.async { showingEscriptCamera = true } }
                Button("Choose from Photo Library") { DispatchQueue.main.async { showingEscriptLibrary = true } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Save your QR code to show at the pharmacy.")
            }
            .photosPicker(isPresented: $showingEscriptLibrary, selection: $escriptPickerItem, matching: .images)
            .sheet(isPresented: $showingScanner) {
                MedicationScannerView(
                    onResult: { result in
                        if !result.name.isEmpty { viewModel.name = result.name }
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
                        // Units taken per dose, reasoned from the box's dosing instructions
                        // ("take 2 tablets" → 2). Only overwrite the form's default when the
                        // scanner actually found it.
                        if result.perDose > 0 {
                            viewModel.quantityAmount = result.perDose
                        }
                        cameFromScan = true
                        showingScanner = false
                    },
                    onCancel: { showingScanner = false }
                )
            }
            .sheet(isPresented: $showingScanPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $showingEscriptCamera) {
                RestockCameraPickerView(
                    onCapture: { image in
                        showingEscriptCamera = false
                        escriptToCrop = CropItem(image: image)   // route through the crop step
                    },
                    onCancel: { showingEscriptCamera = false }
                )
            }
            // E-Scripts are added as full screenshots — offer a crop step so the user can trim to
            // just the QR code and relevant text (or keep the whole thing).
            .fullScreenCover(item: $escriptToCrop) { img in
                ImageCropView(
                    image: img.image,
                    onConfirm: { cropped in
                        viewModel.escriptData = cropped.jpegData(compressionQuality: 0.85)
                        escriptToCrop = nil
                    },
                    onCancel: { escriptToCrop = nil }
                )
            }
            // Reference photo: same "Take Photo / Choose from Library" chooser as the E-Script.
            .confirmationDialog("Add a Photo", isPresented: $showingPhotoSourcePicker) {
                Button("Take Photo") { DispatchQueue.main.async { showingPhotoCamera = true } }
                Button("Choose from Photo Library") { DispatchQueue.main.async { showingPhotoLibrary = true } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Add a photo of the pills, box, or bottle for easy identification.")
            }
            .photosPicker(isPresented: $showingPhotoLibrary, selection: $photoPickerItem, matching: .images)
            .onChange(of: photoPickerItem) { _, item in
                Task { @MainActor in
                    if let data = try? await item?.loadTransferable(type: Data.self) {
                        viewModel.photoData = data
                    }
                }
            }
            .sheet(isPresented: $showingPhotoCamera) {
                RestockCameraPickerView(
                    onCapture: { image in
                        viewModel.photoData = image.jpegData(compressionQuality: 0.85)
                        showingPhotoCamera = false
                    },
                    onCancel: { showingPhotoCamera = false }
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

    /// The user's screen brightness before we forced it to max — restored on dismiss. Captured in
    /// `onAppear` (not as a default) so we always restore the value that was actually in effect.
    @State private var previousBrightness: CGFloat = UIScreen.main.brightness

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
        // Crank the screen to full brightness so a pharmacy scanner can read the QR reliably, then
        // put it back exactly as it was when the viewer closes.
        .onAppear {
            previousBrightness = UIScreen.main.brightness
            UIScreen.main.brightness = 1.0
        }
        .onDisappear {
            UIScreen.main.brightness = previousBrightness
        }
    }
}

// MARK: - Contraceptive Tracker Link Section

/// Shown in Add/Edit Medication form — directs users to the dedicated tracker in Settings → Profile.
// MARK: - Colour Picker Grid

private struct ColourPickerGrid: View {
    @Binding var selectedHex: String
    let options: [String]
    // Loaded once per appearance of the form rather than kept live — the palette/tags aren't
    // expected to change while this sheet is open, and re-reading UserDefaults on every render
    // would be wasteful for something that only matters when the Colour Coding screen is edited.
    @State private var tagStore = ColorTagStore.load()

    /// Colours the user has tagged (Settings > Colour Coding) first, in the order they were
    /// assigned, then any remaining untagged palette colours in their normal order. Assigned
    /// colours were deliberately chosen for a reason, so they should be the easiest to find
    /// rather than scattered wherever they happen to fall in the raw palette.
    private var orderedOptions: [String] {
        let assignedHexes = tagStore.tags.map { $0.colorHex }
        let assigned = assignedHexes.filter { hex in options.contains { $0.caseInsensitiveCompare(hex) == .orderedSame } }
        let unassigned = options.filter { hex in !assignedHexes.contains { $0.caseInsensitiveCompare(hex) == .orderedSame } }
        return assigned + unassigned
    }

    var body: some View {
        // Horizontally scrolling rather than a fixed grid — the palette (see
        // Constants.MedicationColors.palette) is meant to keep growing, and a fixed 8-column
        // grid had no room for more colours without shrinking every swatch.
        ScrollView(.horizontal, showsIndicators: false) {
            // `.top` alignment + a fixed-height label row under every swatch (not just tagged
            // ones) so circles all sit on the same baseline — mixing swatches with and without a
            // tag label under a default-centered HStack shifted circles to different heights,
            // which read as visually uneven.
            HStack(alignment: .top, spacing: 14) {
                ForEach(orderedOptions, id: \.self) { hex in
                    VStack(spacing: 4) {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 36, height: 36)
                            .overlay {
                                if selectedHex == hex {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .overlay {
                                Circle().stroke(Color.primary.opacity(selectedHex == hex ? 0.25 : 0), lineWidth: 2)
                                    .padding(-3)
                            }
                            .onTapGesture { selectedHex = hex }
                            .accessibilityLabel(tagStore.name(forHex: hex).map { "Colour \($0)" } ?? "Colour \(hex)")

                        // Shows the user's own Colour Coding tag (Settings > Preferences), if
                        // they've assigned one, so the picker itself reflects their scheme.
                        // Reserves the same height whether or not a tag exists (see above).
                        Text(tagStore.name(forHex: hex) ?? "")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(width: 48, height: 22)
                    }
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
        }
    }
}

#Preview {
    AddEditMedicationView(
        viewModel: AddEditMedicationViewModel(context: PersistenceController.preview.viewContext),
        onSave: { _ in }
    )
    .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
