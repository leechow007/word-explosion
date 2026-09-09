import AppKit
import SwiftUI

// MARK: - 单个词泡窗口控制器

@MainActor
final class BubbleController: NSObject, ObservableObject, Identifiable {

    enum Phase: Equatable {
        case entering
        case idle
        case bursting
        case drifting
    }

    @Published var phase: Phase = .entering
    @Published var hovered = false

    let id = UUID()
    let entry: WordEntry
    let appearance: BubbleAppearance
    let windowFrame: CGRect          // 屏幕坐标（左下原点）
    let window: NSPanel

    weak var engine: OverlayEngine?

    private var ttlTask: Task<Void, Never>?
    private var popped = false

    init(entry: WordEntry, appearance: BubbleAppearance, windowFrame: CGRect) {
        self.entry = entry
        self.appearance = appearance
        self.windowFrame = windowFrame

        let panel = NSPanel(
            contentRect: windowFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.acceptsMouseMovedEvents = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        panel.animationBehavior = .none
        self.window = panel

        super.init()

        let contentView = BubbleContentView(controller: self)
            .frame(width: windowFrame.width, height: windowFrame.height)
        let hosting = NSHostingView(rootView: contentView)
        hosting.frame = NSRect(origin: .zero, size: windowFrame.size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
    }

    func orderFront() {
        window.orderFrontRegardless()
        // 入场动画在 SwiftUI 中由 phase 驱动，这里延迟 0.6s 进入 idle 并开始计时
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 620_000_000)
            guard let self, self.phase == .entering else { return }
            self.phase = .idle
        }
    }

    func setTTL(_ ttl: TimeInterval) {
        guard ttl > 0 else { return }
        ttlTask?.cancel()
        ttlTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(ttl * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            if self.phase == .idle {
                self.driftAway(quick: false)
            }
        }
    }

    func setHover(_ on: Bool) {
        guard phase == .idle || phase == .entering else {
            if on == false { engine?.scheduleMeaningTip(for: self, show: false) }
            return
        }
        hovered = on
        engine?.scheduleMeaningTip(for: self, show: on)
    }

    // MARK: 双击点爆

    func pop() {
        guard !popped, phase == .idle || phase == .entering else { return }
        popped = true
        ttlTask?.cancel()
        engine?.scheduleMeaningTip(for: self, show: false)
        phase = .bursting

        if engine?.hapticsEnabled ?? true {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }

        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        engine?.burstFX(at: center, appearance: appearance, anchorScreen: window.screen)

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard let self else { return }
            self.window.orderOut(nil)
            self.engine?.remove(self, counted: true)
        }
    }

    // MARK: 飘走

    func driftAway(quick: Bool) {
        guard phase != .drifting, phase != .bursting, !popped else { return }
        ttlTask?.cancel()
        phase = .drifting
        let delay: UInt64 = quick ? 400_000_000 : 800_000_000
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard let self else { return }
            self.window.orderOut(nil)
            self.engine?.remove(self, counted: false)
        }
    }

    func hide() {
        window.orderOut(nil)
    }

    deinit {
        ttlTask?.cancel()
    }
}

// MARK: - 词泡 SwiftUI 内容

struct BubbleContentView: View {
    @ObservedObject var controller: BubbleController

    @State private var appeared = false
    @State private var bobOffset: CGFloat = 0
    @State private var hoverScale: CGFloat = 1

    var body: some View {
        ZStack {
            bubbleBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scaleEffect(scale)
        .opacity(opacity)
        .offset(x: 0, y: yOffset)
        .onAppear {
            guard !appeared else { return }
            appeared = true
            let amplitude: CGFloat = controller.appearance.fontSize * 0.16
            let duration = Double.random(in: 2.8 ... 4.4)
            withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
                bobOffset = amplitude
            }
        }
        .onChange(of: controller.phase) { _, newPhase in
            if newPhase == .drifting {
                withAnimation(.easeInOut(duration: 0.72)) { appeared = false }
                withAnimation(.easeOut(duration: 0.25)) { bobOffset = 0 }
            }
        }
        .onHover { hovering in
            controller.setHover(hovering)
            if hovering {
                withAnimation(.easeOut(duration: 0.14)) { hoverScale = 1.04 }
            } else {
                withAnimation(.easeOut(duration: 0.2)) { hoverScale = 1 }
            }
        }
        .onTapGesture(count: 2) {
            controller.pop()
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.68), value: appeared)
        .animation(.easeOut(duration: 0.09), value: isBursting)
        .animation(.easeInOut(duration: 0.72), value: isDrifting)
    }

    // MARK: Visual states

    private var isBursting: Bool { controller.phase == .bursting }
    private var isDrifting: Bool { controller.phase == .drifting }

    private var scale: CGFloat {
        if isDrifting { return 0.9 }
        if !appeared { return 0.55 }
        return hoverScale * (isBursting ? 1.18 : 1.0)
    }

    private var opacity: Double {
        if isDrifting { return 0 }
        return appeared ? 1 : 0
    }

    private var yOffset: CGFloat {
        if isDrifting { return -52 }
        return bobOffset
    }

    // MARK: 外观

    private var capsuleFill: some View {
        Group {
            switch controller.appearance.theme {
            case .glassLight:
                Capsule().fill(.ultraThinMaterial)
            case .glassDark:
                Capsule().fill(
                    LinearGradient(colors: [.black.opacity(0.46), .black.opacity(0.30)],
                                   startPoint: .top, endPoint: .bottom)
                )
            case .aurora:
                Capsule().fill(
                    LinearGradient(colors: [controller.appearance.accent.opacity(0.92),
                                            AppPalette.partner(for: controller.appearance.accentHex)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            }
        }
    }

    private var bubbleBody: some View {
        ZStack {
            capsuleFill
            // 内描边：顶部高光 + 强调色渐变
            Capsule().strokeBorder(
                LinearGradient(colors: [.white.opacity(0.75), .white.opacity(0.05)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 1.0
            )
            Capsule().strokeBorder(
                LinearGradient(colors: [controller.appearance.accent.opacity(0.42),
                                        controller.appearance.accent.opacity(0.10)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 1.3
            )
            Text(controller.entry.word)
                .font(controller.appearance.font)
                .foregroundStyle(controller.appearance.textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.45)
                .padding(.horizontal, WordMetrics.bubblePadding(appearance: controller.appearance).h - 6)
                .padding(.vertical, WordMetrics.bubblePadding(appearance: controller.appearance).v - 5)
        }
        .compositingGroup()
        .shadow(color: controller.appearance.accent.opacity(controller.appearance.glowOpacity),
                radius: controller.appearance.glowRadius, x: 0, y: 5)
        .shadow(color: .black.opacity(0.16), radius: 7, x: 0, y: 3)
        .overlay(
            Capsule().fill(.white.opacity(isBursting ? 0.9 : 0)).animation(.easeOut(duration: 0.1), value: isBursting)
                .allowsHitTesting(false)
        )
        .padding(ceil(max(10, controller.appearance.fontSize * 0.55)))
    }
}
