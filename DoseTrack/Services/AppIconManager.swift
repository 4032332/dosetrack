// DoseTrack/Services/AppIconManager.swift
import UIKit

/// Lets a DoseTrack Pro user choose an alternate home-screen app icon. Icon files themselves are
/// loose PNGs under DoseTrack/Resources/AlternateIcons (declared in Info.plist's
/// CFBundleAlternateIcons — see the comment there), NOT in the Assets.xcassets AppIcon.appiconset,
/// since UIApplication.setAlternateIconName requires plain bundle files, not a compiled catalog.
enum AppIconOption: String, CaseIterable, Identifiable {
    case `default`
    case dark = "AltIconDark"
    case mint = "AltIconMint"
    case lavender = "AltIconLavender"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .default:  return "Default"
        case .dark:     return "Midnight"
        case .mint:     return "Mint"
        case .lavender: return "Lavender"
        }
    }

    /// `nil` tells `setAlternateIconName` to restore the primary icon.
    var bundleIconName: String? { self == .default ? nil : rawValue }

    /// Filename (no extension) of the picker-preview thumbnail. App-icon asset catalogs (as
    /// opposed to regular imagesets) aren't reliably loadable via UIImage(named:), so every
    /// option — including the default — has a loose "-Preview" PNG under AlternateIcons/.
    var previewImage: UIImage? {
        let name = self == .default ? "AppIconDefault" : rawValue
        guard let path = Bundle.main.path(forResource: "\(name)-Preview", ofType: "png") else { return nil }
        return UIImage(contentsOfFile: path)
    }
}

@MainActor
enum AppIconManager {

    static var current: AppIconOption {
        guard let name = UIApplication.shared.alternateIconName else { return .default }
        return AppIconOption(rawValue: name) ?? .default
    }

    @discardableResult
    static func setIcon(_ option: AppIconOption) async -> Bool {
        guard UIApplication.shared.supportsAlternateIcons else { return false }
        guard UIApplication.shared.alternateIconName != option.bundleIconName else { return true }
        do {
            try await UIApplication.shared.setAlternateIconName(option.bundleIconName)
            return true
        } catch {
            print("setAlternateIconName error: \(error)")
            return false
        }
    }
}
