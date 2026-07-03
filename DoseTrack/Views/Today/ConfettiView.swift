// DoseTrack/Views/Today/ConfettiView.swift
import SwiftUI

// MARK: - Particle model

private struct ConfettiParticle {
    let birthTime: Double
    let x0: CGFloat          // launch X (0–1 of width)
    let vx: CGFloat          // horizontal velocity (pts/s)
    let vy: CGFloat          // vertical velocity (pts/s, positive = down)
    let rotation0: Double    // initial rotation degrees
    let rotSpeed: Double     // degrees/s
    let color: Color
    let size: CGFloat
    let shape: Shape

    enum Shape: CaseIterable { case rect, circle, triangle }

    static let palette: [Color] = [
        .init(hex: "FF6B6B"), .init(hex: "FFD93D"), .init(hex: "6BCB77"),
        .init(hex: "4D96FF"), .init(hex: "C77DFF"), .init(hex: "FF9F1C"),
        .init(hex: "2EC4B6"), .white
    ]

    static func make(in size: CGSize, stagger: Double) -> ConfettiParticle {
        let now = Date.timeIntervalSinceReferenceDate
        return ConfettiParticle(
            birthTime:  now + stagger,
            x0:         CGFloat.random(in: 0...1),
            vx:         CGFloat.random(in: -60...60),
            vy:         CGFloat.random(in: 180...420),
            rotation0:  Double.random(in: 0...360),
            rotSpeed:   Double.random(in: -360...360),
            color:      palette.randomElement()!,
            size:       CGFloat.random(in: 7...14),
            shape:      Shape.allCases.randomElement()!
        )
    }
}

// MARK: - ConfettiView

struct ConfettiView: View {
    var particleCount: Int = 120
    /// Called once the animation finishes so parent can remove the overlay.
    var onFinish: (() -> Void)? = nil

    @State private var particles: [ConfettiParticle] = []
    @State private var startTime: Double = 0
    private let duration: Double = 3.2

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let now = tl.date.timeIntervalSinceReferenceDate
                for p in particles {
                    let age = now - p.birthTime
                    guard age > 0 else { continue }

                    let x = p.x0 * size.width + p.vx * age
                    let y = -20 + p.vy * age + 0.5 * 200 * age * age   // gravity = 200 pts/s²
                    guard y < size.height + 30 else { continue }

                    let opacity = min(1, max(0, 1 - (age - (duration - 0.8)) / 0.8))
                    let rot = Angle.degrees(p.rotation0 + p.rotSpeed * age)

                    ctx.opacity = opacity
                    ctx.translateBy(x: x, y: y)
                    ctx.rotate(by: rot)

                    switch p.shape {
                    case .rect:
                        let r = CGRect(x: -p.size/2, y: -p.size * 0.35,
                                       width: p.size, height: p.size * 0.7)
                        ctx.fill(Path(r), with: .color(p.color))
                    case .circle:
                        let r = CGRect(x: -p.size/2, y: -p.size/2,
                                       width: p.size, height: p.size)
                        ctx.fill(Path(ellipseIn: r), with: .color(p.color))
                    case .triangle:
                        var path = Path()
                        path.move(to: .init(x: 0, y: -p.size/2))
                        path.addLine(to: .init(x:  p.size/2, y:  p.size/2))
                        path.addLine(to: .init(x: -p.size/2, y:  p.size/2))
                        path.closeSubpath()
                        ctx.fill(path, with: .color(p.color))
                    }

                    // Reset transform for next particle
                    ctx.rotate(by: -rot)
                    ctx.translateBy(x: -x, y: -y)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            startTime = Date.timeIntervalSinceReferenceDate
            particles = (0..<particleCount).map { i in
                ConfettiParticle.make(
                    in: UIScreen.main.bounds.size,
                    stagger: Double(i) / Double(particleCount) * 0.6
                )
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.2) {
                onFinish?()
            }
        }
    }
}

