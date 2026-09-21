import SwiftUI
import AppKit

// MARK: - Color helpers

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexString.hasPrefix("#") { hexString.removeFirst() }
        Scanner(string: hexString).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Palette

enum AppPalette {
    static let accentOptions: [(name: String, hex: String)] = [
        ("靛蓝", "#5E5CE6"),
        ("清蓝", "#0A84FF"),
        ("青碧", "#32ADE6"),
        ("湖绿", "#40C8BE"),
        ("薄荷", "#30D158"),
        ("樱花粉", "#FF6482"),
        ("紫罗兰", "#BF5AF2"),
        ("落日橙", "#FF9F0A")
    ]

    static let ink = Color(hex: "1B1D29")
    static let auroraPartner = Color(hex: "FF8FB2")

    static func accent(_ hex: String) -> Color {
        Color(hex: hex)
    }

    static func partner(for hex: String) -> Color {
        // Aurora 渐变配对的第二色：暖色强调色配紫罗兰，冷色强调色配樱花粉
        let warm = ["#FF9F0A", "#FF6482", "#30D158", "#40C8BE"]
        if warm.contains(hex) {
            return Color(hex: "#BF5AF2")
        }
        return Color(hex: "#FF8FB2")
    }
}

// MARK: - Bubble appearance

struct BubbleAppearance: Equatable {
    var theme: BubbleTheme
    var accentHex: String
    var accent: Color
    var fontSize: CGFloat
    var serif: Bool

    static func from(settings: AppSettings) -> BubbleAppearance {
        BubbleAppearance(
            theme: settings.theme,
            accentHex: settings.accentHex,
            accent: AppPalette.accent(settings.accentHex),
            fontSize: CGFloat(settings.fontSize.rawValue),
            serif: settings.serifFont
        )
    }

    var font: Font {
        if serif {
            return .system(size: fontSize, weight: .semibold, design: .serif)
        }
        return .system(size: fontSize, weight: .semibold, design: .rounded)
    }

    var textColor: Color {
        switch theme {
        case .glassLight: return AppPalette.ink.opacity(0.92)
        case .glassDark: return Color.white.opacity(0.95)
        case .aurora: return .white
        }
    }

    var glowRadius: CGFloat { theme == .aurora ? 16 : 12 }
    var glowOpacity: Double {
        switch theme {
        case .glassLight: return 0.5
        case .glassDark: return 0.35
        case .aurora: return 0.65
        }
    }
}

enum WordMetrics {
    static func measureFont(size: CGFloat, serif: Bool) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: .semibold)
        let design: NSFontDescriptor.SystemDesign = serif ? .serif : .rounded
        let descriptor = base.fontDescriptor.withDesign(design) ?? base.fontDescriptor
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    /// 词泡胶囊（不含阴影/浮动余量）的尺寸
    static func capsuleSize(word: String, appearance: BubbleAppearance) -> CGSize {
        let font = measureFont(size: appearance.fontSize, serif: appearance.serif)
        let textSize = (word as NSString).size(withAttributes: [.font: font])
        let padH = max(22, 14 + appearance.fontSize * 0.55)
        let padV = max(14, 12 + appearance.fontSize * 0.30)
        return CGSize(width: ceil(textSize.width) + padH * 2,
                      height: ceil(textSize.height) + padV * 2)
    }

    /// 词泡窗口相对胶囊的留白（只容纳自身很轻的投影，不再放发光）
    static func bubbleMargin(fontSize: CGFloat) -> CGFloat {
        ceil(max(12, fontSize * 0.6))
    }

    /// 发光窗口相对胶囊的余量（必须 ≥ 最大模糊半径 × 2，否则会被裁切出硬边）
    static let glowMargin: CGFloat = 104

    /// 词泡窗口尺寸 = 胶囊 + 阴影/浮动余量（视觉绘制空间）
    static func windowSize(capsule: CGSize, fontSize: CGFloat) -> CGSize {
        let margin = bubbleMargin(fontSize: fontSize)
        return CGSize(width: capsule.width + margin * 2,
                      height: capsule.height + margin * 2)
    }

    static func windowSize(word: String, appearance: BubbleAppearance) -> CGSize {
        windowSize(capsule: capsuleSize(word: word, appearance: appearance),
                   fontSize: appearance.fontSize)
    }

    static func bubblePadding(appearance: BubbleAppearance) -> (h: CGFloat, v: CGFloat) {
        (max(22, 14 + appearance.fontSize * 0.55),
         max(14, 12 + appearance.fontSize * 0.30))
    }
}
