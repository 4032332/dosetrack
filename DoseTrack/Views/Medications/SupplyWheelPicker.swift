// DoseTrack/Views/Medications/SupplyWheelPicker.swift
import SwiftUI

/// Current-supply input for refill tracking. A prior scrolling-wheel design had a
/// persistent visual bug (the highlighted number never lined up with the selection
/// box), so this is a plain stepper with a large tappable number that opens a numpad
/// for direct entry — simpler and more reliable than a custom scroll-snapping picker.
struct SupplyWheelPicker: View {
    @Binding var value: Int
    let unit: String

    private let maxValue = 999
    @State private var showingManualEntry = false
    @State private var manualText = ""

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Label("Current supply", systemImage: "cross.case.fill")
                    .font(.subheadline)
                Spacer()
                Text("\(value) \(unit)\(value == 1 ? "" : "s")")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }

            HStack(spacing: 20) {
                Button {
                    if value > 0 { value -= 1 }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 30))
                }
                .buttonStyle(.plain)
                .disabled(value <= 0)

                Button {
                    // Blank, not pre-filled with the current value — pre-filling forced the
                    // user to backspace before typing a new number, adding friction to what's
                    // meant to be a quick "type the number" entry point.
                    manualText = ""
                    showingManualEntry = true
                } label: {
                    Text("\(value)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                        .frame(minWidth: 90)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                Button {
                    if value < maxValue { value += 1 }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 30))
                }
                .buttonStyle(.plain)
                .disabled(value >= maxValue)
            }
            .frame(maxWidth: .infinity)

            Text("Tap the number to type a value")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .alert("Enter quantity", isPresented: $showingManualEntry) {
            TextField("e.g. 100", text: $manualText)
                .keyboardType(.numberPad)
            Button("Set") {
                if let n = Int(manualText), n >= 0, n <= maxValue {
                    value = n
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("How many \(unit)s do you have?")
        }
    }
}

#Preview {
    Form {
        SupplyWheelPicker(value: .constant(28), unit: "tablet")
    }
}
