// DoseTrack/Views/Restock/RestockView.swift
import SwiftUI
import CoreData
import PhotosUI

struct RestockView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var caregiverManager: CaregiverManager
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Medication.currentCount, ascending: true)],
        predicate: NSPredicate(format: "isActive == YES"),
        animation: .default
    ) private var medications: FetchedResults<Medication>

    @State private var medicationToEdit: Medication?
    @State private var showingEscript: (medication: Medication, image: UIImage)? = nil
    @State private var escriptUploadTarget: Medication? = nil
    @State private var escriptPhotoItem: PhotosPickerItem? = nil
    @State private var showingEscriptUpload = false
    @State private var showingCameraPicker = false
    @State private var escriptToCrop: CropItem? = nil
    @Binding var showingAccountSwitcher: Bool

    init(showingAccountSwitcher: Binding<Bool> = .constant(false)) {
        self._showingAccountSwitcher = showingAccountSwitcher
    }

    private var sorted: [Medication] {
        medications.sorted { a, b in
            urgencyRank(a) < urgencyRank(b)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if medications.isEmpty {
                    emptyState
                } else {
                    List {
                        // Legend
                        Section {
                            LegendRow()
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())

                        // Medications sorted by urgency
                        Section {
                            ForEach(sorted) { med in
                                RestockRow(med: med) {
                                    if let data = med.escriptData, let img = UIImage(data: data) {
                                        showingEscript = (med, img)
                                    } else {
                                        escriptUploadTarget = med
                                        showingEscriptUpload = true
                                    }
                                }
                            }
                        }
                    }
                    .scrollIndicators(.visible)
                    .contentMargins(.bottom, 32, for: .scrollContent)
                    .refreshable { await refresh() }
                }
            }
            .navigationTitle("Restock")
            .toolbar {
                if !caregiverManager.overseenPatients.isEmpty {
                    ToolbarItem(placement: .principal) {
                        AccountSwitcherPill(isPresented: $showingAccountSwitcher)
                    }
                }
                // Leading, matching the Edit button's placement on the Medications list — it
                // was on the trailing side here and leading there, which looked inconsistent.
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
            }
            // E-Script viewer
            .sheet(isPresented: Binding(
                get: { showingEscript != nil },
                set: { if !$0 { showingEscript = nil } }
            )) {
                if let item = showingEscript {
                    EScriptFullscreenView(image: item.image, medicationName: item.medication.wrappedName)
                }
            }
            // E-Script upload prompt (no script saved)
            .confirmationDialog(
                "Upload E-Script for \(escriptUploadTarget?.wrappedName ?? "Medication")",
                isPresented: $showingEscriptUpload,
                titleVisibility: .visible
            ) {
                PhotosPicker(selection: $escriptPhotoItem, matching: .images) {
                    Label("Choose from Photo Library", systemImage: "photo.on.rectangle")
                }
                Button("Take Photo with Camera") {
                    // Presenting a new sheet in the same run-loop turn as this
                    // confirmationDialog dismisses can be silently dropped by SwiftUI — the
                    // dialog animates away and the camera sheet just never appears, which
                    // looked exactly like "the button does nothing." Deferring to the next
                    // run loop turn lets the dialog's dismissal complete first.
                    DispatchQueue.main.async {
                        showingCameraPicker = true
                    }
                }
                Button("Cancel", role: .cancel) {
                    escriptUploadTarget = nil
                }
            } message: {
                Text("Save your QR code script so you can show it at the pharmacy.")
            }
            // Photo library picker → crop step (keeps escriptUploadTarget until crop confirms).
            .onChange(of: escriptPhotoItem) { _, newItem in
                guard escriptUploadTarget != nil, let item = newItem else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        escriptToCrop = CropItem(image: img)
                    }
                    escriptPhotoItem = nil
                }
            }
            // Camera picker → crop step
            .sheet(isPresented: $showingCameraPicker) {
                if escriptUploadTarget != nil {
                    RestockCameraPickerView(
                        onCapture: { image in
                            showingCameraPicker = false
                            escriptToCrop = CropItem(image: image)
                        },
                        onCancel: {
                            showingCameraPicker = false
                            escriptUploadTarget = nil
                        }
                    )
                }
            }
            // Crop the uploaded E-Script screenshot before saving it to the target medication.
            .fullScreenCover(item: $escriptToCrop) { item in
                ImageCropView(
                    image: item.image,
                    onConfirm: { cropped in
                        if let target = escriptUploadTarget, let data = cropped.jpegData(compressionQuality: 0.85) {
                            target.escriptData = data
                            try? context.save()
                        }
                        escriptToCrop = nil
                        escriptUploadTarget = nil
                    },
                    onCancel: { escriptToCrop = nil; escriptUploadTarget = nil }
                )
            }
            // Edit medication sheet
            .sheet(item: $medicationToEdit) { med in
                AddEditMedicationView(
                    viewModel: AddEditMedicationViewModel(context: context, medication: med),
                    onSave: { _ in medicationToEdit = nil }
                )
                .environment(\.managedObjectContext, context)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "cart.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary.opacity(0.5))
            Text("No Medications Added")
                .font(.title2.weight(.semibold))
            Text("Add medications to track your supply levels here.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private func refresh() async {
        await SupabaseSyncManager.shared.pullAll(context: context)
        context.refreshAllObjects()
    }

    private func urgencyRank(_ med: Medication) -> Int {
        if med.currentCount < 3 { return 0 }
        if med.daysOfSupply < 5  { return 1 }
        if med.daysOfSupply < 7  { return 2 }
        return 3
    }
}

// MARK: - Restock Row

private struct RestockRow: View {
    @ObservedObject var med: Medication
    let onTap: () -> Void
    @AppStorage("compactRows") private var compactRows: Bool = false

    var body: some View {
        Button(action: onTap) {
            Group {
                if compactRows { compactBody } else { fullBody }
            }
        }
        .foregroundStyle(.primary)
    }

    private var fullBody: some View {
        HStack(spacing: 14) {
            // Shared tinted tile (identical to the Medications list) + a supply-urgency dot,
            // which is meaningful specifically on this restock-focused screen.
            MedicationColorTile(medication: med)
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(med.restockColor)
                        .frame(width: 12, height: 12)
                        .offset(x: 3, y: 3)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(med.wrappedName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text("\(med.wrappedDosage) · \(med.wrappedUnit)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                supplyLabel
                if med.escriptData != nil {
                    Label("E-Script", systemImage: "qrcode")
                        .font(.caption2)
                        .foregroundStyle(.purple)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // ~Half height: slim colour bar (tinted by supply urgency, which is the meaningful signal on
    // this screen) replaces the tile; name inline; a compact supply label + E-Script glyph trail.
    private var compactBody: some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(med.restockColor)
                .frame(width: 4, height: 22)

            Text(med.wrappedName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 6)

            if med.escriptData != nil {
                Image(systemName: "qrcode")
                    .font(.caption2)
                    .foregroundStyle(.purple)
            }
            supplyLabelCompact
        }
        .padding(.vertical, 2)
    }

    // Single-line supply summary for compact mode (the full row stacks days + doses on two lines).
    @ViewBuilder
    private var supplyLabelCompact: some View {
        let count = Int(med.currentCount)
        if count == 0 {
            Text("No supply")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
        } else if count < 3 {
            Text("\(count) left")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
        } else {
            let days = med.daysOfSupply
            Text("\(days)d left")
                .font(.caption.weight(.semibold))
                .foregroundStyle(med.restockColor == .yellow ? Color.orange : med.restockColor)
        }
    }

    @ViewBuilder
    private var supplyLabel: some View {
        let count = Int(med.currentCount)
        if count == 0 {
            Text("No supply")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
        } else if count < 3 {
            Text("\(count) dose\(count == 1 ? "" : "s") left")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
        } else {
            let days = med.daysOfSupply
            Text("\(days) day\(days == 1 ? "" : "s") left")
                .font(.caption.weight(.semibold))
                .foregroundStyle(med.restockColor == .yellow ? Color.orange : med.restockColor)
            Text("\(count) doses")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

}

// MARK: - Legend

private struct LegendRow: View {
    var body: some View {
        HStack(spacing: 16) {
            LegendItem(color: .red,    label: "< 3 doses")
            LegendItem(color: .orange, label: "< 5 days")
            LegendItem(color: .yellow, label: "< 7 days")
            LegendItem(color: .green,  label: "7+ days")
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

private struct LegendItem: View {
    let color: Color
    let label: String
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Camera Picker

struct RestockCameraPickerView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture, onCancel: onCancel) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        let onCancel: () -> Void
        init(onCapture: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture; self.onCancel = onCancel
        }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { onCapture(img) }
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onCancel() }
    }
}

#Preview {
    RestockView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
        .environmentObject(CaregiverManager.shared)
}
