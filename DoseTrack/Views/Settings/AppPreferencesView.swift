// DoseTrack/Views/Settings/AppPreferencesView.swift
import SwiftUI

// MARK: - Color Theme

enum AppColorTheme: String, CaseIterable, Identifiable {
    case oceanBlue   = "Ocean Blue"
    case sunsetCoral = "Sunset Coral"
    case forestGreen = "Forest Green"
    case purpleHaze  = "Purple Haze"
    case roseGold    = "Rose Gold"
    case mintFresh   = "Mint Fresh"

    var id: String { rawValue }

    /// Pastel primary — used as the app accent / tint colour.
    var primary: Color {
        switch self {
        case .oceanBlue:   return Color(hex: "5B9BD5")
        case .sunsetCoral: return Color(hex: "E8836A")
        case .forestGreen: return Color(hex: "5FAD7C")
        case .purpleHaze:  return Color(hex: "9B7EC8")
        case .roseGold:    return Color(hex: "D4829A")
        case .mintFresh:   return Color(hex: "4FB8B0")
        }
    }

    /// Slightly lighter complementary pastel.
    var secondary: Color {
        switch self {
        case .oceanBlue:   return Color(hex: "85BFED")
        case .sunsetCoral: return Color(hex: "F0AB8E")
        case .forestGreen: return Color(hex: "8FD4A0")
        case .purpleHaze:  return Color(hex: "C4A8E6")
        case .roseGold:    return Color(hex: "EDB0C4")
        case .mintFresh:   return Color(hex: "88D9D4")
        }
    }

    /// Very light pastel for card/section backgrounds.
    var background: Color {
        switch self {
        case .oceanBlue:   return Color(hex: "EBF4FF")
        case .sunsetCoral: return Color(hex: "FFF0EB")
        case .forestGreen: return Color(hex: "EBF8F0")
        case .purpleHaze:  return Color(hex: "F3EEFF")
        case .roseGold:    return Color(hex: "FFF0F5")
        case .mintFresh:   return Color(hex: "E8F9F8")
        }
    }

    var icon: String {
        switch self {
        case .oceanBlue:   return "water.waves"
        case .sunsetCoral: return "sun.horizon.fill"
        case .forestGreen: return "leaf.fill"
        case .purpleHaze:  return "sparkles"
        case .roseGold:    return "heart.fill"
        case .mintFresh:   return "wind"
        }
    }
}

// MARK: - Preferences View

struct AppPreferencesView: View {
    @AppStorage("timeFormat")        private var timeFormat: String = "system"
    @AppStorage("colorTheme")        private var colorTheme: String = AppColorTheme.oceanBlue.rawValue
    @AppStorage("hapticsEnabled")    private var hapticsEnabled: Bool = true
    @AppStorage("showDoseBadge")     private var showDoseBadge: Bool = true
    @AppStorage("compactRows")       private var compactRows: Bool = false
    @AppStorage("healthKitEnabled")  private var healthKitEnabled: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("appearanceOverride") private var appearanceOverride: String = "system"
    @StateObject private var healthKit = HealthKitManager.shared

    var body: some View {
        List {
            // MARK: Appearance
            Section {
                Picker("Appearance", selection: $appearanceOverride) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            } header: {
                Text("Appearance")
            }

            // MARK: Colour Theme
            Section("Colour Theme") {
                ForEach(AppColorTheme.allCases) { theme in
                    Button {
                        colorTheme = theme.rawValue
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                LinearGradient(
                                    colors: [theme.primary, theme.secondary],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .frame(width: 36, height: 36)
                                Image(systemName: theme.icon)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                            Text(theme.rawValue)
                                .foregroundStyle(.primary)
                            Spacer()
                            if colorTheme == theme.rawValue {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(theme.primary)
                            }
                        }
                    }
                }
            }

            // MARK: Time Format
            Section("Time Format") {
                Picker("Time Format", selection: $timeFormat) {
                    Text("System Default").tag("system")
                    Text("12-hour (1:30 PM)").tag("12h")
                    Text("24-hour (13:30)").tag("24h")
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            // MARK: General
            Section("General") {
                Toggle(isOn: $hapticsEnabled) {
                    Label("Haptic Feedback", systemImage: "iphone.radiowaves.left.and.right")
                }

                Toggle(isOn: $showDoseBadge) {
                    Label("App Badge (pending doses)", systemImage: "app.badge.fill")
                }

                Toggle(isOn: $compactRows) {
                    Label("Compact Dose Rows", systemImage: "list.dash")
                }
            }

            // MARK: Apple Health
            if healthKit.isAvailable {
                Section {
                    Toggle(isOn: $healthKitEnabled) {
                        Label("Sync to Apple Health", systemImage: "heart.fill")
                    }
                    .onChange(of: healthKitEnabled) { _, enabled in
                        if enabled && !healthKit.isAuthorized {
                            Task { await healthKit.requestAuthorization() }
                        }
                    }
                } header: {
                    Text("Apple Health")
                } footer: {
                    Text("When enabled, each dose you mark as taken is logged to Apple Health as a mindfulness session tagged with the medication name.")
                        .font(.caption)
                }
            }

            // MARK: App Icon
            Section("App Icon") {
                NavigationLink {
                    AppIconPickerView()
                } label: {
                    Label("Change App Icon", systemImage: "app.fill")
                }
            }
        }
        .scrollIndicators(.visible)
        .navigationTitle("Preferences")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(preferredScheme)
    }

    private var preferredScheme: ColorScheme? {
        switch appearanceOverride {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }
}

#Preview {
    NavigationStack { AppPreferencesView() }
}
