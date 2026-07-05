// DoseTrack/Views/Settings/AppIconPickerView.swift
// Lets users switch between alternate app icons. Each option reuses one of the
// existing profile-avatar image sets already in Assets.xcassets (real artwork,
// not a placeholder) — see the matching CFBundleAlternateIcons entries in Info.plist.

import SwiftUI

private struct AppIconOption: Identifiable {
    let id: String   // nil (represented as "default") for the primary icon, else the avatar key
    var avatar: AvatarOption? { allAvatars.first { $0.key == id } }
}

private let iconOptions: [AppIconOption] = [
    AppIconOption(id: "default"),
    AppIconOption(id: "bear"),
    AppIconOption(id: "robot"),
    AppIconOption(id: "wizard"),
    AppIconOption(id: "hero"),
    AppIconOption(id: "owl"),
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
                            iconPreview(for: option)
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)

                            Text(option.avatar?.name ?? "Default")
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)

                            Spacer()

                            if currentIconName == option.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                                    .font(.title3)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("App Icon")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            currentIconName = UIApplication.shared.alternateIconName ?? "default"
        }
    }

    @ViewBuilder
    private func iconPreview(for option: AppIconOption) -> some View {
        // The default icon lives in an .appiconset, which isn't reliably loadable via
        // UIImage(named:) — render a stand-in tile instead of risking a blank image.
        if option.id == "default" {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.accentColor.gradient)
                Image(systemName: "pill.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white)
            }
        } else if let assetName = option.avatar?.assetName, let ui = UIImage(named: assetName) {
            Image(uiImage: flattenOnWhite(ui)).resizable().scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.accentColor.gradient)
        }
    }

    private func switchIcon(to option: AppIconOption) {
        let name: String? = option.id == "default" ? nil : "Avatar_\(option.id)"
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
