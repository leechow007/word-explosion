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

        engine.onBubblePopped = { [weak self] _ in
            StatsStore.shared.recordPop()
            self?.statsRevision += 1
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
        if settings.autoStartOnLaunch {
            start()
        }
        beginSmokeTestIfRequested()
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
        let sourcePool = WordPool.entries(for: settings.source)
        guard !sourcePool.isEmpty else {
            engine.clearAll(quick: true)
            return
        }

        var candidates = sourcePool.filter { !engine.shouldExclude($0.word) }
        if candidates.isEmpty { candidates = sourcePool }

        let count = min(settings.wordsPerWave, candidates.count)
        let wave = Array(candidates.shuffled().prefix(count))

        let appearance = BubbleAppearance.from(settings: settings)
        engine.launchWave(
            words: wave,
            appearance: appearance,
            ttl: settings.ttlSeconds,
            clearRemainder: settings.clearRemainderBeforeNewWave,
            maxOnScreen: settings.maxOnScreen
        )
    }

    // MARK: 词库变化

    func wordSourceChanged() {
        engine.clearAll(quick: true)
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
