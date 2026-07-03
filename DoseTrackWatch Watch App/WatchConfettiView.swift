// DoseTrackWatch Watch App/WatchConfettiView.swift
import SwiftUI

// MARK: - Particle

private struct WatchParticle {
    let birthTime: Double
    let x0: CGFloat
    let vx: CGFloat
    let vy: CGFloat
    let rotation0: Double
    let rotSpeed: Double
    let color: Color
    let size: CGFloat
    let isCircle: Bool

    static let palette: [Color] = [
        Color(r: 255, g: 107, b: 107), Color(r: 255, g: 217, b: 61),
        Color(r: 107, g: 203, b: 119), Color(r: 77,  g: 150, b: 255),
        Color(r: 199, g: 125, b: 255), Color(r: 255, g: 159, b: 28),
        .white
    ]

    static func make(stagger: Double) -> WatchParticle {
        WatchParticle(
            birthTime:  Date.timeIntervalSinceReferenceDate + stagger,
            x0:         CGFloat.random(in: 0...1),
            vx:         CGFloat.random(in: -40...40),
            vy:         CGFloat.random(in: 120...280),
            rotation0:  Double.random(in: 0...360),
            rotSpeed:   Double.random(in: -300...300),
            color:      palette.randomElement()!,
            size:       CGFloat.random(in: 5...10),
            isCircle:   Bool.random()
        )
    }
}

// MARK: - WatchConfettiView

struct WatchConfettiView: View {
    var onFinish: (() -> Void)? = nil

    private let count = 55
    private let duration: Double = 2.8
    @State private var particles: [WatchParticle] = []

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let now = tl.date.timeIntervalSinceReferenceDate
                for p in particles {
                    let age = now - p.birthTime
                    guard age > 0 else { continue }

                    let x = p.x0 * size.width + p.vx * age
                    let y = -14 + p.vy * age + 0.5 * 160 * age * age
                    guard y < size.height + 20 else { continue }

                    let fade = min(1, max(0, 1 - (age - (duration - 0.6)) / 0.6))
                    let rot  = Angle.degrees(p.rotation0 + p.rotSpeed * age)

                    ctx.opacity = fade
                    ctx.translateBy(x: x, y: y)
                    ctx.rotate(by: rot)

                    let rect = CGRect(x: -p.size/2, y: -p.size/2, width: p.size, height: p.size)
                    let path = p.isCircle ? Path(ellipseIn: rect) : Path(rect)
                    ctx.fill(path, with: .color(p.color))

                    ctx.rotate(by: -rot)
                    ctx.translateBy(x: -x, y: -y)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            particles = (0..<count).map { i in
                WatchParticle.make(stagger: Double(i) / Double(count) * 0.5)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.2) {
                onFinish?()
            }
        }
    }
}

private extension Color {
    init(r: Double, g: Double, b: Double) {
        self.init(red: r/255, green: g/255, blue: b/255)
    }
}
