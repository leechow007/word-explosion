import AppKit
import SwiftUI

// MARK: - Overlay engine: spawns & manages word bubble windows

@MainActor
final class OverlayEngine {

    private(set) var bubbles: [BubbleController] = []
    private var meaningTip: MeaningTipController?
    private var burstFXs: [BurstFXController] = []
    private var pendingTip: (bubble: BubbleController, task: Task<Void, Never>)?
    private var pendingTipHide: Task<Void, Never>?
    private var recentPopped: [String] = []

    var onBubblePopped: ((WordEntry) -> Void)?
    var onWaveStarted: ((Int) -> Void)?
    var hapticsEnabled: Bool = true

    // MARK: Wave launch

    func launchWave(words: [WordEntry], appearance: BubbleAppearance, ttl: TimeInterval, clearRemainder: Bool, maxOnScreen: Int) {
        guard !words.isEmpty else { return }

        let keepLimit = clearRemainder ? 0 : max(0, maxOnScreen - words.count)
        if !bubbles.isEmpty {
            // 需要清理的词泡：清到 keepLimit 以内
            let toRemove = bubbles.count - keepLimit
            if toRemove > 0 {
                let doomed = Array(bubbles.prefix(toRemove))
                for bubble in doomed {
                    bubble.driftAway(quick: true)
                }
            }
        }

        if clearRemainder && !bubbles.isEmpty {
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 420_000_000)
                guard let self else { return }
                self.bubbles.removeAll { $0.phase == .drifting }
                self.spawnNow(words: words, appearance: appearance, ttl: ttl)
            }
        } else {
            spawnNow(words: words, appearance: appearance, ttl: ttl)
        }
        print("[WordPop] wave launched: \(words.count) words, active bubbles: \(bubbles.count)")
        onWaveStarted?(words.count)
    }

    func clearAll(quick: Bool) {
        for bubble in bubbles {
            bubble.driftAway(quick: quick)
        }
        hideMeaningTip()
    }

    private func spawnNow(words: [WordEntry], appearance: BubbleAppearance, ttl: TimeInterval) {
        // 清理已结束的旧泡（防御）
        bubbles.removeAll { $0.phase == .drifting || $0.phase == .bursting }

        let screens = NSScreen.screens.isEmpty ? [NSScreen.main].compactMap { $0 } : NSScreen.screens
        guard !screens.isEmpty else { return }
        let plan = Self.screenPlan(screens: screens, count: words.count)
        var placedRects: [CGRect] = bubbles.map { $0.windowFrame }
        var index = 0

        for item in plan {
            for _ in 0 ..< item.count {
                guard index < words.count else { break }
                let word = words[index]
                index += 1
                let size = WordMetrics.windowSize(word: word.word, appearance: appearance)
                guard let rect = Self.place(size: size, in: item.screen, avoiding: placedRects) else { continue }

                let controller = BubbleController(entry: word, appearance: appearance, windowFrame: rect)
                controller.engine = self
                controller.setTTL(ttl)
                controller.orderFront()
                bubbles.append(controller)
                placedRects.append(rect)
            }
        }
    }

    // MARK: Screen distribution

    private struct ScreenPlanItem {
        let screen: NSScreen
        var count: Int
    }

    private static func screenPlan(screens: [NSScreen], count: Int) -> [ScreenPlanItem] {
        guard count > 0 else { return [] }
        let areas = screens.map { $0.visibleFrame.width * $0.visibleFrame.height }
        let totalArea = max(areas.reduce(0, +), 1)
        var result: [ScreenPlanItem] = []
        var remaining = count

        for (i, screen) in screens.enumerated() {
            var c = Int((Double(areas[i]) / Double(totalArea) * Double(count)).rounded(.down))
            if i == 0, c == 0 { c = 1 }          // 主屏至少分到 1 个
            c = min(c, remaining)
            if c > 0 {
                result.append(ScreenPlanItem(screen: screen, count: c))
                remaining -= c
            }
        }
        // 余数按屏幕面积降序轮流补齐
        let order = screens.indices.sorted { areas[$0] > areas[$1] }
        var cursor = 0
        while remaining > 0 {
            let idx = order[cursor % order.count]
            if let pos = result.firstIndex(where: { $0.screen === screens[idx] }) {
                result[pos].count += 1
            } else {
                result.append(ScreenPlanItem(screen: screens[idx], count: 1))
            }
            remaining -= 1
            cursor += 1
        }
        return result
    }

    // MARK: Placement

    /// 返回词泡窗口的屏幕坐标（左下原点），尽量不与 placed 重叠
    private static func place(size: CGSize, in screen: NSScreen, avoiding placed: [CGRect]) -> CGRect? {
        let visible = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        let minX = visible.minX
        let maxX = visible.maxX - size.width
        let minY = visible.minY
        let maxY = visible.maxY - size.height
        guard maxX >= minX, maxY >= minY else { return nil }
        let pad: CGFloat = 8

        var rng = SystemRandomNumberGenerator()

        for _ in 0 ..< 90 {
            let x = minX + CGFloat.random(in: 0 ... 1, using: &rng) * (maxX - minX)
            let y = minY + CGFloat.random(in: 0 ... 1, using: &rng) * (maxY - minY)
            let rect = CGRect(x: x, y: y, width: size.width, height: size.height).insetBy(dx: -pad, dy: -pad)
            if !placed.contains(where: { $0.intersects(rect) }) {
                return CGRect(x: x, y: y, width: size.width, height: size.height)
            }
        }

        // 网格兜底
        var best: (CGRect, CGFloat)? = nil
        let step: CGFloat = 18
        var gy = minY
        while gy <= maxY {
            var gx = minX
            while gx <= maxX {
                let rect = CGRect(x: gx, y: gy, width: size.width, height: size.height)
                var minDist = CGFloat.greatestFiniteMagnitude
                for p in placed where p.intersects(rect.insetBy(dx: -pad, dy: -pad)) {
                    minDist = min(minDist, rect.minX - p.maxX + rect.minY - p.maxY)
                }
                let score = minDist == .greatestFiniteMagnitude ? 1 : minDist
                if best == nil || score > best!.1 {
                    best = (rect, score)
                }
                if score == 1 { break }
                gx += step
            }
            gy += step
        }
        return best?.0
    }

    // MARK: Bubble removal

    func remove(_ bubble: BubbleController, counted: Bool) {
        bubbles.removeAll { $0 === bubble }
        bubble.hide()
        if counted {
            recentPopped.append(bubble.entry.word.lowercased())
            if recentPopped.count > 30 { recentPopped.removeFirst(recentPopped.count - 30) }
            onBubblePopped?(bubble.entry)
        }
        if pendingTip?.bubble === bubble {
            pendingTip?.task.cancel()
            pendingTip = nil
            hideMeaningTip()
        }
    }

    // MARK: Recent words (avoid immediate repeat)

    func shouldExclude(_ word: String) -> Bool {
        recentPopped.contains(word.lowercased())
    }

    // MARK: Meaning tip

    func scheduleMeaningTip(for bubble: BubbleController, show: Bool) {
        pendingTip?.task.cancel()
        pendingTip = nil

        guard show else {
            // 光标可能正停在释义卡上（用户想去点小喇叭）→ 保持显示
            if meaningTip?.isHovered == true { return }
            // 给光标从词泡移动到卡片的时间（两者之间有间隙）
            scheduleTipHide(after: 0.38)
            return
        }

        // 要显示时取消待执行的隐藏
        pendingTipHide?.cancel()
        pendingTipHide = nil

        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 260_000_000)
            guard let self, !Task.isCancelled else { return }
            if bubble.phase == .idle || bubble.phase == .entering {
                self.showMeaningTip(for: bubble)
            }
        }
        pendingTip = (bubble, task)
    }

    /// 释义卡自身 hover 状态变化
    func tipHoverChanged(_ hovering: Bool) {
        if hovering {
            pendingTipHide?.cancel()
            pendingTipHide = nil
        } else {
            scheduleTipHide(after: 0.25)
        }
    }

    private func scheduleTipHide(after seconds: Double) {
        pendingTipHide?.cancel()
        pendingTipHide = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            if self.meaningTip?.isHovered == true { return }
            self.hideMeaningTip()
        }
    }

    private func showMeaningTip(for bubble: BubbleController) {
        if meaningTip == nil {
            let tip = MeaningTipController()
            tip.onHoverChange = { [weak self] hovering in
                self?.tipHoverChanged(hovering)
            }
            meaningTip = tip
        }
        meaningTip?.show(entry: bubble.entry,
                         appearance: bubble.appearance,
                         anchorFrame: bubble.windowFrame,
                         screen: bubble.window.screen ?? NSScreen.main)
    }

    func hideMeaningTip() {
        pendingTipHide?.cancel()
        pendingTipHide = nil
        meaningTip?.hide()
    }

    // MARK: Burst FX

    func burstFX(at center: CGPoint, appearance: BubbleAppearance, anchorScreen: NSScreen?) {
        let fx = BurstFXController(center: center, appearance: appearance, screen: anchorScreen)
        fx.show()
        burstFXs.append(fx)
        let fxID = ObjectIdentifier(fx)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 980_000_000)
            guard let self else { return }
            self.burstFXs.removeAll { ObjectIdentifier($0) == fxID }
        }
    }
}
