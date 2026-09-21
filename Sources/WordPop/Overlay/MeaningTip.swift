import AppKit
import SwiftUI
import AVFoundation

// MARK: - hover 释义卡（共享单窗口）

@MainActor
final class MeaningTipController {

    /// 窗口四周留给投影的余量（否则投影会被窗口边界裁成方板）
    static let tipMargin: CGFloat = 44

    private let window: NSPanel
    private var speaker: WordSpeaker?

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 90),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        window = panel
    }

    func show(entry: WordEntry, appearance: BubbleAppearance, anchorFrame: CGRect, screen: NSScreen?) {
        let card = Self.tipSize(entry: entry)
        let margin = Self.tipMargin
        let windowSize = CGSize(width: card.width + margin * 2, height: card.height + margin * 2)
        let screenFrame = (screen ?? NSScreen.main)?.visibleFrame ?? anchorFrame

        // 卡片自身的位置（左下原点），窗口再按 margin 外扩，保证投影不被裁切
        var cardX = anchorFrame.minX
        var cardBottom: CGFloat
        if anchorFrame.minY - 12 - card.height >= screenFrame.minY {
            cardBottom = anchorFrame.minY - 12 - card.height
        } else {
            cardBottom = min(anchorFrame.maxY + 12, screenFrame.maxY - card.height)
        }
        cardX = max(screenFrame.minX + 4, min(cardX, screenFrame.maxX - card.width - 4))

        window.setFrame(NSRect(x: cardX - margin,
                               y: cardBottom - margin,
                               width: windowSize.width,
                               height: windowSize.height),
                        display: false)

        let speaker = WordSpeaker()
        self.speaker = speaker

        let content = MeaningTipView(entry: entry,
                                     accent: appearance.accent,
                                     speaker: speaker,
                                     width: card.width)
            .frame(width: card.width, height: card.height)
            .padding(margin)
        let hosting = TransparentHostingView(rootView: content)
        hosting.frame = NSRect(origin: .zero, size: windowSize)
        window.contentView = hosting
        window.orderFrontRegardless()
    }

    func hide() {
        window.orderOut(nil)
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
        let height = ceil(16 + wordH + 8 + textH + 14)
        return CGSize(width: width, height: height)
    }
}

// MARK: - 释义卡内容

struct MeaningTipView: View {
    let entry: WordEntry
    let accent: Color
    @ObservedObject var speaker: WordSpeaker
    let width: CGFloat

    var body: some View {
        ZStack {
            // 同样避免 .ultraThinMaterial 的矩形底噪，使用自适应半透明底 + 渐变高光
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.94))
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
            }
            .padding(.horizontal, 16)
            .padding(.top, 15)
            .padding(.bottom, 13)
        }
        .shadow(color: .black.opacity(0.22), radius: 16, x: 0, y: 8)
        .frame(width: width)
        .allowsHitTesting(true)
    }

    @ViewBuilder
    private var speakButton: some View {
        Button {
            speaker.toggle(word: entry.word)
        } label: {
            ZStack {
                Circle().fill(speaker.isSpeaking ? accent.opacity(0.28) : accent.opacity(0.14))
                Image(systemName: speaker.isSpeaking ? "speaker.wave.2.fill" : "speaker.wave.2")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .frame(width: 26, height: 26)
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
