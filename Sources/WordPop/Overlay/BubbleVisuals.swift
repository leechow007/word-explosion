import SwiftUI
import AppKit

// MARK: - 词泡运动状态（词泡窗口与发光窗口共享，保证任何时刻都严丝合缝对齐）

final class BubbleMotionState: ObservableObject {
    @Published var bobOffset: CGFloat = 0        // 上下浮动
    @Published var capsuleScale: CGFloat = 0.55  // 入场/悬停/点爆的综合缩放
    @Published var appeared = false              // 词泡本体不透明度
    @Published var glowOpacity: Double = 0       // 发光不透明度
}

// MARK: - 词泡胶囊视觉

struct BubbleCapsuleView: View {
    let appearance: BubbleAppearance
    let text: String
    var flash: Double = 0          // 点爆瞬间的白色闪光 0...1

    @Environment(\.colorScheme) private var colorScheme

    /// 晨雾主题在系统深色模式下自动切换为深色玻璃，保证文字对比度
    private var theme: BubbleTheme {
        appearance.theme == .glassLight && colorScheme == .dark ? .glassDark : appearance.theme
    }

    var body: some View {
        ZStack {
            fill
            tintOverlay
            innerStrokes
            Text(text)
                .font(appearance.font)
                .foregroundStyle(textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.45)
                .padding(.horizontal, WordMetrics.bubblePadding(appearance: appearance).h - 6)
                .padding(.vertical, WordMetrics.bubblePadding(appearance: appearance).v - 5)
        }
        .compositingGroup()
        .overlay(
            Capsule()
                .fill(.white.opacity(flash))
                .allowsHitTesting(false)
        )
        .padding(WordMetrics.bubbleMargin(fontSize: appearance.fontSize))
    }

    private var textColor: Color {
        switch theme {
        case .glassLight:
            return appearance.background.relativeLuminance > 0.45 ? AppPalette.ink.opacity(0.92) : .white.opacity(0.95)
        case .glassDark:
            return appearance.background.relativeLuminance > 0.6 ? AppPalette.ink.opacity(0.92) : .white.opacity(0.95)
        case .aurora:
            return .white
        }
    }

    private var fillOpacity: Double {
        min(max(appearance.fillOpacity, 0.05), 1.0)
    }

    // MARK: 基础填充（用户可自定义背景色与不透明度）

    @ViewBuilder
    private var fill: some View {
        switch theme {
        case .glassLight:
            // 不使用 .ultraThinMaterial：系统毛玻璃的模糊区域是矩形，圆角裁不掉，
            // 会在胶囊外露出一层方形底噪。这里用可控的渐变半透明填充。
            Capsule().fill(
                LinearGradient(stops: [
                    .init(color: appearance.background.opacity(min(1, fillOpacity * 1.12)), location: 0.00),
                    .init(color: appearance.background.opacity(min(1, fillOpacity * 0.95)), location: 0.48),
                    .init(color: appearance.background.opacity(min(1, fillOpacity * 0.82)), location: 1.00)
                ], startPoint: .top, endPoint: .bottom)
            )
        case .glassDark:
            ZStack {
                Capsule().fill(
                    LinearGradient(colors: [.black.opacity(0.40), .black.opacity(0.28)],
                                   startPoint: .top, endPoint: .bottom)
                )
                Capsule().fill(appearance.background.opacity(min(1, fillOpacity * 0.45)))
            }
        case .aurora:
            Capsule().fill(
                LinearGradient(colors: [
                    appearance.accent.opacity(min(1, fillOpacity + 0.35)),
                    AppPalette.partner(for: appearance.accentHex).opacity(min(1, fillOpacity + 0.25))
                ], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
        }
    }

    /// 多段柔和渐变：上高光 → 中间过渡 → 底部微暗，避免两段式生硬断层
    @ViewBuilder
    private var tintOverlay: some View {
        switch theme {
        case .glassLight:
            Capsule().fill(
                LinearGradient(stops: [
                    .init(color: .white.opacity(0.16), location: 0.00),
                    .init(color: .clear, location: 0.42),
                    .init(color: appearance.accent.opacity(0.07), location: 1.00)
                ], startPoint: .top, endPoint: .bottom)
            )
        case .glassDark:
            Capsule().fill(
                LinearGradient(stops: [
                    .init(color: .white.opacity(0.14), location: 0.00),
                    .init(color: .clear, location: 0.45),
                    .init(color: .black.opacity(0.14), location: 1.00)
                ], startPoint: .top, endPoint: .bottom)
            )
        case .aurora:
            Capsule().fill(
                LinearGradient(stops: [
                    .init(color: .white.opacity(0.28), location: 0.00),
                    .init(color: .clear, location: 0.42),
                    .init(color: .black.opacity(0.10), location: 1.00)
                ], startPoint: .top, endPoint: .bottom)
            )
        }
    }

    private var innerStrokes: some View {
        ZStack {
            Capsule().strokeBorder(
                LinearGradient(stops: [
                    .init(color: .white.opacity(0.62), location: 0.00),
                    .init(color: .white.opacity(0.08), location: 1.00)
                ], startPoint: .top, endPoint: .bottom),
                lineWidth: 0.7
            )
            Capsule().strokeBorder(
                LinearGradient(stops: [
                    .init(color: appearance.accent.opacity(0.28), location: 0.00),
                    .init(color: appearance.accent.opacity(0.05), location: 1.00)
                ], startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 1.0
            )
        }
    }
}

// MARK: - 柔光层（投影 + 外发光，全部在 Canvas 的整窗图层内模糊，永不裁切）

struct BubbleGlowView: View {
    let appearance: BubbleAppearance
    let capsuleSize: CGSize
    @ObservedObject var motion: BubbleMotionState

    private struct Halo {
        let blur: CGFloat
        let expand: CGFloat
        let opacity: Double
    }

    private let halos: [Halo] = [
        Halo(blur: 10, expand: 0, opacity: 0.30),
        Halo(blur: 26, expand: 3, opacity: 0.15),
        Halo(blur: 46, expand: 7, opacity: 0.08)
    ]

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(x: (size.width - capsuleSize.width) / 2,
                              y: (size.height - capsuleSize.height) / 2,
                              width: capsuleSize.width,
                              height: capsuleSize.height)

            // 1) 投影（放在这里绘制，避免在词泡小窗口里被裁成矩形）
            let shadowRect = rect.offsetBy(dx: 0, dy: 3)
            context.drawLayer { inner in
                inner.addFilter(.blur(radius: 9))
                inner.opacity = 0.20
                inner.fill(Path(roundedRect: shadowRect, cornerRadius: shadowRect.height / 2),
                           with: .color(.black))
            }

            // 2) 彩色柔光：三层由紧到松，形成连续衰减
            let gradient = Gradient(colors: [
                appearance.accent,
                AppPalette.partner(for: appearance.accentHex)
            ])
            for halo in halos {
                let expanded = rect.insetBy(dx: -halo.expand, dy: -halo.expand)
                let path = Path(roundedRect: expanded, cornerRadius: expanded.height / 2)
                context.drawLayer { inner in
                    inner.addFilter(.blur(radius: halo.blur))
                    inner.opacity = halo.opacity
                    inner.fill(path, with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: expanded.minX, y: expanded.minY),
                        endPoint: CGPoint(x: expanded.maxX, y: expanded.maxY)
                    ))
                }
            }
        }
        // 与词泡共享同一套运动状态，任何时刻都对齐
        .scaleEffect(motion.capsuleScale)
        .offset(y: motion.bobOffset)
        .opacity(motion.glowOpacity)
        .allowsHitTesting(false)
    }
}
