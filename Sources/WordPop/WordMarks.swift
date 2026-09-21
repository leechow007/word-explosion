import Foundation

// MARK: - 词状态（与词库解耦：按单词文本记录，换词库/重装都不丢）

enum WordMarkState: String, Codable, CaseIterable {
    case unmarked   // 内部态：仅用于记录计数，不代表用户表态（权重等同未标记）
    case unknown    // 生词：我不认识，多考我
    case known      // 认识：低频复习
    case mastered   // 已掌握：不再出现

    /// 用户可见/可操作的三个状态
    static var userStates: [WordMarkState] { [.unknown, .known, .mastered] }

    var title: String {
        switch self {
        case .unmarked: return "未标记"
        case .unknown: return "生词"
        case .known: return "认识"
        case .mastered: return "已掌握"
        }
    }

    var symbol: String {
        switch self {
        case .unmarked: return "circle.dashed"
        case .unknown: return "questionmark.circle.fill"
        case .known: return "checkmark.circle.fill"
        case .mastered: return "star.circle.fill"
        }
    }
}

struct WordMark: Codable {
    var word: String
    var state: WordMarkState
    var seenCount: Int = 0
    var popCount: Int = 0
    var unknownCount: Int = 0
    var lastSeenAt: Date?
    var updatedAt: Date = Date()

    // MARK: 记忆曲线（v0.3）
    /// 记忆阶段：0 = 刚学/遗忘，1..6 依次为 1/2/4/7/15/30 天
    var level: Int = 0
    /// 下次该复习的时间（nil = 不参与曲线，如「已掌握」或未标记）
    var dueAt: Date?
    /// 累计"记得"（双击=认识）的次数
    var reviewCount: Int = 0

    init(word: String, state: WordMarkState) {
        self.word = word
        self.state = state
    }

    /// 兼容旧版 marks.json：缺失字段用默认值补齐
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        word = try c.decode(String.self, forKey: .word)
        state = try c.decodeIfPresent(WordMarkState.self, forKey: .state) ?? .unmarked
        seenCount = try c.decodeIfPresent(Int.self, forKey: .seenCount) ?? 0
        popCount = try c.decodeIfPresent(Int.self, forKey: .popCount) ?? 0
        unknownCount = try c.decodeIfPresent(Int.self, forKey: .unknownCount) ?? 0
        lastSeenAt = try c.decodeIfPresent(Date.self, forKey: .lastSeenAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        level = try c.decodeIfPresent(Int.self, forKey: .level) ?? 0
        dueAt = try c.decodeIfPresent(Date.self, forKey: .dueAt)
        reviewCount = try c.decodeIfPresent(Int.self, forKey: .reviewCount) ?? 0
    }
}

// MARK: - 记忆曲线参数

enum ReviewSchedule {
    /// level 0 = 生词回炉（分钟级），之后按 1/2/4/7/15/30 天递增
    static let intervals: [TimeInterval] = [
        10 * 60,        // 0：刚标记为生词 → 10 分钟后回炉
        1 * 86_400,     // 1
        2 * 86_400,     // 2
        4 * 86_400,     // 3
        7 * 86_400,     // 4
        15 * 86_400,    // 5
        30 * 86_400     // 6+
    ]

    static func interval(forLevel level: Int) -> TimeInterval {
        intervals[min(max(level, 0), intervals.count - 1)]
    }

    static func levelTitle(_ level: Int) -> String {
        switch level {
        case 0: return "刚学"
        case 1: return "1 天"
        case 2: return "2 天"
        case 3: return "4 天"
        case 4: return "7 天"
        case 5: return "15 天"
        default: return "30 天"
        }
    }

    /// 人类可读的到期描述
    static func dueText(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "—" }
        let delta = date.timeIntervalSince(now)
        if delta <= 0 { return "现在可复习" }
        let minutes = delta / 60
        if minutes < 60 { return "\(max(1, Int(minutes.rounded()))) 分钟后" }
        let roundedHours = Int((delta / 3600).rounded())
        if roundedHours < 24 { return "\(max(1, roundedHours)) 小时后" }
        let days = Int((delta / 86_400).rounded())
        return "\(max(1, days)) 天后"
    }
}

// MARK: - 词状态存储（marks.json）

final class WordMarkStore: ObservableObject {

    static let shared = WordMarkStore()

    /// key = 小写单词
    @Published private(set) var marks: [String: WordMark] = [:]

    /// 生词回炉间隔（由设置同步，默认 10 分钟）
    var unknownReturnInterval: TimeInterval = 10 * 60

    private var fileURL: URL

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("WordPop", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("marks.json")
        load()
    }

    var storagePath: String { fileURL.path }

    // MARK: 查询

    func state(for word: String) -> WordMarkState? {
        guard let state = marks[word.lowercased()]?.state, state != .unmarked else { return nil }
        return state
    }

    func masteredWords() -> Set<String> {
        Set(marks.values.filter { $0.state == .mastered }.map { $0.word.lowercased() })
    }

    func count(of state: WordMarkState) -> Int {
        marks.values.filter { $0.state == state }.count
    }

    // MARK: 修改

    func mark(_ word: String, as state: WordMarkState) {
        mark(word, as: state, now: Date())
    }

    /// 标记 + 按记忆曲线安排下次复现
    func mark(_ word: String, as state: WordMarkState, now: Date) {
        let key = word.lowercased()
        var mark = marks[key] ?? WordMark(word: word, state: state)
        mark.state = state
        mark.updatedAt = now

        switch state {
        case .unknown:
            // 不认识 → 回到第 0 阶段，短间隔回炉
            mark.unknownCount += 1
            mark.level = 0
            mark.dueAt = now.addingTimeInterval(unknownReturnInterval)
        case .known:
            // 记得 → 阶段 +1，间隔按 1/2/4/7/15/30 天递增
            mark.reviewCount += 1
            mark.level = min(mark.level + 1, ReviewSchedule.intervals.count - 1)
            mark.dueAt = now.addingTimeInterval(ReviewSchedule.interval(forLevel: mark.level))
        case .mastered:
            mark.dueAt = nil      // 不再参与曲线
        case .unmarked:
            mark.level = 0
            mark.dueAt = nil
        }

        marks[key] = mark
        save()
    }

    /// 到期待复习的词
    func dueMarks(now: Date = Date()) -> [WordMark] {
        marks.values.filter { mark in
            guard mark.state == .unknown || mark.state == .known else { return false }
            return (mark.dueAt ?? .distantPast) <= now
        }
    }

    func dueCount(now: Date = Date()) -> Int {
        dueMarks(now: now).count
    }

    func nextDueAt(now: Date = Date()) -> Date? {
        marks.values
            .compactMap { mark -> Date? in
                guard mark.state == .unknown || mark.state == .known, let due = mark.dueAt else { return nil }
                return due > now ? due : nil
            }
            .min()
    }

    /// 各记忆阶段的词数（index = level）
    func levelDistribution() -> [Int] {
        var buckets = Array(repeating: 0, count: ReviewSchedule.intervals.count)
        for mark in marks.values where mark.state == .unknown || mark.state == .known {
            let idx = min(max(mark.level, 0), buckets.count - 1)
            buckets[idx] += 1
        }
        return buckets
    }

    /// 正确率：记得次数 /（记得 + 遗忘）
    func accuracy() -> (reviews: Int, lapses: Int, rate: Double?) {
        let reviews = marks.values.reduce(0) { $0 + $1.reviewCount }
        let lapses = marks.values.reduce(0) { $0 + $1.unknownCount }
        let total = reviews + lapses
        return (reviews, lapses, total > 0 ? Double(reviews) / Double(total) : nil)
    }

    func clearMark(_ word: String) {
        marks.removeValue(forKey: word.lowercased())
        save()
    }

    /// 开发自测用：把某词的时间戳回拨，验证"7 天后权重回升"
    func debugBackdate(_ word: String, days: Int) {
        let key = word.lowercased()
        guard var mark = marks[key] else { return }
        let past = Date().addingTimeInterval(-Double(days) * 86_400)
        mark.lastSeenAt = past
        mark.updatedAt = past
        marks[key] = mark
        save()
    }

    /// 开发自测用：从磁盘重新加载，验证持久化是否真的生效
    func debugReload() {
        marks = [:]
        load()
    }

    func clearAll() {
        marks = [:]
        save()
    }

    /// 把「已掌握」的词全部恢复为未标记（安全阀：误标后可一键还原）
    @discardableResult
    func restoreAllMastered() -> Int {
        var restored = 0
        for (key, var mark) in marks where mark.state == .mastered {
            mark.state = .unmarked
            mark.level = 0
            mark.dueAt = nil
            mark.updatedAt = Date()
            marks[key] = mark
            restored += 1
        }
        if restored > 0 { save() }
        return restored
    }

    /// 开发自测用：把某词的到期时间设为过去/未来，验证曲线调度
    func debugSetDue(_ word: String, secondsFromNow seconds: TimeInterval) {
        let key = word.lowercased()
        guard var mark = marks[key] else { return }
        mark.dueAt = Date().addingTimeInterval(seconds)
        marks[key] = mark
        save()
    }

    /// 记录"弹出过"（仅计数，不改变用户标记状态）
    func recordSeen(_ words: [String]) {
        guard !words.isEmpty else { return }
        let now = Date()
        for word in words {
            let key = word.lowercased()
            var mark = marks[key] ?? WordMark(word: word, state: .unmarked)
            mark.seenCount += 1
            mark.lastSeenAt = now
            marks[key] = mark
        }
        save()
    }

    /// 记录"被点爆"
    func recordPop(_ word: String) {
        let key = word.lowercased()
        var mark = marks[key] ?? WordMark(word: word, state: .unmarked)
        mark.popCount += 1
        marks[key] = mark
        save()
    }

    // MARK: 持久化

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([WordMark].self, from: data) else { return }
        marks = Dictionary(uniqueKeysWithValues: list.map { ($0.word.lowercased(), $0) })
        migrateLegacyMarksIfNeeded()
    }

    /// 把 v0.2 时期（无记忆曲线字段）的标记迁移到曲线体系：
    /// - 缺失到期时间 → 设为"立即可复习"，之后按曲线走
    /// - 旧版「双击=认识」没有复习计数 → 补 1 次，避免正确率被低估
    private func migrateLegacyMarksIfNeeded() {
        let now = Date()
        var changed = false
        for (key, var mark) in marks {
            var touched = false
            if (mark.state == .unknown || mark.state == .known), mark.dueAt == nil {
                mark.dueAt = now
                touched = true
            }
            if mark.state == .known, mark.reviewCount == 0 {
                mark.reviewCount = 1
                touched = true
            }
            if touched {
                marks[key] = mark
                changed = true
            }
        }
        if changed {
            save()
            FileHandle.standardError.write(Data("[WordPop] 已迁移旧标记到记忆曲线（\(marks.count) 条）\n".utf8))
        }
    }

    private func save() {
        let list = Array(marks.values)
        do {
            let data = try JSONEncoder().encode(list)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            let message = "[WordPop] 标记保存失败: \(error.localizedDescription)\n"
            FileHandle.standardError.write(Data(message.utf8))
        }
    }
}
