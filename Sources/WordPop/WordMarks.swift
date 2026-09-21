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
}

// MARK: - 词状态存储（marks.json）

final class WordMarkStore: ObservableObject {

    static let shared = WordMarkStore()

    /// key = 小写单词
    @Published private(set) var marks: [String: WordMark] = [:]

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
        let key = word.lowercased()
        var mark = marks[key] ?? WordMark(word: word, state: state)
        mark.state = state
        mark.updatedAt = Date()
        if state == .unknown { mark.unknownCount += 1 }
        marks[key] = mark
        save()
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
            mark.updatedAt = Date()
            marks[key] = mark
            restored += 1
        }
        if restored > 0 { save() }
        return restored
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
