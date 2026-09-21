import AppKit
import SwiftUI

// MARK: - 标记反馈提示（鼠标穿透、自动淡出，不打断操作）

final class ToastFadeState: ObservableObject {
    @Published var opacity: Double = 0
}

@MainActor
final class MarkToastController {

    private let window: NSPanel
    private let fade = ToastFadeState()
    private var hideTask: Task<Void, Never>?

    init() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 240, height: 80),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 4)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.animationBehavior = .none
        window = panel
    }

    func show(text: String, symbol: String, accent: Color, at point: CGPoint) {
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let textWidth = (text as NSString).size(withAttributes: [.font: font]).width
        let capsule = CGSize(width: ceil(textWidth) + 62, height: 34)
        let margin: CGFloat = 22
        let size = CGSize(width: capsule.width + margin * 2, height: capsule.height + margin * 2)

        window.setFrame(NSRect(x: point.x - size.width / 2,
                               y: point.y - size.height / 2,
                               width: size.width,
                               height: size.height),
                        display: false)

        let content = MarkToastView(text: text, symbol: symbol, accent: accent, fade: fade)
            .frame(width: size.width, height: size.height)
        let hosting = TransparentHostingView(rootView: content)
        hosting.frame = NSRect(origin: .zero, size: size)
        window.contentView = hosting
        window.orderFrontRegardless()

        withAnimation(.easeOut(duration: 0.18)) { fade.opacity = 1 }

        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_250_000_000)
            guard let self, !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.35)) { self.fade.opacity = 0 }
            try? await Task.sleep(nanoseconds: 420_000_000)
            guard !Task.isCancelled else { return }
            self.window.orderOut(nil)
        }
    }

    func hideImmediately() {
        hideTask?.cancel()
        fade.opacity = 0
        window.orderOut(nil)
    }
}

private struct MarkToastView: View {
    let text: String
    let symbol: String
    let accent: Color
    @ObservedObject var fade: ToastFadeState

    var body: some View {
        ZStack {
            Capsule().fill(Color(nsColor: .windowBackgroundColor).opacity(0.94))
            Capsule().fill(
                LinearGradient(stops: [
                    .init(color: .white.opacity(0.18), location: 0.0),
                    .init(color: .clear, location: 0.6)
                ], startPoint: .top, endPoint: .bottom)
            )
            Capsule().strokeBorder(accent.opacity(0.45), lineWidth: 1)
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(accent)
                Text(text)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppPalette.ink)
            }
            .padding(.horizontal, 18)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.20), radius: 12, y: 6)
        .padding(22)
        .opacity(fade.opacity)
        .scaleEffect(0.96 + 0.04 * fade.opacity)
        .allowsHitTesting(false)
    }
}
