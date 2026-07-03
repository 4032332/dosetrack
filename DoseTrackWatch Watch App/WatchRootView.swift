// DoseTrackWatch Watch App/WatchRootView.swift
import SwiftUI

struct WatchRootView: View {
    @State private var showSplash = true

    var body: some View {
        ZStack {
            TodayWatchView()

            if showSplash {
                WatchSplashView()
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: showSplash)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
                showSplash = false
            }
        }
    }
}

// MARK: - Watch Splash

private struct WatchSplashView: View {
    // Phase 1 – drop in
    @State private var milliY: CGFloat = -200
    @State private var milliRotation: Double = 0

    // Phase 2 – rattle
    @State private var shakeX: CGFloat = 0
    @State private var milliScale: CGFloat = 1.0

    // Phase 3 – pill burst
    @State private var burstProgress: CGFloat = 0
    @State private var burstOpacity: Double = 0

    // Phase 4 – labels
    @State private var labelScale: CGFloat = 0.6
    @State private var labelOpacity: Double = 0
    @State private var taglineOpacity: Double = 0

    // Exit
    @State private var exitOpacity: Double = 1.0

    private let pillAngles: [Double] = [0, 60, 120, 180, 240, 300]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "1A1A2E"), Color(hex: "0F3460")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Pill burst
            ZStack {
                ForEach(Array(pillAngles.enumerated()), id: \.offset) { i, angle in
                    Capsule()
                        .fill(pillColor(i).opacity(0.9))
                        .frame(width: 12, height: 6)
                        .rotationEffect(.degrees(angle))
                        .offset(
                            x: cos(angle * .pi / 180) * 40 * burstProgress,
                            y: sin(angle * .pi / 180) * 40 * burstProgress
                        )
                        .opacity(burstOpacity * (1 - burstProgress * 0.5))
                }
            }

            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.white)
                        .frame(width: 52, height: 52)
                        .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
                    Image("MilliHero")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 44, height: 44)
                }
                .rotationEffect(.degrees(milliRotation))
                .scaleEffect(milliScale)
                .offset(x: shakeX, y: milliY)

                VStack(spacing: 2) {
                    Text("DoseTrack")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Never miss a dose.")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.65))
                        .opacity(taglineOpacity)
                }
                .scaleEffect(labelScale)
                .opacity(labelOpacity)
            }
        }
        .opacity(exitOpacity)
        .onAppear { runSequence() }
    }

    private func pillColor(_ i: Int) -> Color {
        let colors: [Color] = [
            Color(hex: "FF6B6B"), Color(hex: "FFD93D"), Color(hex: "6BCB77"),
            Color(hex: "4D96FF"), Color(hex: "C77DFF"), Color(hex: "FF9F1C")
        ]
        return colors[i % colors.count]
    }

    private func runSequence() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) {
            milliY = 0
            milliRotation = 360
        }

        let shakeTimes: [(Double, CGFloat)] = [
            (0.50, -10), (0.56, 10), (0.61, -7), (0.66, 7), (0.71, 0)
        ]
        for (delay, x) in shakeTimes {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.interactiveSpring(response: 0.06, dampingFraction: 0.3)) {
                    shakeX = x
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.51) {
            withAnimation(.easeInOut(duration: 0.15)) { milliScale = 1.1 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.66) {
            withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) { milliScale = 1.0 }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            burstOpacity = 1
            withAnimation(.easeOut(duration: 0.35)) { burstProgress = 1 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.78) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                labelScale = 1.0; labelOpacity = 1
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
            withAnimation(.easeIn(duration: 0.25)) { taglineOpacity = 1 }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.35) {
            withAnimation(.easeIn(duration: 0.25)) { exitOpacity = 0 }
        }
    }
}

private extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: h).scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8)  & 0xFF) / 255
        let b = Double(rgb & 0xFF)          / 255
        self.init(red: r, green: g, blue: b)
    }
}
