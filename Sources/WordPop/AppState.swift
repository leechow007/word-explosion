import AppKit
import SwiftUI

// MARK: - 全局应用状态与调度引擎

@MainActor
final class AppState: ObservableObject {

    static let shared = AppState()

    let engine = OverlayEngine()

    @Published var settings: AppSettings {
        didSet {
            saveSettings()
            engine.hapticsEnabled = settings.hapticsEnabled
            if settings.intervalMinutes != oldValue.intervalMinutes, running {
                nextWaveAt = Date().addingTimeInterval(settings.intervalSeconds)
            }
            if settings.source != oldValue.source {
                engine.clearAll(quick: true)
            }
        }
    }

    @Published var running = false
    @Published var nextWaveAt: Date?
    @Published var tick = Date()
    @Published var statsRevision = 0

    private var timer: Timer?
    private var pauseRemaining: TimeInterval = 0
    private var didFinishLaunch = false

    private let settingsKey = "wordpop.settings.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = AppSettings()
        }
        engine.hapticsEnabled = settings.hapticsEnabled

        engine.onBubblePopped = { [weak self] entry, intent in
            StatsStore.shared.recordPop()
            WordMarkStore.shared.recordPop(entry.word)
            WordMarkStore.shared.mark(entry.word, as: intent)
            self?.statsRevision += 1
        }
        engine.onWordsSpawned = { words in
            WordMarkStore.shared.recordSeen(words)
        }
        engine.onWaveStarted = { [weak self] _ in
            StatsStore.shared.recordWave()
            self?.statsRevision += 1
        }
    }

    // MARK: 生命周期

    func applicationDidFinishLaunching() {
        guard !didFinishLaunch else { return }
        didFinishLaunch = true

        // 开发自测：标记 → 加权选词闭环（环境变量或触发文件）
        if runMarkSelfTestIfRequested() || runMarkSelfTestFromTriggerFile() {
            NSApp.terminate(nil)
            return
        }

        // 开发预览：离屏渲染词泡视觉后退出
        if DevPreview.runIfRequested() {
            return
        }

        // 自动导入模式：环境变量 WORDPOP_IMPORT 或应用目录下的 wordpop-import.txt
        if performAutoImportIfNeeded() {
            return
        }

        if settings.autoStartOnLaunch {
            start()
        }
        beginSmokeTestIfRequested()
    }

    /// 启动时自动导入词本（一次性）。
    /// 检测顺序：环境变量 WORDPOP_IMPORT → 应用包同级目录的 wordpop-import.txt/.csv。
    /// 导入结果写入同级 wordpop-import.log，便于脚本化验证。
    @discardableResult
    private func performAutoImportIfNeeded() -> Bool {
        let env = ProcessInfo.processInfo.environment
        let bundleDir = Bundle.main.bundleURL.deletingLastPathComponent()

        var importURL: URL?
        var exitAfterImport = false

        if let path = env["WORDPOP_IMPORT"], !path.isEmpty {
            importURL = URL(fileURLWithPath: path)
            exitAfterImport = env["WORDPOP_IMPORT_EXIT"] == "1"
        } else {
            for name in ["wordpop-import.txt", "wordpop-import.csv"] {
                let candidate = bundleDir.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    importURL = candidate
                    break
                }
            }
            exitAfterImport = env["WORDPOP_IMPORT_EXIT"] == "1"
        }

        guard let url = importURL else { return false }

        var report: [String] = []
        func log(_ text: String) {
            report.append(text)
            FileHandle.standardError.write(Data((text + "\n").utf8))
        }

        log("[WordPop] 开始导入: \(url.path)")
        let result = WordImportParser.parse(url: url)

        var merged = WordBankStore.shared.imported
        var seen = Set(merged.map { $0.word.lowercased() })
        var added = 0
        var duplicate = 0
        for entry in result.entries {
            if seen.insert(entry.word.lowercased()).inserted {
                merged.append(entry)
                added += 1
            } else {
                duplicate += 1
            }
        }
        WordBankStore.shared.replaceImported(with: merged)

        var updated = settings
        updated.source = .imported
        settings = updated

        log("[WordPop] 解析 \(result.entries.count) 条，新增 \(added) 条，重复 \(duplicate) 条，无效行 \(result.skipped)")
        log("[WordPop] 我的词本当前 \(WordBankStore.shared.imported.count) 条；词源已切换为「我的词本」")
        let savedOK = FileManager.default.fileExists(
            atPath: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("WordPop/bank.json").path
        )
        log("[WordPop] 词库落盘: \(savedOK ? "成功" : "失败（见上方错误）")")
        log("[WordPop] 完成时间: \(Date())")

        // 写报告到导入文件同级目录
        let reportURL = url.deletingLastPathComponent().appendingPathComponent("wordpop-import.log")
        try? report.joined(separator: "\n").write(to: reportURL, atomically: true, encoding: .utf8)

        // 一次性使用：导入后删除源文件（避免每次启动重复导入；重复条目本身也会被去重）
        try? FileManager.default.removeItem(at: url)

        if exitAfterImport {
            Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                NSApp.terminate(nil)
            }
        } else if settings.autoStartOnLaunch {
            start()
        }
        return true
    }

    /// 冒烟测试：WORDPOP_SMOKE=1 时 1 秒后立即弹一波（不依赖计时器）
    private func beginSmokeTestIfRequested() {
        let env = ProcessInfo.processInfo.environment

        if env["WORDPOP_SMOKE"] == "1" {
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self else { return }
                var demo = self.settings
                demo.intervalMinutes = 180
                demo.ttlMinutes = 5
                self.settings = demo
                self.fireNow()
            }

            if env["WORDPOP_SMOKE_QUIT"] == "1" {
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 9_000_000_000)
                    self?.engine.clearAll(quick: true)
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    NSApp.terminate(nil)
                }
            }
        }

        if env["WORDPOP_OPEN_SETTINGS"] == "1" {
            Task { [weak self] in
                FileHandle.standardError.write(Data("[WordPop] settings test begin\n".utf8))
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                SettingsWindowController.open()
                FileHandle.standardError.write(Data("[WordPop] settings opened\n".utf8))
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                SettingsWindowController.close()
                FileHandle.standardError.write(Data("[WordPop] settings closed, quitting\n".utf8))
                try? await Task.sleep(nanoseconds: 400_000_000)
                self?.engine.clearAll(quick: true)
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: 计时控制

    func start() {
        running = true
        pauseRemaining = 0
        scheduleNextWave()
        installTimer()
    }

    func pause() {
        guard running else { return }
        running = false
        if let next = nextWaveAt {
            pauseRemaining = max(0, next.timeIntervalSinceNow)
        }
        nextWaveAt = nil
        timer?.invalidate()
        timer = nil
        tick = Date()
    }

    func resume() {
        guard !running else { return }
        running = true
        let interval = max(pauseRemaining > 0 ? pauseRemaining : settings.intervalSeconds, 0.5)
        pauseRemaining = 0
        nextWaveAt = Date().addingTimeInterval(interval)
        installTimer()
    }

    func toggleRunning() {
        running ? pause() : resume()
    }

    private func scheduleNextWave() {
        nextWaveAt = Date().addingTimeInterval(settings.intervalSeconds)
    }

    private func installTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickNow()
            }
        }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tickNow() {
        tick = Date()
        guard running else { return }
        if let next = nextWaveAt, next <= tick {
            fireWave()
            scheduleNextWave()
        }
    }

    var countdownText: String {
        if !running { return "已暂停" }
        guard let next = nextWaveAt else { return "待命" }
        let remain = max(0, next.timeIntervalSince(tick))
        let total = Int(remain.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }

    // MARK: 弹出一波

    func fireNow() {
        fireWave()
    }

    private func fireWave() {
        let wave = pickWaveWords(count: settings.wordsPerWave)
        guard !wave.isEmpty else {
            // 词库为空，或所有词都已被标记为「已掌握」
            engine.clearAll(quick: true)
            return
        }

        let appearance = BubbleAppearance.from(settings: settings)
        engine.launchWave(
            words: wave,
            appearance: appearance,
            ttl: settings.ttlSeconds,
            clearRemainder: settings.clearRemainderBeforeNewWave,
            maxOnScreen: settings.maxOnScreen
        )
    }

    // MARK: - 加权选词（标记体系的核心）

    /// 最近 2 波出现过的词（用于冷却降权）
    private var recentWaves: [[String]] = []

    /// 单词的选词权重（可单测）
    /// 生词 3.0 / 未标记 1.0 / 认识 0.25（7 天后回升到 1.0）/ 已掌握 0
    func pickWeight(for entry: WordEntry, cooled: Set<String>) -> Double {
        let key = entry.word.lowercased()
        let marks = WordMarkStore.shared
        let base: Double
        switch marks.state(for: entry.word) {
        case .some(.unknown):
            base = 3.0
        case .some(.known):
            // 「认识」= 低频复习：7 天内几乎不再出现，之后权重回升到正常水平
            // （否则在大词库中 0.25 的权重会等价于"永不出现"）
            let record = marks.marks[key]
            let reference = max(record?.lastSeenAt ?? .distantPast,
                                record?.updatedAt ?? .distantPast)
            let days = Date().timeIntervalSince(reference) / 86_400
            base = days >= 7 ? 1.0 : 0.25
        case .some(.mastered):
            base = 0.0
        case .some(.unmarked), .none:
            base = 1.0
        }
        var w = base
        if cooled.contains(key) { w *= 0.2 }
        if engine.shouldExclude(entry.word) { w *= 0.5 }
        return w
    }

    /// 权重：生词 3.0 / 未标记 1.0 / 认识 0.25 / 已掌握排除；再叠加冷却与"最近点爆"降权
    func pickWaveWords(count: Int) -> [WordEntry] {
        let pool = WordPool.entries(for: settings.source)
        guard !pool.isEmpty else { return [] }

        let marks = WordMarkStore.shared
        let available = pool.filter { marks.state(for: $0.word) != .mastered }
        guard !available.isEmpty else { return [] }

        let cooled = Set(recentWaves.flatMap { $0 })
        let target = min(count, available.count)

        func weight(_ entry: WordEntry) -> Double {
            pickWeight(for: entry, cooled: cooled)
        }

        var remaining = available
        var picked: [WordEntry] = []

        // 生词优先补位：只要还有"未在冷却中"的生词，每波至少带 1 个
        let unknownCandidates = remaining.filter {
            marks.state(for: $0.word) == .unknown && !cooled.contains($0.word.lowercased())
        }
        if let firstUnknown = unknownCandidates.randomElement() {
            picked.append(firstUnknown)
            remaining.removeAll { $0.id == firstUnknown.id }
        }

        // 其余按权重抽样（不放回）
        while picked.count < target, !remaining.isEmpty {
            let total = remaining.reduce(0.0) { $0 + weight($1) }
            var r = Double.random(in: 0 ..< max(total, 0.0001))
            var chosen = remaining[remaining.count - 1]
            for entry in remaining {
                r -= weight(entry)
                if r <= 0 {
                    chosen = entry
                    break
                }
            }
            picked.append(chosen)
            remaining.removeAll { $0.id == chosen.id }
        }

        recentWaves.append(picked.map { $0.word.lowercased() })
        if recentWaves.count > 2 { recentWaves.removeFirst(recentWaves.count - 2) }

        return picked.shuffled()
    }

    // MARK: 词库变化

    func wordSourceChanged() {
        engine.clearAll(quick: true)
    }

    // MARK: 开发自测：验证"标记 → 加权选词"闭环（WORDPOP_MARK_TEST=1）

    func runMarkSelfTestIfRequested() -> Bool {
        guard ProcessInfo.processInfo.environment["WORDPOP_MARK_TEST"] == "1" else { return false }
        runMarkSelfTest(reportURL: nil)
        return true
    }

    /// 触发文件版本（用于 `open` 启动的非沙箱路径）：dist/wordpop-marktest.txt
    func runMarkSelfTestFromTriggerFile() -> Bool {
        let dir = Bundle.main.bundleURL.deletingLastPathComponent()
        let trigger = dir.appendingPathComponent("wordpop-marktest.txt")
        guard FileManager.default.fileExists(atPath: trigger.path) else { return false }
        try? FileManager.default.removeItem(at: trigger)
        runMarkSelfTest(reportURL: dir.appendingPathComponent("wordpop-marktest.log"))
        return true
    }

    private func runMarkSelfTest(reportURL: URL?) {
        var lines: [String] = []
        func log(_ text: String) {
            lines.append(text)
            FileHandle.standardError.write(Data((text + "\n").utf8))
        }

        let pool = WordPool.entries(for: settings.source)
        guard pool.count >= 4 else {
            log("[MarkTest] 词库太小，跳过")
            if let reportURL {
                try? lines.joined(separator: "\n").write(to: reportURL, atomically: true, encoding: .utf8)
            }
            return
        }

        let marks = WordMarkStore.shared
        let wUnmarked = pool[3].word
        let wUnknown = pool[0].word
        let wMastered = pool[1].word
        let wKnown = pool[2].word
        marks.mark(wUnknown, as: .unknown)
        marks.mark(wMastered, as: .mastered)
        marks.mark(wKnown, as: .known)

        log("[MarkTest] 词源=\(settings.source.title)，共 \(pool.count) 词")
        log("[MarkTest] 标记：\(wUnknown)=生词 / \(wKnown)=认识 / \(wMastered)=已掌握 / \(wUnmarked)=未标记")

        let none = Set<String>()
        func w(_ word: String) -> Double {
            guard let entry = pool.first(where: { $0.word == word }) else { return -1 }
            return pickWeight(for: entry, cooled: none)
        }
        log(String(format: "[MarkTest] 权重校验：未标记 %.2f（期望 1.00）/ 生词 %.2f（期望 3.00）/ 认识 %.2f（期望 0.25）/ 已掌握 %.2f（期望 0.00）",
                   w(wUnmarked), w(wUnknown), w(wKnown), w(wMastered)))

        let cooledSet = Set([wUnknown.lowercased()])
        if let entry = pool.first(where: { $0.word == wUnknown }) {
            log(String(format: "[MarkTest] 冷却校验：生词进入最近 2 波后权重 %.2f（期望 0.60）",
                       pickWeight(for: entry, cooled: cooledSet)))
        }

        marks.debugBackdate(wKnown, days: 8)
        log(String(format: "[MarkTest] 7 天回升校验：认识词回拨 8 天后权重 %.2f（期望 1.00）", w(wKnown)))

        // 抽样验证：已掌握的词绝不出现在任何一波
        var masteredHits = 0
        var unknownHits = 0
        var totalPicks = 0
        for _ in 0 ..< 200 {
            for entry in pickWaveWords(count: 5) {
                totalPicks += 1
                let lower = entry.word.lowercased()
                if lower == wMastered.lowercased() { masteredHits += 1 }
                if lower == wUnknown.lowercased() { unknownHits += 1 }
            }
        }
        log("[MarkTest] 抽样 200 波 / \(totalPicks) 次选词：生词出现 \(unknownHits) 次，已掌握出现 \(masteredHits) 次（必须为 0）")

        marks.clearMark(wUnknown)
        marks.clearMark(wKnown)
        marks.clearMark(wMastered)

        // 落盘回读校验：证明 marks.json 真的写成功并能读回
        marks.mark(wUnknown, as: .unknown)
        marks.debugReload()
        let persisted = marks.state(for: wUnknown) == .unknown
        log("[MarkTest] 落盘回读校验：\(persisted ? "通过 ✅" : "失败 ❌")（marks.json = \(marks.storagePath)）")
        marks.clearMark(wUnknown)

        if let reportURL {
            try? lines.joined(separator: "\n").write(to: reportURL, atomically: true, encoding: .utf8)
        }
    }

    func clearAllBubbles() {
        engine.clearAll(quick: true)
    }

    // MARK: 设置持久化

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }

    func resetSettings() {
        settings = AppSettings()
    }
}
