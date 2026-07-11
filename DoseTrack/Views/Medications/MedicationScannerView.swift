// DoseTrack/Views/Medications/MedicationScannerView.swift
// Live medication-box scanner. Uses VisionKit's DataScannerViewController for continuous on-feed
// text recognition — the text it reads is highlighted live over the camera image and labelled by
// which field it matched (Name / Strength / Supply / Dose). MedicationParser turns the recognised
// text into a structured result (name, strength, supply quantity, form, and units-per-dose reasoned
// from any dosing instructions), which is written straight into the Add Medication form.
//
// DataScannerViewController requires a physical device (A12 Bionic or newer) and isn't available on
// the Simulator, so `PhotoScanFallbackView` provides a single-photo capture path for those cases.

import SwiftUI
import UIKit
import VisionKit

// MARK: - Entry point (chooses live scanner vs. photo fallback)

struct MedicationScannerView: View {
    let onResult: (MedicationScanResult) -> Void
    let onCancel: () -> Void

    private var liveScanningAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        NavigationStack {
            Group {
                if liveScanningAvailable {
                    LiveMedicationScannerView(onUse: onResult, onCancel: onCancel)
                } else {
                    PhotoScanFallbackView(onResult: onResult, onCancel: onCancel)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }
}

// MARK: - Live scanner (DataScannerViewController)

private struct LiveMedicationScannerView: View {
    let onUse: (MedicationScanResult) -> Void
    let onCancel: () -> Void

    @StateObject private var model = LiveScanModel()

    var body: some View {
        ZStack(alignment: .bottom) {
            DataScannerRepresentable(model: model)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                instructionBanner
                Spacer()
                capturedCard
            }
        }
        .navigationTitle("Scan Medication")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var instructionBanner: some View {
        Text("Point at the label until the details fill in below. For a round bottle, rotate it slowly to read the whole label.")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(.black.opacity(0.55))
    }

    private var capturedCard: some View {
        let r = model.result
        return VStack(spacing: 12) {
            capturedRow(label: "Name", value: r?.name, found: r?.hasName ?? false)
            capturedRow(label: "Strength",
                        value: (r?.hasStrength ?? false) ? "\(r!.strength)\(r!.strengthUnit)" : nil,
                        found: r?.hasStrength ?? false)
            capturedRow(label: "Supply",
                        value: (r?.hasSupply ?? false) ? "\(r!.count) \(r!.form)s" : nil,
                        found: r?.hasSupply ?? false)
            capturedRow(label: "Per dose",
                        value: (r?.hasPerDose ?? false) ? "\(r!.perDose) \(r!.form)\(r!.perDose == 1 ? "" : "s")" : nil,
                        found: r?.hasPerDose ?? false)

            Button {
                if let r, r.hasName { onUse(r) }
            } label: {
                Text("Use These Details")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!(model.result?.hasName ?? false))

            HStack {
                Button("Rescan") { model.resetAccumulation?() }
                Spacer()
                Button("Enter Manually") {
                    onUse(MedicationScanResult(name: "", strength: "", strengthUnit: "mg",
                                               count: 0, form: "tablet", perDose: 0,
                                               instructions: nil, rawLines: model.result?.rawLines ?? []))
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private func capturedRow(label: String, value: String?, found: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: found ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(found ? Color.green : Color.secondary)
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value ?? "Scanning…")
                .font(.subheadline.weight(found ? .semibold : .regular))
                .foregroundStyle(found ? .primary : .tertiary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

// MARK: - Live scan model (observed by the captured-details card)

@MainActor
final class LiveScanModel: ObservableObject {
    @Published var result: MedicationScanResult? = nil
    /// Set by the DataScanner coordinator; called by the card's "Rescan" button to clear the
    /// accumulated text and start fresh.
    var resetAccumulation: (() -> Void)?
}

// MARK: - DataScanner wrapper + delegate

/// Which extracted field a recognised on-screen text item was matched to — drives the colour and
/// label of its highlight box over the live camera feed.
private enum FieldTag {
    case name, strength, supply, dose

    var title: String {
        switch self {
        case .name: return "Name"
        case .strength: return "Strength"
        case .supply: return "Supply"
        case .dose: return "Dose"
        }
    }

    var color: UIColor {
        switch self {
        case .name: return UIColor(red: 0.36, green: 0.54, blue: 0.94, alpha: 1)   // brand blue
        case .strength: return UIColor(red: 0.65, green: 0.48, blue: 0.98, alpha: 1) // purple
        case .supply: return UIColor.systemOrange
        case .dose: return UIColor.systemGreen
        }
    }
}

private struct DataScannerRepresentable: UIViewControllerRepresentable {
    @ObservedObject var model: LiveScanModel

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .balanced,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: false,
            isHighlightingEnabled: false   // we draw our own field-labelled highlights
        )
        scanner.delegate = context.coordinator
        context.coordinator.scanner = scanner
        model.resetAccumulation = { [weak coordinator = context.coordinator] in coordinator?.reset() }
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let model: LiveScanModel
        weak var scanner: DataScannerViewController?
        private var overlays: [RecognizedItem.ID: UIView] = [:]

        /// Text accumulated across ALL frames this session (see ScanTextAccumulator). This is what
        /// makes a cylindrical bottle work — the wrapped label is never fully visible in one frame,
        /// so the user rotates the bottle and each field is captured once and retained rather than
        /// lost when it scrolls off. Cleared by the card's "Rescan" button.
        private var accumulator = ScanTextAccumulator()

        init(model: LiveScanModel) { self.model = model }

        /// Clears the accumulated text — used when the user taps "Rescan" (e.g. they've aimed at a
        /// different medication and don't want stale text from the last one bleeding in).
        func reset() {
            accumulator.removeAll()
            overlays.values.forEach { $0.removeFromSuperview() }
            overlays.removeAll()
            model.result = nil
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            refresh(with: allItems, in: dataScanner)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            refresh(with: allItems, in: dataScanner)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didRemove removedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in removedItems { overlays.removeValue(forKey: item.id)?.removeFromSuperview() }
            refresh(with: allItems, in: dataScanner)
        }

        /// Fold the currently-visible text into the running accumulation, re-parse the whole
        /// accumulation, and redraw the field-labelled highlight boxes over the visible items.
        private func refresh(with allItems: [RecognizedItem], in dataScanner: DataScannerViewController) {
            let viewHeight = max(dataScanner.view.bounds.height, 1)

            // Text items only, paired with their transcripts and bounds.
            let texts: [(item: RecognizedItem, transcript: String)] = allItems.compactMap { item in
                if case let .text(text) = item { return (item, text.transcript) }
                return nil
            }

            // Accumulate this frame's text (keeps the longest variant + greatest height per line).
            for entry in texts {
                let h = boundingRect(for: entry.item.bounds).height / viewHeight
                accumulator.add(text: entry.transcript, height: h)
            }

            // Parse the full accumulation, not just this frame — the crux of reading a wrapped label.
            let parsed = MedicationParser.parse(lines: accumulator.lines)
            model.result = parsed

            // Highlight whichever CURRENTLY-visible items map to a field (you can only draw a box
            // over text that's on screen right now, even though the parse spans the accumulation).
            var live: Set<RecognizedItem.ID> = []
            for entry in texts {
                guard let tag = tag(for: entry.transcript, parsedName: parsed?.name) else { continue }
                live.insert(entry.item.id)
                let frame = boundingRect(for: entry.item.bounds)
                let box = overlays[entry.item.id] ?? makeOverlay()
                configure(box, frame: frame, tag: tag)
                if box.superview == nil { dataScanner.overlayContainerView.addSubview(box) }
                overlays[entry.item.id] = box
            }
            for (id, view) in overlays where !live.contains(id) {
                view.removeFromSuperview()
                overlays.removeValue(forKey: id)
            }
        }


        private func boundingRect(for bounds: RecognizedItem.Bounds) -> CGRect {
            let xs = [bounds.topLeft.x, bounds.topRight.x, bounds.bottomLeft.x, bounds.bottomRight.x]
            let ys = [bounds.topLeft.y, bounds.topRight.y, bounds.bottomLeft.y, bounds.bottomRight.y]
            let minX = xs.min() ?? 0, maxX = xs.max() ?? 0
            let minY = ys.min() ?? 0, maxY = ys.max() ?? 0
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }

        /// Classify a single recognised line by what it looks like — the name comes from the
        /// global parse (tallest line), the rest are self-evident from the line's own content.
        private func tag(for transcript: String, parsedName: String?) -> FieldTag? {
            let lc = transcript.lowercased()
            if let name = parsedName, !name.isEmpty,
               lc.contains(name.lowercased()) { return .name }
            if MedicationLineClassifier.isInstruction(transcript) { return .dose }
            if MedicationLineClassifier.isSupply(transcript) { return .supply }
            if MedicationLineClassifier.isStrength(transcript) { return .strength }
            return nil
        }

        private func makeOverlay() -> UIView {
            let box = UIView()
            box.backgroundColor = .clear
            box.layer.borderWidth = 2
            box.layer.cornerRadius = 4
            let label = UILabel()
            label.font = .systemFont(ofSize: 11, weight: .bold)
            label.textColor = .white
            label.tag = 99
            box.addSubview(label)
            return box
        }

        private func configure(_ box: UIView, frame: CGRect, tag: FieldTag) {
            box.frame = frame
            box.layer.borderColor = tag.color.cgColor
            box.backgroundColor = tag.color.withAlphaComponent(0.16)
            if let label = box.viewWithTag(99) as? UILabel {
                label.text = " \(tag.title) "
                label.backgroundColor = tag.color
                label.sizeToFit()
                label.frame = CGRect(x: 0, y: -16, width: label.bounds.width + 8, height: 16)
                label.layer.cornerRadius = 3
                label.clipsToBounds = true
                label.textAlignment = .center
            }
        }
    }
}

/// Lightweight, self-contained line classifiers used only for the live highlight labelling (the
/// authoritative extraction is `MedicationParser`; these just answer "does this one line look like
/// a strength / supply / instruction?" for colouring the box).
private enum MedicationLineClassifier {
    static func isStrength(_ line: String) -> Bool {
        line.range(of: #"\d+(\.\d+)?\s*(mg|mcg|microgram|iu|ml|g|%)"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
    static func isSupply(_ line: String) -> Bool {
        line.range(of: #"\b(qty|quantity|pack|contents?)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
            || line.range(of: #"\b\d+\s*('s|tablets?|caps?(ules?)?|capsules?)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
    static func isInstruction(_ line: String) -> Bool {
        line.range(of: #"\b(take|use|apply|swallow|inhale|chew)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
            && line.range(of: #"\b(tablet|capsule|cap|pill|puff|spray|drop|ml)s?\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

// MARK: - Photo fallback (Simulator / devices without live scanning)

/// A single-photo capture + parse path for hardware that can't run DataScannerViewController.
/// Retains a small review step (since there's no live feedback), then hands the result off.
private struct PhotoScanFallbackView: View {
    let onResult: (MedicationScanResult) -> Void
    let onCancel: () -> Void

    @State private var scanResult: MedicationScanResult? = nil
    @State private var rawLinesForFallback: [String]? = nil
    @State private var isProcessing = false
    @State private var showingCamera = true
    @State private var errorMessage: String? = nil

    var body: some View {
        Group {
            if let result = scanResult {
                ScanResultReviewView(result: result, onAccept: onResult, onRetry: retry)
            } else if let lines = rawLinesForFallback {
                RawLinesPickerView(
                    lines: lines,
                    onSelect: { name in
                        scanResult = MedicationScanResult(name: name, strength: "", strengthUnit: "mg",
                                                          count: 0, form: "tablet", perDose: 0,
                                                          instructions: nil, rawLines: lines)
                        rawLinesForFallback = nil
                    },
                    onEnterManually: {
                        scanResult = MedicationScanResult(name: "", strength: "", strengthUnit: "mg",
                                                          count: 0, form: "tablet", perDose: 0,
                                                          instructions: nil, rawLines: lines)
                        rawLinesForFallback = nil
                    },
                    onRetry: retry
                )
            } else if isProcessing {
                VStack(spacing: 24) {
                    ProgressView().scaleEffect(1.5)
                    Text("Reading medication details…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if showingCamera {
                ScannerCameraView(onCapture: { image in showingCamera = false; process(image) },
                                  onCancel: onCancel)
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 48)).foregroundStyle(.orange)
                    Text("Couldn't read the label").font(.title3.weight(.semibold))
                    if let errorMessage {
                        Text(errorMessage).font(.subheadline).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).padding(.horizontal)
                    }
                    Button("Try Again") { retry() }.buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Scan Medication")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func process(_ image: UIImage) {
        isProcessing = true
        errorMessage = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = Result { try MedicationTextRecognizer.recognizeLines(in: image) }
            DispatchQueue.main.async {
                isProcessing = false
                switch outcome {
                case .failure:
                    errorMessage = "Couldn't read this image. Please try again with better lighting."
                case .success(let lines):
                    if let result = MedicationParser.parse(lines: lines) {
                        scanResult = result
                    } else if !lines.isEmpty {
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
        rawLinesForFallback = nil
        errorMessage = nil
        showingCamera = true
    }
}

// MARK: - Raw lines fallback picker

/// Shown (fallback path only) when Vision detected text but the parser couldn't confidently pick a
/// name line — letting the user tap the correct line is more trustworthy than a wrong guess.
private struct RawLinesPickerView: View {
    let lines: [String]
    let onSelect: (String) -> Void
    let onEnterManually: () -> Void
    let onRetry: () -> Void

    var body: some View {
        List {
            Section {
                Text("We couldn't automatically tell which line is the medication name. Tap the correct one below.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("Detected Text") {
                ForEach(lines, id: \.self) { line in
                    Button { onSelect(line) } label: {
                        Text(line).foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
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

// MARK: - Scan result review (fallback path only)

private struct ScanResultReviewView: View {
    let result: MedicationScanResult
    let onAccept: (MedicationScanResult) -> Void
    let onRetry: () -> Void

    @State private var name: String
    @State private var strength: String
    @State private var strengthUnit: String
    @State private var count: String
    @State private var form: String
    @State private var perDose: Int

    private let strengthUnits = ["mg", "mcg", "g", "ml", "mg/ml", "mg/5ml", "%", "IU"]
    private let forms = ["tablet", "capsule", "ml", "injection", "patch", "spray", "inhaler", "drop", "supplement"]

    init(result: MedicationScanResult, onAccept: @escaping (MedicationScanResult) -> Void, onRetry: @escaping () -> Void) {
        self.result = result
        self.onAccept = onAccept
        self.onRetry = onRetry
        _name = State(initialValue: result.name)
        _strength = State(initialValue: result.strength)
        _strengthUnit = State(initialValue: result.strengthUnit)
        _count = State(initialValue: result.count > 0 ? "\(result.count)" : "")
        _form = State(initialValue: result.form)
        _perDose = State(initialValue: max(result.perDose, 1))
    }

    var body: some View {
        Form {
            Section("Medication Name") {
                TextField("Name", text: $name).autocorrectionDisabled()
            }
            Section("Strength") {
                HStack {
                    TextField("Amount", text: $strength).keyboardType(.decimalPad).frame(width: 80)
                    Picker("Unit", selection: $strengthUnit) {
                        ForEach(strengthUnits, id: \.self) { Text($0).tag($0) }
                    }.pickerStyle(.menu)
                }
            }
            Section("Supply in pack") {
                HStack {
                    TextField("Count", text: $count).keyboardType(.numberPad).frame(width: 80)
                    Picker("Form", selection: $form) {
                        ForEach(forms, id: \.self) { Text($0).tag($0) }
                    }.pickerStyle(.menu)
                }
            }
            Section("Per dose") {
                Stepper("\(perDose) \(form)\(perDose == 1 ? "" : "s") per dose", value: $perDose, in: 1...12)
            }
            Section {
                Button("Use These Details") {
                    onAccept(MedicationScanResult(name: name, strength: strength, strengthUnit: strengthUnit,
                                                  count: Int(count) ?? 0, form: form, perDose: perDose,
                                                  instructions: result.instructions, rawLines: result.rawLines))
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

// MARK: - Camera picker (UIImagePickerController, fallback capture)

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
