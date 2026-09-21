import AppKit
import SwiftUI

// MARK: - 开发预览：离屏渲染词泡视觉，便于快速核对发光/渐变是否丝滑
// 用法：WORDPOP_RENDER=<输出目录> ./dist/词爆.app/Contents/MacOS/WordPop

@MainActor
enum DevPreview {

    static func runIfRequested() -> Bool {
        if runCaptureIfRequested() { return true }
        guard let dir = ProcessInfo.processInfo.environment["WORDPOP_RENDER"], !dir.isEmpty else {
            return false
        }
        let outDir = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let walls: [(name: String, colors: [Color])] = [
            ("light", [Color(hex: "E9EDF7"), Color(hex: "DCE2F1"), Color(hex: "F5F1EA")]),
            ("dark", [Color(hex: "181B29"), Color(hex: "22263F"), Color(hex: "12141F")])
        ]
        let accents = ["#5E5CE6", "#FF6482", "#30D158"]

        var count = 0
        for theme in BubbleTheme.allCases {
            for wall in walls {
                let appearance = BubbleAppearance(
                    theme: theme,
                    accentHex: accents[0],
                    accent: AppPalette.accent(accents[0]),
                    fontSize: 23,
                    serif: false
                )
                let view = BubbleScenePreview(appearance: appearance,
                                              words: ["indecent", "serendipity", "candid"],
                                              wallColors: wall.colors)
                let name = "bubble-\(theme.subtitle.replacingOccurrences(of: " ", with: "-").lowercased())-\(wall.name).png"
                if render(view, to: outDir.appendingPathComponent(name)) { count += 1 }
            }
        }

        // 强调色对照
        for (i, hex) in accents.enumerated() {
            let appearance = BubbleAppearance(theme: .glassLight, accentHex: hex,
                                              accent: AppPalette.accent(hex), fontSize: 23, serif: false)
            let view = BubbleScenePreview(appearance: appearance, words: ["resilient"], wallColors: walls[0].colors)
            if render(view, to: outDir.appendingPathComponent("accent-\(i).png")) { count += 1 }
        }

        // 系统深色模式下的自动适配（晨雾 → 深色玻璃）
        let darkModeAppearance = BubbleAppearance(theme: .glassLight, accentHex: accents[0],
                                                  accent: AppPalette.accent(accents[0]), fontSize: 23, serif: false)
        if render(BubbleScenePreview(appearance: darkModeAppearance,
                                     words: ["indecent", "serendipity"],
                                     wallColors: walls[1].colors)
                    .environment(\.colorScheme, .dark),
                  to: outDir.appendingPathComponent("darkmode-adapt.png")) { count += 1 }

        FileHandle.standardError.write(Data("[WordPop] 预览渲染完成 \(count) 张 → \(outDir.path)\n".utf8))

        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            NSApp.terminate(nil)
        }
        return true
    }

    /// 真实渲染捕获：在屏幕中央生成一个词泡，等待入场完成后捕获自身窗口区域
    private static func runCaptureIfRequested() -> Bool {
        guard let path = ProcessInfo.processInfo.environment["WORDPOP_CAPTURE"], !path.isEmpty else {
            return false
        }
        guard let screen = NSScreen.main else { return false }

        let outURL = URL(fileURLWithPath: path)
        let appearance = BubbleAppearance.from(settings: AppState.shared.settings)
        let word = ProcessInfo.processInfo.environment["WORDPOP_CAPTURE_WORD"] ?? "indecent"
        let size = WordMetrics.windowSize(word: word, appearance: appearance)
        let frame = NSRect(x: screen.frame.midX - size.width / 2,
                           y: screen.frame.midY - size.height / 2,
                           width: size.width,
                           height: size.height)

        let controller = BubbleController(entry: WordEntry(word: word, meaning: ""),
                                          appearance: appearance,
                                          windowFrame: frame)
        controller.orderFront()

        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if let image = controller.debugCompositeSnapshot(),
               let tiff = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(),
                                                         withIntermediateDirectories: true)
                try? png.write(to: outURL)
                FileHandle.standardError.write(Data("[WordPop] 真实效果截图: \(outURL.path)\n".utf8))
            } else {
                FileHandle.standardError.write(Data("[WordPop] 截图失败（系统可能限制窗口捕获）\n".utf8))
            }
            controller.hide()
            try? await Task.sleep(nanoseconds: 250_000_000)
            NSApp.terminate(nil)
        }
        return true
    }

    private static func render(_ view: some View, to url: URL) -> Bool {        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try png.write(to: url)
            return true
        } catch {
            FileHandle.standardError.write(Data("[WordPop] 渲染失败 \(url.lastPathComponent): \(error)\n".utf8))
            return false
        }
    }
}

/// 与真实窗口层级一致：壁纸 → 发光窗口 → 词泡窗口
private struct BubbleScenePreview: View {
    let appearance: BubbleAppearance
    let words: [String]
    let wallColors: [Color]

    private let previewFade: GlowFadeState = {
        let state = GlowFadeState()
        state.opacity = 1
        return state
    }()

    var body: some View {
        ZStack {
            LinearGradient(colors: wallColors, startPoint: .topLeading, endPoint: .bottomTrailing)

            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                let capsule = WordMetrics.capsuleSize(word: word, appearance: appearance)
                let bubbleSize = WordMetrics.windowSize(capsule: capsule, fontSize: appearance.fontSize)
                let glowSize = CGSize(width: capsule.width + WordMetrics.glowMargin * 2,
                                      height: capsule.height + WordMetrics.glowMargin * 2)
                let dx = CGFloat(index) * -34
                let dy = CGFloat(index) * 62 - 62

                ZStack {
                    BubbleGlowView(appearance: appearance, capsuleSize: capsule, fade: previewFade)
                        .frame(width: glowSize.width, height: glowSize.height)
                    BubbleCapsuleView(appearance: appearance, text: word)
                        .frame(width: bubbleSize.width, height: bubbleSize.height)
                }
                .offset(x: dx, y: dy)
                .scaleEffect(1.0 - CGFloat(index) * 0.06)
            }
        }
        .frame(width: 620, height: 420)
    }
}
