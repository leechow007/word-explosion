import AppKit
import SwiftUI
import AVFoundation

// MARK: - hover 释义卡（投影窗口 + 卡片窗口分离：投影不挡点击，卡片本体可交互）

@MainActor
final class MeaningTipController {

    /// 投影窗口相对卡片的余量（越大投影越完整，但窗口本身鼠标穿透，不影响点击）
    static let tipMargin: CGFloat = 44

    private let cardWindow: NSPanel
    private let shadowWindow: NSPanel
    private var speaker: WordSpeaker?

    /// 光标是否停在卡片上（由卡片视图上报，用于"够得到小喇叭"）
    var onHoverChange: ((Bool) -> Void)?
    private(set) var isHovered = false

    init() {
        cardWindow = Self.makePanel(interactive: true)
        shadowWindow = Self.makePanel(interactive: false)
    }

    private static func makePanel(interactive: Bool) -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 240, height: 100),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = !interactive
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = interactive   // 让卡片能收到 hover 事件
        panel.animationBehavior = .none
        return panel
    }

    func show(entry: WordEntry,
              appearance: BubbleAppearance,
              anchorFrame: CGRect,
              screen: NSScreen?,
              onMark: @escaping (WordMarkState) -> Void) {
        let card = Self.tipSize(entry: entry)
        let margin = Self.tipMargin
        let screenFrame = (screen ?? NSScreen.main)?.visibleFrame ?? anchorFrame

        // 卡片位置（左下原点）：优先放在词泡下方，空间不足则放上方
        var cardX = anchorFrame.minX
        var cardBottom: CGFloat
        if anchorFrame.minY - 12 - card.height >= screenFrame.minY {
            cardBottom = anchorFrame.minY - 12 - card.height
        } else {
            cardBottom = min(anchorFrame.maxY + 12, screenFrame.maxY - card.height)
        }
        cardX = max(screenFrame.minX + 4, min(cardX, screenFrame.maxX - card.width - 4))

        // 卡片窗口：精确等于卡片大小（不留隐形拦点击区域）
        cardWindow.setFrame(NSRect(x: cardX, y: cardBottom, width: card.width, height: card.height), display: false)
        // 投影窗口：外扩 margin，鼠标完全穿透
        shadowWindow.setFrame(NSRect(x: cardX - margin, y: cardBottom - margin,
                                     width: card.width + margin * 2,
                                     height: card.height + margin * 2),
                              display: false)

        let speaker = WordSpeaker()
        self.speaker = speaker

        let cardContent = MeaningTipView(entry: entry,
                                         accent: appearance.accent,
                                         speaker: speaker,
                                         width: card.width,
                                         onMark: onMark)
            .frame(width: card.width, height: card.height)
            .onHover { [weak self] hovering in
                guard let self else { return }
                self.isHovered = hovering
                self.onHoverChange?(hovering)
            }
        let cardHosting = TransparentHostingView(rootView: cardContent)
        cardHosting.frame = NSRect(origin: .zero, size: card)
        cardWindow.contentView = cardHosting

        let shadowContent = TipShadowView(cardSize: card)
            .frame(width: card.width + margin * 2, height: card.height + margin * 2)
        let shadowHosting = TransparentHostingView(rootView: shadowContent)
        shadowHosting.frame = NSRect(origin: .zero,
                                     size: CGSize(width: card.width + margin * 2,
                                                  height: card.height + margin * 2))
        shadowWindow.contentView = shadowHosting

        shadowWindow.orderFrontRegardless()
        cardWindow.orderFrontRegardless()
    }

    func hide() {
        isHovered = false
        cardWindow.orderOut(nil)
        shadowWindow.orderOut(nil)
        speaker = nil
    }

    /// 卡片本体尺寸（不含投影余量）
    static func tipSize(entry: WordEntry) -> CGSize {
        let width: CGFloat = 236
        let hPad: CGFloat = 16
        let innerW = width - hPad * 2

        let wordFont = NSFont.systemFont(ofSize: 19, weight: .semibold)
        let wordH = (entry.word as NSString).size(withAttributes: [.font: wordFont]).height

        let meaningFont = NSFont.systemFont(ofSize: 13.5)
        var textH: CGFloat = 20
        if !entry.meaning.isEmpty {
            let rect = (entry.meaning as NSString).boundingRect(
                with: CGSize(width: innerW, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin],
                attributes: [.font: meaningFont]
            )
            textH = max(20, min(rect.height, 94))   // 最多约 5 行，兼顾长释义（如雅思词条）
        }
        // 底部标记按钮行：26pt 按钮 + 间距
        let height = ceil(16 + wordH + 8 + textH + 10 + 26 + 12)
        return CGSize(width: width, height: height)
    }
}

// MARK: - 投影（独立穿透窗口，避免被卡片窗口裁成方板）

private struct TipShadowView: View {
    let cardSize: CGSize

    var body: some View {
        RoundedRectangle(cornerRadius: 15, style: .continuous)
            .fill(Color.black.opacity(0.22))
            .frame(width: cardSize.width, height: cardSize.height)
            .blur(radius: 16)
            .offset(y: 8)
            .padding(MeaningTipController.tipMargin)
            .allowsHitTesting(false)
    }
}

// MARK: - 释义卡内容

struct MeaningTipView: View {
    let entry: WordEntry
    let accent: Color
    @ObservedObject var speaker: WordSpeaker
    let width: CGFloat
    let onMark: (WordMarkState) -> Void
    @State private var hoveredMark: WordMarkState?

    var body: some View {
        ZStack {
            // 避免 .ultraThinMaterial 的矩形底噪，使用自适应半透明底 + 渐变高光
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.96))
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(
                    LinearGradient(stops: [
                        .init(color: .white.opacity(0.22), location: 0.00),
                        .init(color: .clear, location: 0.55)
                    ], startPoint: .top, endPoint: .bottom)
                )
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.85), .white.opacity(0.25)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
        }
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(LinearGradient(colors: [accent.opacity(0.25), .clear],
                                     startPoint: .top, endPoint: .center))
                .blendMode(.plusLighter)
        }
        .overlay {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 10) {
                    Text(entry.word)
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppPalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    speakButton
                }
                Text(entry.meaning.isEmpty ? "(暂无释义)" : entry.meaning)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(AppPalette.ink.opacity(0.72))
                    .lineSpacing(2.5)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                markRow
            }
            .padding(.horizontal, 16)
            .padding(.top, 15)
            .padding(.bottom, 12)
        }
        .frame(width: width)
        .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .allowsHitTesting(true)
        .help("点击 🔊 发音（双击词泡可点爆）")
    }

    /// 底部标记按钮行（⌥/⇧ 双击的等价入口，鼠标用户也能用）
    private var markRow: some View {
        HStack(spacing: 8) {
            markChip(title: "不认识", symbol: "questionmark.circle.fill",
                     tint: accent, state: .unknown)
            markChip(title: "已掌握", symbol: "star.circle.fill",
                     tint: AppPalette.accent("#30D158"), state: .mastered)
            Spacer(minLength: 0)
        }
    }

    private func markChip(title: String, symbol: String, tint: Color, state: WordMarkState) -> some View {
        Button {
            onMark(state)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background {
                Capsule().fill(tint.opacity(hoveredMark == state ? 0.22 : 0.12))
            }
            .overlay {
                Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 0.8)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                hoveredMark = state
            } else if hoveredMark == state {
                hoveredMark = nil
            }
        }
        .help(state == .unknown
              ? "标记为生词：之后会更多出现（快捷键 ⌥ + 双击）"
              : "标记为已掌握：不再弹出（快捷键 ⇧ + 双击）")
    }

    @ViewBuilder
    private var speakButton: some View {        Button {
            speaker.toggle(word: entry.word)
        } label: {
            ZStack {
                Circle().fill(speaker.isSpeaking ? accent.opacity(0.28) : accent.opacity(0.14))
                Image(systemName: speaker.isSpeaking ? "speaker.wave.2.fill" : "speaker.wave.2")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .frame(width: 30, height: 30)          // 加大可点区域，便于命中
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .scaleEffect(speaker.isSpeaking ? 1.08 : 1)
        .animation(.easeInOut(duration: 0.3), value: speaker.isSpeaking)
        .accessibilityLabel("朗读 \(entry.word)")
    }
}

// MARK: - 单词朗读

final class WordSpeaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var isSpeaking = false
    private let synth = AVSpeechSynthesizer()
    private let voice: AVSpeechSynthesisVoice?

    override init() {
        voice = AVSpeechSynthesisVoice(language: "en-US")
            ?? AVSpeechSynthesisVoice(language: "en-GB")
            ?? AVSpeechSynthesisVoice(language: "en")
        super.init()
        synth.delegate = self
    }

    func toggle(word: String) {
        if isSpeaking {
            synth.stopSpeaking(at: .immediate)
            isSpeaking = false
        } else {
            speak(word: word)
        }
    }

    func speak(word: String) {
        synth.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: word)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85
        isSpeaking = true
        synth.speak(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeaking = false
    }
}
