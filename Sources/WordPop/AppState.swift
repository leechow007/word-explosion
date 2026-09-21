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
            syncEngineMarkSettings()
            if settings.intervalMinutes != oldValue.intervalMinutes, running {
                nextWaveAt = Date().addingTimeInterval(settings.intervalSeconds)
            }
            if settings.source != oldValue.source {
                engine.clearAll(quick: true)
            }
        }
    }

    private func syncEngineMarkSettings() {
        engine.doubleClickMarksKnown = settings.doubleClickMarksKnown
        engine.modifierMarksEnabled = settings.modifierMarksEnabled
        WordMarkStore.shared.unknownReturnInterval = TimeInterval(max(1, settings.unknownReturnMinutes) * 60)
    }

    // MARK: - 标记与撤销

    private var undoTask: Task<Void, Never>?
    private var lastMark: (word: String, previous: WordMarkState?)?

    /// 统一的标记入口（记录撤销信息 + 刷新统计）
    func applyMark(_ word: String, as state: WordMarkState, recordUndo: Bool = true) {
        let store = WordMarkStore.shared
        let previous = store.state(for: word)
        store.mark(word, as: state)
        statsRevision += 1

        guard recordUndo else { return }
        lastMark = (word, previous)
        undoDescription = "「\(word)」已标记为\(state.title)"
        undoAvailable = true
        undoTask?.cancel()
        undoTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self, !Task.isCancelled else { return }
            self.undoAvailable = false
            self.undoDescription = nil
        }
    }

    /// 撤销上一次标记（回到标记前的状态）
    func undoLastMark() {
        guard let last = lastMark else { return }
        if let previous = last.previous {
            WordMarkStore.shared.mark(last.word, as: previous)
        } else {
            WordMarkStore.shared.clearMark(last.word)
        }
        lastMark = nil
        undoAvailable = false
        undoDescription = nil
        undoTask?.cancel()
        statsRevision += 1
    }

    @Published var running = false
    @Published var nextWaveAt: Date?
    @Published var tick = Date()
    @Published var statsRevision = 0
    /// 撤销上次标记（菜单栏 3 秒内可用）
    @Published var undoAvailable = false
    @Published var undoDescription: String?

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
        syncEngineMarkSettings()

        engine.onBubblePopped = { [weak self] entry, intent in
            StatsStore.shared.recordPop()
            WordMarkStore.shared.recordPop(entry.word)
            if let intent {
                self?.applyMark(entry.word, as: intent, recordUndo: true)
            }
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
                // 注意：只弹一波，不改动（也不持久化）用户设置
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
    /// - 记忆曲线开启时：只有"已到期"的词才参与，逾期越久权重越高
    /// - 记忆曲线关闭时：按状态权重（生词 3.0 / 未标记 1.0 / 认识 0.25，若干天后回升）/ 已掌握 0
    func pickWeight(for entry: WordEntry, cooled: Set<String>, now: Date = Date()) -> Double {
        let key = entry.word.lowercased()
        let marks = WordMarkStore.shared

        guard let state = marks.state(for: entry.word) else {
            // 未标记：基线随机
            var w = 1.0
            if cooled.contains(key) { w *= 0.2 }
            if engine.shouldExclude(entry.word) { w *= 0.5 }
            return w
        }

        var base: Double
        switch state {
        case .mastered:
            return 0
        case .unknown:
            base = settings.unknownWeightMultiplier
        case .known:
            base = settings.knownWeight
        case .unmarked:
            base = 1.0
        }

        if settings.spacedRepetitionEnabled {
            if let due = marks.marks[key]?.dueAt {
                if due > now { return 0 }                      // 未到期：本轮不出现
                let overdueDays = now.timeIntervalSince(due) / 86_400
                base *= min(3.0, 1 + overdueDays * 0.5)        // 逾期越久越优先（上限 3×）
            }
        } else if state == .known {
            // 旧逻辑：「认识」词若干天后权重回升
            let record = marks.marks[key]
            let reference = max(record?.lastSeenAt ?? .distantPast,
                                record?.updatedAt ?? .distantPast)
            let days = now.timeIntervalSince(reference) / 86_400
            base = days >= Double(max(1, settings.knownReviveDays)) ? 1.0 : settings.knownWeight
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

        // 生词优先补位：只要还有"到期且未在冷却中"的生词，每波至少带 1 个（可在设置关闭）
        if settings.prioritizeUnknown {
            let now = Date()
            let unknownCandidates = remaining.filter { entry -> Bool in
                guard marks.state(for: entry.word) == .unknown,
                      !cooled.contains(entry.word.lowercased()) else { return false }
                if settings.spacedRepetitionEnabled,
                   let due = marks.marks[entry.word.lowercased()]?.dueAt, due > now {
                    return false     // 未到期，不强行补位
                }
                return true
            }
            if let firstUnknown = unknownCandidates.randomElement() {
                picked.append(firstUnknown)
                remaining.removeAll { $0.id == firstUnknown.id }
            }
        }

        // 其余按权重抽样（不放回）
        while picked.count < target, !remaining.isEmpty {
            let total = remaining.reduce(0.0) { $0 + weight($1) }
            if total <= 0 { break }        // 剩余词都未到期（记忆曲线模式）
            var r = Double.random(in: 0 ..< total)
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

        // 补位：到期词不足时，用"最早到期"的已标记词补足，避免波次空缺
        if picked.count < target {
            let filler = remaining
                .filter { marks.state(for: $0.word) != nil }
                .sorted {
                    (marks.marks[$0.word.lowercased()]?.dueAt ?? .distantPast)
                        < (marks.marks[$1.word.lowercased()]?.dueAt ?? .distantPast)
                }
            for entry in filler where picked.count < target {
                picked.append(entry)
            }
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
        let none = Set<String>()

        func weight(_ word: String) -> Double {
            guard let entry = pool.first(where: { $0.word == word }) else { return -1 }
            return pickWeight(for: entry, cooled: none)
        }
        func level(_ word: String) -> Int { marks.marks[word.lowercased()]?.level ?? -1 }
        func dueText(_ word: String) -> String {
            ReviewSchedule.dueText(marks.marks[word.lowercased()]?.dueAt)
        }

        log("[MarkTest] 词源=\(settings.source.title)，共 \(pool.count) 词")
        log(String(format: "[MarkTest] 设置：间隔 %d 分钟 / 记忆曲线:%@ / 生词回炉 %d 分钟 / 生词倍数 %.1f / 认识权重 %.2f / 优先补位:%@",
                   settings.intervalMinutes,
                   settings.spacedRepetitionEnabled ? "开" : "关",
                   settings.unknownReturnMinutes,
                   settings.unknownWeightMultiplier,
                   settings.knownWeight,
                   settings.prioritizeUnknown ? "开" : "关"))

        // ---- 记忆曲线校验 ----
        marks.mark(wUnknown, as: .unknown)
        marks.mark(wKnown, as: .known)
        marks.mark(wMastered, as: .mastered)

        log(String(format: "[MarkTest] 未标记词权重 %.2f（期望 1.00）", weight(wUnmarked)))
        log(String(format: "[MarkTest] 生词刚标记：阶段 %d，due=%@，权重 %.2f（期望 0.00，未到期不重复出现）",
                   level(wUnknown), dueText(wUnknown), weight(wUnknown)))
        log(String(format: "[MarkTest] 认识词刚标记：阶段 %d，due=%@，权重 %.2f（期望 0.00）",
                   level(wKnown), dueText(wKnown), weight(wKnown)))
        log(String(format: "[MarkTest] 已掌握权重 %.2f（期望 0.00，due 应为 —：%@）",
                   weight(wMastered), dueText(wMastered)))

        // 生词到期 → 权重恢复（含逾期加成）
        marks.debugSetDue(wUnknown, secondsFromNow: -1)
        log(String(format: "[MarkTest] 生词到期后权重 %.2f（期望 3.00）", weight(wUnknown)))
        // 冷却仍生效
        if let entry = pool.first(where: { $0.word == wUnknown }) {
            log(String(format: "[MarkTest] 到期且进入冷却后权重 %.2f（期望 0.60）",
                       pickWeight(for: entry, cooled: Set([wUnknown.lowercased()]))))
        }
        marks.debugSetDue(wKnown, secondsFromNow: -1)
        log(String(format: "[MarkTest] 认识到期后权重 %.2f（期望 0.25）", weight(wKnown)))

        // 阶段推进：再"记得"一次 → 阶段 +1，间隔 1→2 天
        marks.mark(wKnown, as: .known)
        log(String(format: "[MarkTest] 认识到期后再记得：阶段 %d（期望 2），due=%@（期望约 2 天后）",
                   level(wKnown), dueText(wKnown)))

        // ---- 正确率与阶段分布 ----
        let acc = marks.accuracy()
        let rate = acc.rate.map { String(format: "%.0f%%", $0 * 100) } ?? "—"
        log("[MarkTest] 正确率：记得 \(acc.reviews) 次 / 遗忘 \(acc.lapses) 次 → \(rate)")
        log("[MarkTest] 阶段分布 \(marks.levelDistribution())（index=阶段，值=词数）")

        // ---- 关闭曲线时回退到"权重 + N 天回升"逻辑 ----
        let original = settings
        var off = settings
        off.spacedRepetitionEnabled = false
        settings = off
        marks.debugSetDue(wKnown, secondsFromNow: 30 * 86_400)
        log(String(format: "[MarkTest] 关闭曲线：认识词未到期仍有权重 %.2f（期望 0.25）", weight(wKnown)))
        marks.debugBackdate(wKnown, days: 30)
        log(String(format: "[MarkTest] 关闭曲线：回拨 30 天后权重 %.2f（期望 1.00）", weight(wKnown)))
        settings = original

        // ---- 抽样：已掌握绝不出现 ----
        var masteredHits = 0
        var totalPicks = 0
        for _ in 0 ..< 200 {
            for entry in pickWaveWords(count: 5) {
                totalPicks += 1
                if entry.word.lowercased() == wMastered.lowercased() { masteredHits += 1 }
            }
        }
        log("[MarkTest] 抽样 200 波 / \(totalPicks) 次选词：已掌握出现 \(masteredHits) 次（必须为 0）")

        marks.clearMark(wUnknown)
        marks.clearMark(wKnown)
        marks.clearMark(wMastered)

        // ---- 落盘回读（含新增 level/dueAt 字段）----
        marks.mark(wUnknown, as: .unknown)
        marks.debugReload()
        let reloaded = marks.marks[wUnknown.lowercased()]
        let persisted = marks.state(for: wUnknown) == .unknown
            && reloaded?.level == 0
            && reloaded?.dueAt != nil
        log("[MarkTest] 落盘回读校验（含阶段/到期时间）：\(persisted ? "通过 ✅" : "失败 ❌")（marks.json = \(marks.storagePath)）")
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
