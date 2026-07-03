// DoseTrack/Views/Settings/AppIconPickerView.swift
// Lets users switch between alternate app icons.
// Each icon requires a corresponding image set in Assets.xcassets
// and an entry under CFBundleIcons → CFBundleAlternateIcons in Info.plist.

import SwiftUI

struct AppIconOption: Identifiable {
    let id: String          // nil for default, or the alternateIconName string
    let name: String
    let preview: String     // SF Symbol to preview until real icon images exist
    let accent: Color
}

private let iconOptions: [AppIconOption] = [
    AppIconOption(id: "default",   name: "Default",  preview: "pill.fill",       accent: Color(hex: "5B9BD5")),
    AppIconOption(id: "Midnight",  name: "Midnight",  preview: "moon.stars.fill", accent: Color(hex: "2C2C54")),
    AppIconOption(id: "Coral",     name: "Coral",     preview: "sun.horizon.fill", accent: Color(hex: "E8836A")),
    AppIconOption(id: "Forest",    name: "Forest",    preview: "leaf.fill",       accent: Color(hex: "5FAD7C")),
    AppIconOption(id: "Rose",      name: "Rose Gold", preview: "heart.fill",      accent: Color(hex: "D4829A")),
]

struct AppIconPickerView: View {

    @State private var currentIconName: String = UIApplication.shared.alternateIconName ?? "default"

    var body: some View {
        List {
            Section {
                Text("Choose an app icon. The change takes effect immediately.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }

            Section {
                ForEach(iconOptions) { option in
                    Button {
                        switchIcon(to: option)
                    } label: {
                        HStack(spacing: 16) {
                            // Icon preview tile
                            ZStack {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(option.accent.gradient)
                                    .frame(width: 56, height: 56)
                                Image(systemName: option.preview)
                                    .font(.system(size: 24, weight: .medium))
                                    .foregroundStyle(.white)
                            }
                            .shadow(color: option.accent.opacity(0.35), radius: 6, x: 0, y: 3)

                            Text(option.name)
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)

                            Spacer()

                            if currentIconName == option.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(option.accent)
                                    .font(.title3)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }

            Section {
                Text("Note: custom icons require the icon image files to be added by a developer. Placeholder colours are shown above.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .navigationTitle("App Icon")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            currentIconName = UIApplication.shared.alternateIconName ?? "default"
        }
    }

    private func switchIcon(to option: AppIconOption) {
        let name: String? = option.id == "default" ? nil : option.id
        UIApplication.shared.setAlternateIconName(name) { error in
            if let error {
                print("setAlternateIconName error: \(error)")
                return
            }
            DispatchQueue.main.async {
                currentIconName = option.id
            }
        }
    }
}

#Preview {
    NavigationStack { AppIconPickerView() }
}
