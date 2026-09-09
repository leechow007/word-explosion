import AppKit
import SwiftUI

// MARK: - 点爆粒子特效（独立穿透窗口，避免遮挡其他词泡热区）

@MainActor
final class BurstFXController {
    private let window: NSPanel
    private let size: CGFloat = 240

    init(center: CGPoint, appearance: BubbleAppearance, screen: NSScreen?) {
        let panel = NSPanel(
            contentRect: NSRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        window = panel

        let hosting = NSHostingView(rootView: BurstFXView(accent: appearance.accent, size: size))
        hosting.frame = NSRect(x: 0, y: 0, width: size, height: size)
        panel.contentView = hosting
    }

    func show() {
        window.orderFrontRegardless()
    }
}

struct BurstFXView: View {
    let accent: Color
    let size: CGFloat
    let startDate = Date()

    private struct Particle {
        let angle: Double
        let distance: CGFloat
        let delay: Double
        let dot: CGFloat
        let white: Bool
    }

    private let particles: [Particle] = {
        var list: [Particle] = []
        let count = Int.random(in: 15 ... 22)
        for _ in 0 ..< count {
            list.append(Particle(
                angle: Double.random(in: 0 ..< .pi * 2),
                distance: CGFloat.random(in: 42 ... 92),
                delay: Double.random(in: 0 ... 0.18),
                dot: CGFloat.random(in: 3 ... 8),
                white: Bool.random()
            ))
        }
        return list
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            let progress = min(1, max(0, context.date.timeIntervalSince(startDate) / 0.92))
            Canvas { canvas, canvasSize in
                let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)

                // 光晕环
                let ringProgress = easeOutCubic(min(1, progress * 1.25))
                let ringR = 8 + ringProgress * 46
                let ringAlpha = (1 - ringProgress) * 0.55
                let ringRect = CGRect(x: center.x - ringR, y: center.y - ringR,
                                      width: ringR * 2, height: ringR * 2)
                canvas.stroke(Path(ellipseIn: ringRect),
                              with: .color(accent.opacity(ringAlpha)),
                              lineWidth: 2.5)

                // 粒子
                for p in particles {
                    let t = (progress - p.delay) / (1 - p.delay)
                    guard t > 0 else { continue }
                    let eased = easeOutCubic(min(1, t))
                    let dist = eased * p.distance
                    let pos = CGPoint(x: center.x + cos(p.angle) * dist,
                                      y: center.y + sin(p.angle) * dist)
                    let alpha = (1 - eased) * 0.95
                    let dotSize = p.dot * (1 - eased * 0.55)
                    let rect = CGRect(x: pos.x - dotSize / 2, y: pos.y - dotSize / 2,
                                      width: dotSize, height: dotSize)
                    let color = p.white ? Color.white : accent
                    canvas.fill(Path(ellipseIn: rect), with: .color(color.opacity(alpha)))
                }
            }
            .frame(width: size, height: size)
            .allowsHitTesting(false)
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }

    private func easeOutCubic(_ t: Double) -> Double {
        let x = min(1, max(0, t))
        return 1 - pow(1 - x, 3)
    }
}
