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

// MARK: - 外发光（独立鼠标穿透窗口内绘制，因此不会被裁切）

struct BubbleGlowView: View {
    let appearance: BubbleAppearance

    var body: some View {
        ZStack {
            // 三层由紧到松的模糊，形成连续衰减的柔光，避免出现"糊团"与色带
            glowLayer(blur: 10, opacity: 0.28, scale: 1.00)
            glowLayer(blur: 26, opacity: 0.14, scale: 1.02)
            glowLayer(blur: 46, opacity: 0.07, scale: 1.05)
        }
        .padding(WordMetrics.glowMargin)
        .allowsHitTesting(false)
    }

    private func glowLayer(blur: CGFloat, opacity: Double, scale: CGFloat) -> some View {
        Capsule()
            .fill(
                LinearGradient(colors: [
                    appearance.accent.opacity(opacity),
                    AppPalette.partner(for: appearance.accentHex).opacity(opacity * 0.55)
                ], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .scaleEffect(scale)
            .blur(radius: blur)
    }
}
