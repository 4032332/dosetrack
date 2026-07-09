// DoseTrack/Views/Medications/MedicationScannerView.swift
// Camera-based medication box scanner using Vision OCR.
// User photographs the front of a medication box or bottle.
// Vision extracts all text, then a parser pulls out drug name, strength, and tablet count.
// Results pre-fill the Add Medication form — user reviews and corrects before saving.

import SwiftUI
import Vision
import AVFoundation

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
                    ScannerCameraView(
                        onCapture: { image in
                            capturedImage = image
                            showingCamera = false
                            processImage(image)
                        },
                        onCancel: onCancel
                    )
                    .ignoresSafeArea()
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

        guard let cgImage = image.cgImage else {
            isProcessing = false
            errorMessage = "Could not process this image."
            return
        }

        // Watchdog: if Vision hasn't called back within 10s (device stall, huge image, or a
        // failure mode neither the completion handler's error path nor the `perform` catch
        // below happens to cover), surface an error instead of leaving the spinner stuck
        // forever — that indefinite hang is exactly what earlier looked like "does nothing."
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [self] in
            guard currentScanToken == scanToken, isProcessing else { return }
            isProcessing = false
            errorMessage = "Taking longer than expected. Please try again."
        }

        let request = VNRecognizeTextRequest { request, error in
            DispatchQueue.main.async {
                guard currentScanToken == scanToken else { return }
                isProcessing = false
                if let error {
                    errorMessage = error.localizedDescription
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                if let result = MedicationParser.parse(lines: lines) {
                    scanResult = result
                } else if !lines.isEmpty {
                    // Vision found text but the parser's heuristics couldn't confidently pick
                    // a name line — let the user pick instead of a dead-end error.
                    rawLinesForFallback = lines
                } else {
                    errorMessage = "No text detected. Try pointing the camera at the front of the box or bottle label."
                }
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                // `perform` throwing (as opposed to the request completion handler reporting
                // an error) never invokes VNRecognizeTextRequest's completion block at all —
                // silently swallowing this with `try?` left the UI stuck on the "Reading
                // medication details…" spinner forever with no feedback, which is exactly
                // what looked like "the photo does nothing."
                DispatchQueue.main.async {
                    guard currentScanToken == scanToken else { return }
                    isProcessing = false
                    errorMessage = "Couldn't read this image. Please try again with better lighting."
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

// MARK: - OCR parser

enum MedicationParser {

    static func parse(lines: [String]) -> MedicationScanResult? {
        guard !lines.isEmpty else { return nil }

        let strength = extractStrength(from: lines)
        let count = extractCount(from: lines)
        let form = extractForm(from: lines)
        let name = extractName(from: lines, excludingStrength: strength?.full)

        // Require at minimum a name to proceed
        guard let name, !name.isEmpty else { return nil }

        return MedicationScanResult(
            name: name,
            strength: strength?.value ?? "",
            strengthUnit: strength?.unit ?? "mg",
            count: count ?? 0,
            form: form ?? "tablet",
            rawLines: lines
        )
    }

    // MARK: - Strength: "500 mg", "10mg", "2.5mg/5mL"

    private struct StrengthMatch {
        let full: String
        let value: String
        let unit: String
    }

    private static let strengthPattern = try! NSRegularExpression(
        pattern: #"(\d+(?:\.\d+)?)\s*(mg\/(?:ml|5ml)|mcg|mg|g|ml|iu|%|mg\/ml)"#,
        options: .caseInsensitive
    )

    private static func extractStrength(from lines: [String]) -> StrengthMatch? {
        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            if let match = strengthPattern.firstMatch(in: line, range: range) {
                let value = (line as NSString).substring(with: match.range(at: 1))
                let unit  = (line as NSString).substring(with: match.range(at: 2)).lowercased()
                let full  = (line as NSString).substring(with: match.range)
                return StrengthMatch(full: full, value: value, unit: unit)
            }
        }
        return nil
    }

    // MARK: - Count: "30 tablets", "28 CAPSULES", "100 tab"

    private static let countPattern = try! NSRegularExpression(
        pattern: #"(\d+)\s*(?:tablets?|caps?(?:ules?)?|caplets?|sachets?|doses?|puffs?|patches?|vials?|ampoules?|injections?|tabs?)"#,
        options: .caseInsensitive
    )

    private static func extractCount(from lines: [String]) -> Int? {
        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            if let match = countPattern.firstMatch(in: line, range: range) {
                let numStr = (line as NSString).substring(with: match.range(at: 1))
                if let n = Int(numStr), n > 0, n <= 1000 { return n }
            }
        }
        return nil
    }

    // MARK: - Form

    private static let formKeywords: [(keyword: String, form: String)] = [
        ("tablet", "tablet"), ("cap", "capsule"), ("liquid", "liquid"),
        ("syrup", "liquid"), ("injection", "injection"), ("patch", "patch"),
        ("spray", "spray"), ("inhaler", "spray"), ("supplement", "supplement"),
        ("softgel", "capsule"), ("sachet", "sachet")
    ]

    private static func extractForm(from lines: [String]) -> String? {
        let joined = lines.joined(separator: " ").lowercased()
        for (keyword, form) in formKeywords {
            if joined.contains(keyword) { return form }
        }
        return nil
    }

    // MARK: - Name: longest title-case line that isn't just numbers/strength

    private static func extractName(from lines: [String], excludingStrength: String?) -> String? {
        // Filter lines: must have letters, not purely numeric, not too short
        let candidates = lines.filter { line in
            let cleaned = line.trimmingCharacters(in: .whitespaces)
            guard cleaned.count >= 4 else { return false }
            guard cleaned.rangeOfCharacter(from: .letters) != nil else { return false }
            // Exclude lines that are predominantly dosage/count info
            if let strength = excludingStrength, cleaned.lowercased().contains(strength.lowercased()) { return false }
            let lc = cleaned.lowercased()
            let skipWords = ["tablets", "capsules", "dose", "directions", "active ingredient",
                             "inactive", "store", "expir", "batch", "lot", "medicine",
                             "pharmacy", "prescrib", "warning", "keep out", "apn", "ean",
                             "australian", "new zealand", "contains", "each", "take",
                             "before", "after", "consult", "doctor", "pharmacist"]
            return !skipWords.contains(where: { lc.contains($0) })
        }

        // Prefer lines that look like a proper noun (start with capital, short-ish)
        let properNoun = candidates.first(where: { line in
            guard let first = line.first else { return false }
            return first.isUppercase && line.count <= 40 && !line.contains("  ")
        })

        return properNoun ?? candidates.first
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

#Preview {
    MedicationScannerView(onResult: { _ in }, onCancel: {})
}
