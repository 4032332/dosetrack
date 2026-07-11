// DoseTrack/Views/Settings/AvatarPickerView.swift
import SwiftUI
import PhotosUI

// MARK: - Avatar catalogue

struct AvatarOption: Identifiable {
    var id: String { key }
    let key: String           // stored in AppStorage / used as asset name
    let name: String
    let assetName: String?    // nil for a fallback-emoji-only avatar
    let fallbackEmoji: String
    let gradient: [Color]
}

let allAvatars: [AvatarOption] = [
    AvatarOption(key: "milli",   name: "Milli",           assetName: "SplashHero",
                 fallbackEmoji: "💊", gradient: [Color(hex: "5B8AF0"), Color(hex: "3B5FCC")]),
    AvatarOption(key: "bear",    name: "Doctor Bear",      assetName: "Avatar_bear",
                 fallbackEmoji: "🐻", gradient: [Color(hex: "8D6E63"), Color(hex: "5D4037")]),
    AvatarOption(key: "robot",   name: "Nurse Bot",        assetName: "Avatar_robot",
                 fallbackEmoji: "🤖", gradient: [Color(hex: "546E7A"), Color(hex: "263238")]),
    AvatarOption(key: "wizard",  name: "Potion Wizard",    assetName: "Avatar_wizard",
                 fallbackEmoji: "🧙", gradient: [Color(hex: "7B1FA2"), Color(hex: "4A148C")]),
    AvatarOption(key: "hero",    name: "Pill Hero",        assetName: "Avatar_hero",
                 fallbackEmoji: "🦸", gradient: [Color(hex: "F44336"), Color(hex: "B71C1C")]),
    AvatarOption(key: "owl",     name: "Professor Owl",    assetName: "Avatar_owl",
                 fallbackEmoji: "🦉", gradient: [Color(hex: "F57F17"), Color(hex: "E65100")]),
    AvatarOption(key: "cat",     name: "Nurse Cat",        assetName: "Avatar_cat",
                 fallbackEmoji: "🐱", gradient: [Color(hex: "EC407A"), Color(hex: "880E4F")]),
    AvatarOption(key: "fox",     name: "Dr. Fox",          assetName: "Avatar_fox",
                 fallbackEmoji: "🦊", gradient: [Color(hex: "FF7043"), Color(hex: "BF360C")]),
    AvatarOption(key: "alien",   name: "Space Medic",      assetName: "Avatar_alien",
                 fallbackEmoji: "👽", gradient: [Color(hex: "00897B"), Color(hex: "004D40")]),
    AvatarOption(key: "dragon",  name: "Medicine Dragon",  assetName: "Avatar_dragon",
                 fallbackEmoji: "🐉", gradient: [Color(hex: "43A047"), Color(hex: "1B5E20")]),
]

// MARK: - Avatar Image helper

/// Returns the UIImage for an avatar key, or nil if not found.
func avatarImage(for key: String) -> UIImage? {
    let opt = allAvatars.first { $0.key == key }
    if let name = opt?.assetName { return UIImage(named: name) }
    return nil
}

/// Composites a UIImage onto a solid white background to remove any semi-transparent or
/// grainy pixels from the source PNG. This prevents transparency artifacts from appearing
/// against coloured backgrounds.
func flattenOnWhite(_ image: UIImage, size: CGSize? = nil) -> UIImage {
    let targetSize = size ?? image.size
    guard targetSize.width > 0, targetSize.height > 0 else { return image }
    let renderer = UIGraphicsImageRenderer(size: targetSize)
    return renderer.image { ctx in
        UIColor.white.setFill()
        ctx.fill(CGRect(origin: .zero, size: targetSize))
        image.draw(in: CGRect(origin: .zero, size: targetSize))
    }
}

// MARK: - Tessellated background

private struct MedicalEmojiBackground: View {
    var baseColor: Color = Color(hex: "EEF4FF")
    private let emojis = ["💊", "💉", "🩺", "🫀", "🧠", "🩹", "❤️", "💊", "🩺", "💉"]

    var body: some View {
        Canvas { context, size in
            // Base fill
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(baseColor))

            let step: CGFloat = size.width / 3.5
            let fontSize = size.width * 0.18

            var row = 0
            var y: CGFloat = -step * 0.5
            while y < size.height + step {
                var col = 0
                let xOffset = (row % 2 == 0) ? 0 : step * 0.5
                var x: CGFloat = -step * 0.5 + xOffset
                while x < size.width + step {
                    let idx = abs(row * 4 + col) % emojis.count
                    let emoji = emojis[idx]
                    let resolved = context.resolve(
                        Text(emoji).font(.system(size: fontSize))
                    )
                    var ctx = context
                    ctx.opacity = 0.22
                    ctx.draw(resolved, at: CGPoint(x: x, y: y), anchor: .center)
                    x += step
                    col += 1
                }
                y += step * 0.75
                row += 1
            }
        }
    }
}

// MARK: - Avatar Badge (reusable)

struct AvatarBadge: View {
    let avatarKey: String
    let isPro: Bool
    var size: CGFloat = 40
    var customImageData: Data? = nil

    private var avatar: AvatarOption {
        allAvatars.first { $0.key == avatarKey } ?? allAvatars[0]
    }

    // Soft pastel tint unique to each avatar (very light, consistent feel)
    private var pastelBase: Color {
        let c = avatar.gradient.first ?? Color(hex: "EEF4FF")
        return c.opacity(0.18)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(.white)
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)
                .overlay {
                    avatarContent
                        .frame(width: size * 0.88, height: size * 0.88)
                        .clipShape(Circle())
                }

            if isPro {
                // High-contrast Plus marker: a filled brand-blue disc with a white star, ringed in
                // white so it reads clearly against any avatar. (Was a low-contrast yellow star.)
                Image(systemName: "star.fill")
                    .font(.system(size: size * 0.16, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(size * 0.06)
                    .background(Circle().fill(Color(hex: "#3B5FCC")))
                    .overlay(Circle().stroke(.white, lineWidth: max(1, size * 0.03)))
                    .offset(x: 2, y: 2)
            }
        }
    }

    @ViewBuilder
    private var avatarContent: some View {
        if let data = customImageData, let ui = UIImage(data: data) {
            Image(uiImage: flattenOnWhite(ui))
                .resizable().scaledToFill()
        } else if let assetName = avatar.assetName, let ui = UIImage(named: assetName) {
            Image(uiImage: flattenOnWhite(ui))
                .resizable().scaledToFit()
        } else {
            Text(avatar.fallbackEmoji)
                .font(.system(size: size * 0.45))
        }
    }
}

// MARK: - Avatar Picker Sheet

struct AvatarPickerView: View {
    @Binding var selectedKey: String
    /// Raw JPEG/PNG data if user picked a custom photo; nil = use preset.
    @Binding var customPhotoData: Data?

    @Environment(\.dismiss) private var dismiss
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var showingCamera = false
    @State private var cameraCaptured: UIImage? = nil

    let columns = [GridItem(.adaptive(minimum: 80), spacing: 16)]

    var body: some View {
        NavigationStack {
            List {
                // MARK: Custom photo options
                Section("Use Your Own Photo") {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Choose from Photo Library", systemImage: "photo.on.rectangle")
                    }
                    .onChange(of: photoItem) { _, item in
                        Task {
                            if let data = try? await item?.loadTransferable(type: Data.self) {
                                customPhotoData = data
                                selectedKey = "custom"
                                dismiss()
                            }
                        }
                    }

                    Button {
                        showingCamera = true
                    } label: {
                        Label("Take Photo", systemImage: "camera.fill")
                    }
                }

                // MARK: Preset avatars
                Section("Choose an Avatar") {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(allAvatars) { avatar in
                            Button {
                                selectedKey = avatar.key
                                customPhotoData = nil
                                dismiss()
                            } label: {
                                VStack(spacing: 6) {
                                    ZStack {
                                        AvatarBadge(avatarKey: avatar.key, isPro: false, size: 64)
                                        if selectedKey == avatar.key && customPhotoData == nil {
                                            Circle()
                                                .stroke(Color.accentColor, lineWidth: 3)
                                                .frame(width: 64, height: 64)
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.white)
                                                .background(Circle().fill(Color.accentColor).padding(-1))
                                                .offset(x: 22, y: -22)
                                        }
                                    }
                                    Text(avatar.name)
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.center)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }
            .scrollIndicators(.visible)
            .navigationTitle("Profile Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingCamera) {
                CameraPickerView { image in
                    if let data = image.jpegData(compressionQuality: 0.85) {
                        customPhotoData = data
                        selectedKey = "custom"
                    }
                    showingCamera = false
                }
            }
        }
    }
}

// MARK: - Camera picker

struct CameraPickerView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        init(onCapture: @escaping (UIImage) -> Void) { self.onCapture = onCapture }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { onCapture(img) }
            picker.dismiss(animated: true)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

#Preview {
    AvatarPickerView(selectedKey: .constant("milli"), customPhotoData: .constant(nil))
}
