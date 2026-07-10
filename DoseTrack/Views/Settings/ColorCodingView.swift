// DoseTrack/Views/Settings/ColorCodingView.swift
import SwiftUI

/// Settings → Preferences → Colour Coding. Lets the user attach a personal label to each
/// colour in the medication colour palette — e.g. all their morning pills one colour tagged
/// "Morning Batch", vitamins a different colour tagged "Vitamin". Purely a legend: assigning a
/// tag here doesn't move or change any medication, it just names the swatches shown in the
/// Add/Edit Medication colour picker so the user's own scheme is easy to remember and reuse.
struct ColorCodingView: View {
    @State private var store: ColorTagStore = ColorTagStore.load()
    @State private var editingHex: String? = nil

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        List {
            Section {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(Constants.MedicationColors.palette, id: \.self) { hex in
                        ColorTagSwatch(hex: hex, tagName: store.name(forHex: hex)) {
                            editingHex = hex
                        }
                    }
                }
                .padding(.vertical, 8)
            } footer: {
                Text("Tap a colour to give it a meaning — for example, tag one colour \"Morning Batch\" and another \"Night Batch\", or split by Medication / Vitamin / Supplement. This is just a personal legend; it doesn't change how any medication works.")
                    .font(.caption)
            }

            if !store.tags.isEmpty {
                Section("Your Tags") {
                    ForEach(store.tags) { tag in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color(hex: tag.colorHex))
                                .frame(width: 20, height: 20)
                            Text(tag.name)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { editingHex = tag.colorHex }
                    }
                    .onDelete { offsets in
                        store.tags.remove(atOffsets: offsets)
                        store.save()
                    }
                }
            }
        }
        .navigationTitle("Colour Coding")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingHex.mappedToIdentifiableHex()) { wrapped in
            ColorTagEditSheet(
                hex: wrapped.value,
                currentName: store.name(forHex: wrapped.value),
                onSave: { name in
                    setTag(name, forHex: wrapped.value)
                },
                onClear: {
                    store.tags.removeAll { $0.colorHex.caseInsensitiveCompare(wrapped.value) == .orderedSame }
                    store.save()
                }
            )
        }
    }

    private func setTag(_ name: String, forHex hex: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if let idx = store.tags.firstIndex(where: { $0.colorHex.caseInsensitiveCompare(hex) == .orderedSame }) {
            store.tags[idx].name = trimmed
        } else {
            store.tags.append(ColorTag(colorHex: hex, name: trimmed))
        }
        store.save()
    }
}

private struct ColorTagSwatch: View {
    let hex: String
    let tagName: String?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: 40, height: 40)
                    .overlay {
                        if tagName == nil {
                            Image(systemName: "plus")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                Text(tagName ?? "Untagged")
                    .font(.caption2)
                    .foregroundStyle(tagName == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ColorTagEditSheet: View {
    let hex: String
    let currentName: String?
    let onSave: (String) -> Void
    let onClear: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Circle().fill(Color(hex: hex)).frame(width: 28, height: 28)
                        TextField("Tag name", text: $name)
                    }
                }
                Section("Suggestions") {
                    // A simple wrapping flow of quick-pick chips for the common categories the
                    // user asked for, plus room to type anything custom in the field above.
                    FlowChips(options: ColorTagStore.suggestedNames, selected: name) { picked in
                        name = picked
                    }
                }
            }
            .navigationTitle("Tag This Colour")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(name)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if currentName != nil {
                    ToolbarItem(placement: .bottomBar) {
                        Button("Remove Tag", role: .destructive) {
                            onClear()
                            dismiss()
                        }
                    }
                }
            }
            .onAppear { name = currentName ?? "" }
        }
    }
}

/// Simple wrapping chip layout for suggested tag names — add a custom one via the text field.
private struct FlowChips: View {
    let options: [String]
    let selected: String
    let onPick: (String) -> Void

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(options, id: \.self) { option in
                Button(option) { onPick(option) }
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        option == selected ? Color.accentColor : Color.secondary.opacity(0.15),
                        in: Capsule()
                    )
                    .foregroundStyle(option == selected ? .white : .primary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - String? -> Identifiable helper for .sheet(item:)

private struct IdentifiableHex: Identifiable {
    let value: String
    var id: String { value }
}

private extension Binding where Value == String? {
    func mappedToIdentifiableHex() -> Binding<IdentifiableHex?> {
        Binding<IdentifiableHex?>(
            get: { self.wrappedValue.map(IdentifiableHex.init) },
            set: { self.wrappedValue = $0?.value }
        )
    }
}

#Preview {
    NavigationStack { ColorCodingView() }
}
