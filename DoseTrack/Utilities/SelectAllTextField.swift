// DoseTrack/Utilities/SelectAllTextField.swift
import SwiftUI
import UIKit

/// A numeric text field that selects its entire contents the moment it gains focus.
///
/// Fixes two complaints with the plain SwiftUI TextField used for dose entry: (1) tapping a
/// field that already held a value planted the caret at the far left, so backspace appeared to
/// do nothing; and (2) the tap target was tiny. Selecting all on focus means one backspace
/// clears the value and typing overwrites it — the expected behaviour for a short numeric field —
/// and the view stretches to fill the space it's given so the whole area is tappable.
struct SelectAllTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var keyboardType: UIKeyboardType = .decimalPad
    var textAlignment: NSTextAlignment = .right

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.keyboardType = keyboardType
        field.textAlignment = textAlignment
        field.placeholder = placeholder
        field.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        // Don't let the field get squeezed to nothing or balloon; it fills the width it's given.
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text { uiView.text = text }
        uiView.keyboardType = keyboardType
        uiView.textAlignment = textAlignment
        uiView.placeholder = placeholder
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        private let text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        @objc func editingChanged(_ sender: UITextField) {
            text.wrappedValue = sender.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            // Defer to the next runloop turn — selecting immediately inside didBeginEditing is
            // unreliable while the field is still installing its editing state.
            DispatchQueue.main.async { textField.selectAll(nil) }
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}
