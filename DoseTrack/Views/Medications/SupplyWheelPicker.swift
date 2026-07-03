// DoseTrack/Views/Medications/SupplyWheelPicker.swift
import SwiftUI

struct SupplyWheelPicker: View {
    @Binding var value: Int
    let unit: String

    private let maxValue = 999
    private let itemWidth: CGFloat = 60
    @State private var scrollPosition: Int?
    @State private var showingManualEntry = false
    @State private var manualText = ""

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Label("Current supply", systemImage: "cross.case.fill")
                    .font(.subheadline)
                Spacer()
                Text("\(value) \(unit)\(value == 1 ? "" : "s")")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }

            GeometryReader { geo in
                let padding = (geo.size.width - itemWidth) / 2

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(0...maxValue, id: \.self) { n in
                            NumberCell(n: n, selected: n == value, itemWidth: itemWidth)
                                .id(n)
                                .onTapGesture {
                                    if n == value {
                                        // Tap the already-selected (centre) cell → open numpad
                                        manualText = "\(value)"
                                        showingManualEntry = true
                                    } else {
                                        withAnimation(.spring(response: 0.25)) {
                                            value = n
                                            scrollPosition = n
                                        }
                                    }
                                }
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, padding)
                }
                .scrollPosition(id: $scrollPosition, anchor: .center)
                .scrollTargetBehavior(.viewAligned)
                .onChange(of: scrollPosition) { _, newPos in
                    if let pos = newPos { value = pos }
                }
                .onAppear {
                    scrollPosition = value
                }
            }
            .frame(height: 56)
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentColor, lineWidth: 2)
                    .frame(width: itemWidth, height: 46)
                    .allowsHitTesting(false)
            }

            Text("Tap the highlighted number to type a value")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .alert("Enter quantity", isPresented: $showingManualEntry) {
            TextField("e.g. 100", text: $manualText)
                .keyboardType(.numberPad)
            Button("Set") {
                if let n = Int(manualText), n >= 0, n <= maxValue {
                    value = n
                    scrollPosition = n
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("How many \(unit)s do you have?")
        }
    }
}

private struct NumberCell: View {
    let n: Int
    let selected: Bool
    let itemWidth: CGFloat

    var body: some View {
        Text("\(n)")
            .font(.system(size: selected ? 20 : 15, weight: selected ? .bold : .regular, design: .rounded))
            .foregroundStyle(selected ? Color.accentColor : .secondary)
            .frame(width: itemWidth, height: 56)
            .contentShape(Rectangle())
            .scaleEffect(selected ? 1.15 : 1.0)
            .animation(.spring(response: 0.2), value: selected)
    }
}

#Preview {
    Form {
        SupplyWheelPicker(value: .constant(28), unit: "tablet")
    }
}
