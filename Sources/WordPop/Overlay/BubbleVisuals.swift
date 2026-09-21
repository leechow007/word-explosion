import SwiftUI
import AppKit

// MARK: - 词泡胶囊视觉（发光单独放在 BubbleGlowView）

struct BubbleCapsuleView: View {
    let appearance: BubbleAppearance
    let text: String
    var flash: Double = 0          // 点爆瞬间的白色闪光 0...1
    var showShadow: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    /// 晨雾主题在系统深色模式下自动切换为深色玻璃，保证文字对比度
    private var theme: BubbleTheme {
        appearance.theme == .glassLight && colorScheme == .dark ? .glassDark : appearance.theme
    }

    private var textColor: Color {
        switch theme {
        case .glassLight: return AppPalette.ink.opacity(0.92)
        case .glassDark: return .white.opacity(0.95)
        case .aurora: return .white
        }
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
        .shadow(color: .black.opacity(showShadow ? 0.16 : 0), radius: 6, x: 0, y: 3)
        .padding(WordMetrics.bubbleMargin(fontSize: appearance.fontSize))
    }

    // MARK: 基础填充

    @ViewBuilder
    private var fill: some View {
        switch theme {
        case .glassLight:
            // 不使用 .ultraThinMaterial：系统毛玻璃的模糊区域是矩形，圆角裁不掉，
            // 会在胶囊外露出一层方形底噪。这里用半透明白渐变，结构上杜绝该问题。
            Capsule().fill(
                LinearGradient(stops: [
                    .init(color: .white.opacity(0.62), location: 0.00),
                    .init(color: .white.opacity(0.52), location: 0.45),
                    .init(color: .white.opacity(0.44), location: 1.00)
                ], startPoint: .top, endPoint: .bottom)
            )
        case .glassDark:
            Capsule().fill(
                LinearGradient(colors: [.black.opacity(0.44), .black.opacity(0.30)],
                               startPoint: .top, endPoint: .bottom)
            )
        case .aurora:
            Capsule().fill(
                LinearGradient(colors: [appearance.accent.opacity(0.94),
                                        AppPalette.partner(for: appearance.accentHex)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
        }
    }

    /// 多段柔和渐变：让上高光→中间过渡→底部微暗，避免两段式生硬断层
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

// MARK: - 外发光（在 Canvas 图层内做模糊：既不裁切，也不会出现矩形边界）

/// 发光淡入淡出状态（在 SwiftUI 内部做动画，避免对透明窗口做 NSWindow.alphaValue 动画）
final class GlowFadeState: ObservableObject {
    @Published var opacity: Double = 0
}

struct BubbleGlowView: View {
    let appearance: BubbleAppearance
    let capsuleSize: CGSize
    @ObservedObject var fade: GlowFadeState

    private struct Layer {
        let blur: CGFloat
        let expand: CGFloat
        let opacity: Double
    }

    // 三层由紧到松的模糊：形成连续衰减的柔光
    private let layers: [Layer] = [
        Layer(blur: 10, expand: 0, opacity: 0.30),
        Layer(blur: 26, expand: 3, opacity: 0.15),
        Layer(blur: 46, expand: 7, opacity: 0.08)
    ]

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(x: (size.width - capsuleSize.width) / 2,
                              y: (size.height - capsuleSize.height) / 2,
                              width: capsuleSize.width,
                              height: capsuleSize.height)
            let gradient = Gradient(colors: [
                appearance.accent,
                AppPalette.partner(for: appearance.accentHex)
            ])

            for layer in layers {
                let expanded = rect.insetBy(dx: -layer.expand, dy: -layer.expand)
                let path = Path(roundedRect: expanded, cornerRadius: expanded.height / 2)
                context.drawLayer { inner in
                    inner.addFilter(.blur(radius: layer.blur))
                    inner.opacity = layer.opacity
                    inner.fill(path, with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: expanded.minX, y: expanded.minY),
                        endPoint: CGPoint(x: expanded.maxX, y: expanded.maxY)
                    ))
                }
            }
        }
        .opacity(fade.opacity)
        .allowsHitTesting(false)
    }
}
