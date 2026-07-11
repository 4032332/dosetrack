// DoseTrack/Views/Settings/AppIconPickerView.swift
import SwiftUI

/// DoseTrack Pro perk: pick an alternate home-screen app icon. Presenting this screen at all
/// already implies Pro (the Settings row that pushes here is itself Pro-gated), so no paywall
/// logic lives here.
struct AppIconPickerView: View {
    @State private var selected: AppIconOption = AppIconManager.current
    @State private var isApplying = false

    private let columns = [GridItem(.adaptive(minimum: 88), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(AppIconOption.allCases) { option in
                    Button {
                        guard option != selected else { return }
                        let previous = selected
                        selected = option
                        isApplying = true
                        Task {
                            let ok = await AppIconManager.setIcon(option)
                            isApplying = false
                            if !ok { selected = previous }
                        }
                    } label: {
                        VStack(spacing: 8) {
                            ZStack(alignment: .bottomTrailing) {
                                iconThumbnail(for: option)
                                if selected == option {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(.white, Color.accentColor)
                                        .background(Circle().fill(.white))
                                        .offset(x: 4, y: 4)
                                }
                            }
                            Text(option.displayName)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isApplying)
                }
            }
            .padding(20)
        }
        .navigationTitle("App Icon")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func iconThumbnail(for option: AppIconOption) -> some View {
        Group {
            if let image = option.previewImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.secondary.opacity(0.2)
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(selected == option ? Color.accentColor : .clear, lineWidth: 2.5)
        )
    }
}

#Preview {
    NavigationStack { AppIconPickerView() }
}
