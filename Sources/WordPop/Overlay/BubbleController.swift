import AppKit
import SwiftUI

// MARK: - 始终透明的宿主视图（防止 SwiftUI 宿主图层带上不透明底色）

final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }

    override func layout() {
        super.layout()
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
    }
}

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
    private let glowWindow: NSPanel

    weak var engine: OverlayEngine?

    /// 词泡与发光共享的运动状态（浮动/缩放完全同步）
    let motion = BubbleMotionState()
    /// 排查开关：WORDPOP_NO_GLOW=1 时不显示发光层
    private let showsGlow = ProcessInfo.processInfo.environment["WORDPOP_NO_GLOW"] != "1"
    private var ttlTask: Task<Void, Never>?
    private var popped = false
    private var clickMonitor: Any?
    private var lastClickModifiers: NSEvent.ModifierFlags = []

    init(entry: WordEntry, appearance: BubbleAppearance, windowFrame: CGRect) {
        self.entry = entry
        self.appearance = appearance
        self.windowFrame = windowFrame

        let margin = WordMetrics.bubbleMargin(fontSize: appearance.fontSize)
        let capsuleFrame = windowFrame.insetBy(dx: margin, dy: margin)
        let glowFrame = capsuleFrame.insetBy(dx: -WordMetrics.glowMargin, dy: -WordMetrics.glowMargin)

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

        // 发光层：独立窗口、鼠标完全穿透，只为更丝滑的大范围柔光（窗口留足余量避免裁切）
        let glowPanel = NSPanel(
            contentRect: glowFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        glowPanel.isOpaque = false
        glowPanel.backgroundColor = .clear
        glowPanel.hasShadow = false
        glowPanel.isReleasedWhenClosed = false
        glowPanel.hidesOnDeactivate = false
        glowPanel.ignoresMouseEvents = true
        glowPanel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue)
        glowPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        glowPanel.animationBehavior = .none
        self.glowWindow = glowPanel

        super.init()

        let contentView = BubbleContentView(controller: self, motion: motion)
            .frame(width: windowFrame.width, height: windowFrame.height)
        let hosting = TransparentHostingView(rootView: contentView)
        hosting.frame = NSRect(origin: .zero, size: windowFrame.size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        let glowView = BubbleGlowView(appearance: appearance,
                                      capsuleSize: capsuleFrame.size,
                                      motion: motion)
            .frame(width: glowFrame.width, height: glowFrame.height)
        let glowHosting = TransparentHostingView(rootView: glowView)
        glowHosting.frame = NSRect(origin: .zero, size: glowFrame.size)
        glowHosting.autoresizingMask = [.width, .height]
        glowPanel.contentView = glowHosting

        glowPanel.alphaValue = 1   // 不使用窗口 alpha 动画（透明窗口做 alpha 动画会整块矩形显影）

        // 精确捕获鼠标按下时的修饰键（⌥ = 生词，⇧ = 已掌握）
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            if let self, event.window === self.window {
                self.lastClickModifiers = event.modifierFlags
            }
            return event
        }
    }

    func orderFront() {
        if showsGlow {
            glowWindow.orderFrontRegardless()
            withAnimation(.easeOut(duration: 0.5)) {
                motion.glowOpacity = 1
            }
        }
        window.orderFrontRegardless()

        // 词泡与发光共用同一套动画：入场弹簧 + 轻微浮动
        withAnimation(.spring(response: 0.45, dampingFraction: 0.68)) {
            motion.appeared = true
            motion.capsuleScale = 1
        }
        let amplitude: CGFloat = appearance.fontSize * 0.08   // 幅度克制，避免与柔光产生视觉错位
        let duration = Double.random(in: 3.0 ... 4.6)
        withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
            motion.bobOffset = amplitude
        }

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
        withAnimation(.easeOut(duration: on ? 0.14 : 0.2)) {
            motion.capsuleScale = on ? 1.04 : 1.0
        }
        engine?.scheduleMeaningTip(for: self, show: on)
    }

    // MARK: 双击点爆

    /// 本次点爆的标记意图：⌥ = 生词，⇧ = 已掌握，无修饰键 = 认识（可在设置中关闭）
    var currentIntent: WordMarkState? {
        var flags = lastClickModifiers
        if flags.isEmpty { flags = NSEvent.modifierFlags }   // 兜底：读当前修饰键
        let modifiersOn = engine?.modifierMarksEnabled ?? true
        if modifiersOn, flags.contains(.shift) { return .mastered }
        if modifiersOn, flags.contains(.option) { return .unknown }
        return (engine?.doubleClickMarksKnown ?? true) ? .known : nil
    }

    func pop() {
        pop(with: currentIntent)
    }

    /// 指定标记意图点爆（释义卡上的按钮走这条路径）
    func pop(with intent: WordMarkState?) {
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

        // 发光随点爆一起迅速淡出（在 SwiftUI 内部动画）
        withAnimation(.easeOut(duration: 0.10)) {
            motion.glowOpacity = 0
            motion.capsuleScale = 1.18
        }

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard let self else { return }
            self.window.orderOut(nil)
            self.glowWindow.orderOut(nil)
            self.engine?.remove(self, counted: true, intent: intent)
        }
    }

    // MARK: 飘走

    func driftAway(quick: Bool) {
        guard phase != .drifting, phase != .bursting, !popped else { return }
        ttlTask?.cancel()
        phase = .drifting
        let seconds: Double = quick ? 0.4 : 0.72
        withAnimation(.easeInOut(duration: seconds)) {
            motion.glowOpacity = 0
            motion.appeared = false
            motion.capsuleScale = 0.9
            motion.bobOffset = -52   // 与词泡同步上飘，避免柔光与词泡错位
        }
        let delay = UInt64(seconds * 1_000_000_000) + 60_000_000
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard let self else { return }
            self.window.orderOut(nil)
            self.glowWindow.orderOut(nil)
            self.engine?.remove(self, counted: false)
        }
    }

    func hide() {
        glowWindow.orderOut(nil)
        window.orderOut(nil)
    }

    /// 开发用：把发光层与词泡层的视图缓存合成一张图（不含窗口服务的材质底噪，用于判定矩形来自哪一层）
    func debugCompositeSnapshot() -> NSImage? {
        let glowSize = glowWindow.frame.size
        let bubbleSize = window.frame.size
        let margin = WordMetrics.bubbleMargin(fontSize: appearance.fontSize)
        let offset = WordMetrics.glowMargin - margin   // 让两层的胶囊对齐

        let canvas = NSImage(size: glowSize)
        canvas.lockFocus()

        // 合成一层模拟壁纸，便于评估半透明玻璃在真实背景上的观感
        let wallpaper = ProcessInfo.processInfo.environment["WORDPOP_CAPTURE_WALL"] ?? "light"
        let colors: [NSColor] = wallpaper == "dark"
            ? [NSColor(calibratedRed: 0.09, green: 0.10, blue: 0.16, alpha: 1),
               NSColor(calibratedRed: 0.14, green: 0.16, blue: 0.25, alpha: 1)]
            : [NSColor(calibratedRed: 0.91, green: 0.93, blue: 0.97, alpha: 1),
               NSColor(calibratedRed: 0.96, green: 0.94, blue: 0.91, alpha: 1)]
        NSGradient(colors: colors)?.draw(in: NSRect(origin: .zero, size: glowSize), angle: -45)

        if let glowView = glowWindow.contentView,
           let rep = glowView.bitmapImageRepForCachingDisplay(in: glowView.bounds) {
            glowView.cacheDisplay(in: glowView.bounds, to: rep)
            let glowImage = NSImage(size: glowView.bounds.size)
            glowImage.addRepresentation(rep)
            glowImage.draw(in: NSRect(origin: .zero, size: glowSize))
        }

        if let bubbleView = window.contentView,
           let rep = bubbleView.bitmapImageRepForCachingDisplay(in: bubbleView.bounds) {
            bubbleView.cacheDisplay(in: bubbleView.bounds, to: rep)
            let bubbleImage = NSImage(size: bubbleView.bounds.size)
            bubbleImage.addRepresentation(rep)
            bubbleImage.draw(in: NSRect(x: offset, y: offset, width: bubbleSize.width, height: bubbleSize.height))
        }

        canvas.unlockFocus()
        return canvas
    }

    /// NSWindow.frame（左下原点）→ CGWindowList 使用的屏幕坐标（左上原点）
    private static func cgRect(fromNSRect rect: NSRect) -> CGRect {
        let mainHeight = CGDisplayBounds(CGMainDisplayID()).height
        return CGRect(x: rect.minX,
                      y: mainHeight - rect.maxY,
                      width: rect.width,
                      height: rect.height)
    }

    deinit {
        ttlTask?.cancel()
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
    }
}

// MARK: - 词泡 SwiftUI 内容

struct BubbleContentView: View {
    @ObservedObject var controller: BubbleController
    @ObservedObject var motion: BubbleMotionState

    var body: some View {
        ZStack {
            BubbleCapsuleView(appearance: controller.appearance,
                              text: controller.entry.word,
                              flash: isBursting ? 0.85 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scaleEffect(motion.capsuleScale)
        .opacity(motion.appeared ? 1 : 0)
        .offset(x: 0, y: yOffset)
        .onHover { hovering in
            controller.setHover(hovering)
        }
        .onTapGesture(count: 2) {
            controller.pop()
        }
        .animation(.easeOut(duration: 0.09), value: isBursting)
    }

    // MARK: Visual states

    private var isBursting: Bool { controller.phase == .bursting }
    private var isDrifting: Bool { controller.phase == .drifting }

    private var yOffset: CGFloat {
        motion.bobOffset
    }
}
