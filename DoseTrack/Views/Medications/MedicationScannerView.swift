// DoseTrack/Views/Medications/MedicationScannerView.swift
// Camera-based medication box scanner. The user scans the front of a medication box or bottle
// with the system document scanner (edge-detected, deskewed, contrast-enhanced), then
// MedicationTextRecognizer runs Vision OCR (orientation-aware) and MedicationParser pulls out the
// drug name, strength, count, and form. Results pre-fill the Add Medication form for the user to
// review and correct before saving.

import SwiftUI
import UIKit
import VisionKit

// MARK: - Result model

struct MedicationScanResult {
    var name: String
    var strength: String        // e.g. "500"
    var strengthUnit: String    // e.g. "mg"
    var count: Int              // e.g. 30
    var form: String            // e.g. "tablet"
    var rawLines: [String]      // all OCR lines for debugging
}

// MARK: - Main scanner view

struct MedicationScannerView: View {
    let onResult: (MedicationScanResult) -> Void
    let onCancel: () -> Void

    @State private var capturedImage: UIImage? = nil
    @State private var scanResult: MedicationScanResult? = nil
    @State private var isProcessing = false
    @State private var showingCamera = true
    @State private var errorMessage: String? = nil
    /// Set when Vision found text but the heuristic parser couldn't confidently identify a
    /// name line — rather than a dead-end error, the user picks which detected line is the
    /// medication name themselves. Far more reliable than guessing, since real box layouts
    /// vary enormously (marketing taglines, regulatory codes, multiple languages).
    @State private var rawLinesForFallback: [String]? = nil
    /// Identifies the in-flight scan so a stale watchdog/completion from a previous
    /// (already-retried) scan can't clobber the state of a newer one.
    @State private var currentScanToken: UUID? = nil

    var body: some View {
        NavigationStack {
            Group {
                if let result = scanResult {
                    ScanResultReviewView(result: result, onAccept: onResult, onRetry: retry)
                } else if let lines = rawLinesForFallback {
                    RawLinesPickerView(
                        lines: lines,
                        onSelect: { chosenName in
                            scanResult = MedicationScanResult(
                                name: chosenName, strength: "", strengthUnit: "mg",
                                count: 0, form: "tablet", rawLines: lines
                            )
                            rawLinesForFallback = nil
                        },
                        onEnterManually: {
                            scanResult = MedicationScanResult(
                                name: "", strength: "", strengthUnit: "mg",
                                count: 0, form: "tablet", rawLines: lines
                            )
                            rawLinesForFallback = nil
                        },
                        onRetry: retry
                    )
                } else if isProcessing {
                    processingView
                } else if showingCamera {
                    // Prefer the system document scanner: it finds the box edges, corrects the
                    // perspective, and boosts contrast before we ever run OCR — a far cleaner
                    // input than a raw glossy-box snapshot, which is what OCR needs to succeed on
                    // real packaging. Falls back to the photo picker where the document camera
                    // isn't available (notably the Simulator).
                    if DocumentScannerView.isSupported {
                        DocumentScannerView(
                            onCapture: { image in
                                capturedImage = image
                                showingCamera = false
                                processImage(image)
                            },
                            onCancel: onCancel,
                            onError: { message in
                                showingCamera = false
                                errorMessage = message
                            }
                        )
                        .ignoresSafeArea()
                    } else {
                        ScannerCameraView(
                            onCapture: { image in
                                capturedImage = image
                                showingCamera = false
                                processImage(image)
                            },
                            onCancel: onCancel
                        )
                        .ignoresSafeArea()
                    }
                } else {
                    errorView
                }
            }
            .navigationTitle("Scan Medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }

    private var processingView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Reading medication details…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var errorView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Couldn't read the label")
                .font(.title3.weight(.semibold))
            if let msg = errorMessage {
                Text(msg)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            Button("Try Again") { retry() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func processImage(_ image: UIImage) {
        isProcessing = true
        errorMessage = nil
        let scanToken = UUID()
        currentScanToken = scanToken

        // Watchdog: if recognition hasn't finished within 15s (device stall or a huge image),
        // surface an error instead of leaving the spinner stuck forever — that indefinite hang
        // is exactly what earlier looked like "does nothing."
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [self] in
            guard currentScanToken == scanToken, isProcessing else { return }
            isProcessing = false
            errorMessage = "Taking longer than expected. Please try again."
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let outcome: Result<[RecognizedLine], Error>
            do {
                outcome = .success(try MedicationTextRecognizer.recognizeLines(in: image))
            } catch {
                outcome = .failure(error)
            }

            DispatchQueue.main.async {
                guard currentScanToken == scanToken else { return }
                isProcessing = false
                switch outcome {
                case .failure(let error):
                    errorMessage = (error as? LocalizedError)?.errorDescription
                        ?? "Couldn't read this image. Please try again with better lighting."
                case .success(let lines):
                    if let result = MedicationParser.parse(lines: lines) {
                        scanResult = result
                    } else if !lines.isEmpty {
                        // Vision found text but the parser couldn't confidently pick a name
                        // line — let the user pick instead of a dead-end error.
                        rawLinesForFallback = lines.map(\.text)
                    } else {
                        errorMessage = "No text detected. Try pointing the camera at the front of the box or bottle label."
                    }
                }
            }
        }
    }

    private func retry() {
        scanResult = nil
        capturedImage = nil
        errorMessage = nil
        rawLinesForFallback = nil
        showingCamera = true
    }
}

// MARK: - Raw lines fallback picker

/// Shown when Vision detected text but the heuristic parser couldn't confidently identify a
/// name line. Real medication packaging varies too much (marketing taglines, regulatory
/// codes, dosing instructions, multiple languages) for automated guessing to be reliable in
/// every case — letting the user tap the correct line themselves is far more trustworthy than
/// a wrong guess, and only one tap slower than a right one.
private struct RawLinesPickerView: View {
    let lines: [String]
    let onSelect: (String) -> Void
    let onEnterManually: () -> Void
    let onRetry: () -> Void

    var body: some View {
        List {
            Section {
                Text("We couldn't automatically tell which line is the medication name. Tap the correct one below.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Detected Text") {
                ForEach(lines, id: \.self) { line in
                    Button {
                        onSelect(line)
                    } label: {
                        Text(line)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Section {
                Button("None of these — enter manually", action: onEnterManually)
                Button("Retake Photo", action: onRetry)
            }
        }
        .navigationTitle("Select Medication Name")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Scan result review

private struct ScanResultReviewView: View {
    let result: MedicationScanResult
    let onAccept: (MedicationScanResult) -> Void
    let onRetry: () -> Void

    @State private var name: String
    @State private var strength: String
    @State private var strengthUnit: String
    @State private var count: String
    @State private var form: String

    private let strengthUnits = ["mg", "mcg", "g", "ml", "mg/ml", "mg/5ml", "%", "IU"]
    private let forms = ["tablet", "capsule", "liquid", "injection", "patch", "spray", "supplement"]

    init(result: MedicationScanResult, onAccept: @escaping (MedicationScanResult) -> Void, onRetry: @escaping () -> Void) {
        self.result = result
        self.onAccept = onAccept
        self.onRetry = onRetry
        _name = State(initialValue: result.name)
        _strength = State(initialValue: result.strength)
        _strengthUnit = State(initialValue: result.strengthUnit)
        _count = State(initialValue: result.count > 0 ? "\(result.count)" : "")
        _form = State(initialValue: result.form)
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Medication details detected — review and correct if needed")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Medication Name") {
                TextField("Name", text: $name)
                    .autocorrectionDisabled()
            }

            Section("Strength") {
                HStack {
                    TextField("Amount", text: $strength)
                        .keyboardType(.decimalPad)
                        .frame(width: 80)
                    Picker("Unit", selection: $strengthUnit) {
                        ForEach(strengthUnits, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
            }

            Section("Quantity") {
                HStack {
                    TextField("Count", text: $count)
                        .keyboardType(.numberPad)
                        .frame(width: 80)
                    Picker("Form", selection: $form) {
                        ForEach(forms, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
            }

            Section {
                Button("Use These Details") {
                    let finalResult = MedicationScanResult(
                        name: name,
                        strength: strength,
                        strengthUnit: strengthUnit,
                        count: Int(count) ?? 0,
                        form: form,
                        rawLines: result.rawLines
                    )
                    onAccept(finalResult)
                }
                .fontWeight(.semibold)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)

                Button("Scan Again", role: .cancel, action: onRetry)
            }
        }
        .navigationTitle("Confirm Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Camera picker (reuses UIImagePickerController)

struct ScannerCameraView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture, onCancel: onCancel) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        let onCancel: () -> Void

        init(onCapture: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture; self.onCancel = onCancel
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { onCapture(img) }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - Document scanner (VisionKit)

/// Wraps `VNDocumentCameraViewController` — the same edge-detecting, perspective-correcting,
/// contrast-enhancing scanner used by Notes/Files. Its output is a clean, deskewed, high-contrast
/// image of the label, which is dramatically easier for OCR to read than a raw camera photo.
struct DocumentScannerView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void
    let onError: (String) -> Void

    /// False on the Simulator and any device without document-scanning support.
    static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}

    class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScannerView
        init(_ parent: DocumentScannerView) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            // A box front is a single page; take the first scanned page.
            guard scan.pageCount > 0 else {
                parent.onError("No page was scanned. Please try again.")
                return
            }
            let image = scan.imageOfPage(at: 0)
            parent.onCapture(image)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            parent.onError("Scanning failed. Please try again.")
        }
    }
}

#Preview {
    MedicationScannerView(onResult: { _ in }, onCancel: {})
}
