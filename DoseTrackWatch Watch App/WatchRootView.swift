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
//
// Rebuilt to match the iOS SplashView's style (light radial background, transparent WatchHero
// mascot with a spring-overshoot entrance, confetti burst, wordmark) instead of the old separate
// dark-navy/boxed-mascot animation — scaled down for the watch screen. Kept as its own
// implementation (not shared code) since the watch app target compiles independently of the iOS
// app target.

private struct WatchSplashView: View {
    @State private var glowScale: CGFloat = 0.3
    @State private var glowOpacity: Double = 0

    @State private var heroScale: CGFloat = 0.4
    @State private var heroOpacity: Double = 0
    @State private var heroRotation: Double = -10

    @State private var burst: CGFloat = 0

    @State private var wordmarkOpacity: Double = 0
    @State private var wordmarkScale: CGFloat = 0.7

    @State private var exitOpacity: Double = 1.0

    private let confetti = WatchConfettiPiece.burst(count: 14)

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [Color(hex: "E4EDFF"), Color.white],
                center: .center, startRadius: 4, endRadius: 110
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color(hex: "5B8AF0").opacity(0.18))
                .frame(width: 90, height: 90)
                .scaleEffect(glowScale)
                .opacity(glowOpacity)
                .blur(radius: 10)

            ForEach(confetti) { piece in
                piece.shape
                    .fill(piece.color)
                    .frame(width: piece.size.width, height: piece.size.height)
                    .modifier(WatchConfettiEffect(progress: burst, piece: piece))
            }

            VStack(spacing: 6) {
                Image("WatchHero")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
                    .scaleEffect(heroScale)
                    .rotationEffect(.degrees(heroRotation))
                    .opacity(heroOpacity)

                Text("DoseTrack")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(Color(hex: "3B5FCC"))
                    .scaleEffect(wordmarkScale)
                    .opacity(wordmarkOpacity)
            }
        }
        .opacity(exitOpacity)
        .onAppear { runSequence() }
    }

    private func runSequence() {
        withAnimation(.easeOut(duration: 0.25)) {
            glowScale = 1.0; glowOpacity = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.52)) {
                heroScale = 1.0; heroOpacity = 1; heroRotation = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.easeOut(duration: 0.85)) { burst = 1 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                wordmarkScale = 1.0; wordmarkOpacity = 1
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.35) {
            withAnimation(.easeIn(duration: 0.25)) { exitOpacity = 0 }
        }
    }
}

// MARK: - Watch confetti (scaled-down twin of the iOS SplashView confetti)

private struct WatchConfettiPiece: Identifiable {
    let id: Int
    let angle: Double
    let distance: CGFloat
    let color: Color
    let size: CGSize
    let rotation: Double
    let isCapsule: Bool

    var shape: AnyWatchShapeView {
        isCapsule ? AnyWatchShapeView(Capsule()) : AnyWatchShapeView(RoundedRectangle(cornerRadius: 1.5))
    }

    func offset(at progress: CGFloat) -> CGSize {
        let eased = 1 - pow(1 - progress, 2)
        let travel = 30 + distance * eased
        let gravity = 26 * progress * progress
        return CGSize(width: cos(angle) * travel, height: sin(angle) * travel + gravity)
    }

    func opacity(at progress: CGFloat) -> Double {
        let p = Double(progress)
        if p < 0.12 { return p / 0.12 }
        if p > 0.6 { return max(0, 1 - (p - 0.6) / 0.4) }
        return 1
    }

    static func burst(count: Int) -> [WatchConfettiPiece] {
        let palette: [Color] = [
            Color(hex: "5B8AF0"), Color(hex: "F27A9B"), Color(hex: "FFB443"),
            Color(hex: "5FCB7E"), Color(hex: "FFD23F"), Color(hex: "A78BFA"),
        ]
        var rng = WatchSeededGenerator(seed: 20260711)
        return (0..<count).map { i in
            WatchConfettiPiece(
                id: i,
                angle: Double.random(in: -Double.pi ... 0.35 * Double.pi, using: &rng),
                distance: CGFloat.random(in: 24...58, using: &rng),
                color: palette[Int.random(in: 0..<palette.count, using: &rng)],
                size: Bool.random(using: &rng) ? CGSize(width: 3, height: 7) : CGSize(width: 4, height: 4),
                rotation: Double.random(in: 90...300, using: &rng) * (Bool.random(using: &rng) ? 1 : -1),
                isCapsule: Bool.random(using: &rng)
            )
        }
    }
}

private struct WatchConfettiEffect: ViewModifier, Animatable {
    var progress: CGFloat
    let piece: WatchConfettiPiece

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(piece.rotation * Double(progress) * 3))
            .offset(piece.offset(at: progress))
            .opacity(piece.opacity(at: progress))
    }
}

private struct AnyWatchShapeView: Shape {
    private let pathBuilder: (CGRect) -> Path
    init<S: Shape>(_ shape: S) { pathBuilder = { shape.path(in: $0) } }
    func path(in rect: CGRect) -> Path { pathBuilder(rect) }
}

private struct WatchSeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
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
