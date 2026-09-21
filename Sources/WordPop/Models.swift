import Foundation
import SwiftUI

// MARK: - Word entry

struct WordEntry: Codable, Identifiable, Hashable {
    let id: UUID
    var word: String
    var meaning: String

    init(id: UUID = UUID(), word: String, meaning: String) {
        self.id = id
        self.word = word
        self.meaning = meaning
    }
}

// MARK: - Word source

enum WordSource: String, Codable, CaseIterable, Identifiable {
    case builtinEssential
    case builtinAdvanced
    case imported

    var id: String { rawValue }

    var title: String {
        switch self {
        case .builtinEssential: return "内置 · 基础精选"
        case .builtinAdvanced: return "内置 · 进阶精选"
        case .imported: return "我的词本"
        }
    }

    var symbol: String {
        switch self {
        case .builtinEssential: return "sparkle"
        case .builtinAdvanced: return "sparkles"
        case .imported: return "book.closed.fill"
        }
    }
}

// MARK: - Appearance enums

enum BubbleTheme: String, Codable, CaseIterable, Identifiable {
    case glassLight = "晨雾"
    case glassDark = "午夜"
    case aurora = "晚霞"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .glassLight: return "Glass Light"
        case .glassDark: return "Glass Dark"
        case .aurora: return "Aurora"
        }
    }
}

enum BubbleFontSize: Double, Codable, CaseIterable, Identifiable {
    case small = 17
    case medium = 23
    case large = 31

    var id: Double { rawValue }

    var title: String {
        switch self {
        case .small: return "小"
        case .medium: return "中"
        case .large: return "大"
        }
    }
}

// MARK: - App settings

struct AppSettings: Codable, Equatable {
    // 通用
    var intervalMinutes: Int = 20
    var wordsPerWave: Int = 6
    var ttlMinutes: Int = 3
    var clearRemainderBeforeNewWave: Bool = true
    var maxOnScreen: Int = 24
    var autoStartOnLaunch: Bool = true
    var hapticsEnabled: Bool = true
    var speakOnHover: Bool = true

    // 词库
    var source: WordSource = .builtinEssential

    // 外观
    var theme: BubbleTheme = .glassLight
    var accentHex: String = "#5E5CE6"
    var fontSize: BubbleFontSize = .medium
    var serifFont: Bool = false
    var bubbleBackgroundHex: String = "#FFFFFF"
    var bubbleFillOpacity: Double = 0.55

    var intervalSeconds: TimeInterval { TimeInterval(intervalMinutes * 60) }
    var ttlSeconds: TimeInterval { TimeInterval(ttlMinutes * 60) }

    init() {}

    /// 兼容旧版本配置：缺失字段自动使用默认值，避免升级后设置被重置
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        intervalMinutes = try c.decodeIfPresent(Int.self, forKey: .intervalMinutes) ?? d.intervalMinutes
        wordsPerWave = try c.decodeIfPresent(Int.self, forKey: .wordsPerWave) ?? d.wordsPerWave
        ttlMinutes = try c.decodeIfPresent(Int.self, forKey: .ttlMinutes) ?? d.ttlMinutes
        clearRemainderBeforeNewWave = try c.decodeIfPresent(Bool.self, forKey: .clearRemainderBeforeNewWave) ?? d.clearRemainderBeforeNewWave
        maxOnScreen = try c.decodeIfPresent(Int.self, forKey: .maxOnScreen) ?? d.maxOnScreen
        autoStartOnLaunch = try c.decodeIfPresent(Bool.self, forKey: .autoStartOnLaunch) ?? d.autoStartOnLaunch
        hapticsEnabled = try c.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? d.hapticsEnabled
        speakOnHover = try c.decodeIfPresent(Bool.self, forKey: .speakOnHover) ?? d.speakOnHover
        source = try c.decodeIfPresent(WordSource.self, forKey: .source) ?? d.source
        theme = try c.decodeIfPresent(BubbleTheme.self, forKey: .theme) ?? d.theme
        accentHex = try c.decodeIfPresent(String.self, forKey: .accentHex) ?? d.accentHex
        fontSize = try c.decodeIfPresent(BubbleFontSize.self, forKey: .fontSize) ?? d.fontSize
        serifFont = try c.decodeIfPresent(Bool.self, forKey: .serifFont) ?? d.serifFont
        bubbleBackgroundHex = try c.decodeIfPresent(String.self, forKey: .bubbleBackgroundHex) ?? d.bubbleBackgroundHex
        bubbleFillOpacity = try c.decodeIfPresent(Double.self, forKey: .bubbleFillOpacity) ?? d.bubbleFillOpacity
    }
}

// MARK: - Statistics

struct DailyCount: Codable, Identifiable {
    var day: Date
    var count: Int

    var id: Date { day }
}

final class StatsStore {
    private(set) var daily: [String: Int] = [:]      // key: yyyy-MM-dd
    private(set) var totalPopped: Int = 0
    private(set) var totalWaves: Int = 0

    static let shared = StatsStore()
    private var fileURL: URL

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("WordPop", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("stats.json")
        load()
    }

    var todayCount: Int {
        daily[Self.dayKey(Date())] ?? 0
    }

    static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    func recordPop() {
        let key = Self.dayKey(Date())
        daily[key, default: 0] += 1
        totalPopped += 1
        save()
    }

    func recordWave() {
        totalWaves += 1
        save()
    }

    func lastDays(_ n: Int) -> [DailyCount] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0 ..< n).reversed().compactMap { offset -> DailyCount? in
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return DailyCount(day: day, count: daily[Self.dayKey(day)] ?? 0)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let json = try? JSONDecoder().decode(Self.Persisted.self, from: data) else { return }
        daily = json.daily
        totalPopped = json.totalPopped
        totalWaves = json.totalWaves
    }

    private func save() {
        let json = Persisted(daily: daily, totalPopped: totalPopped, totalWaves: totalWaves)
        if let data = try? JSONEncoder().encode(json) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private struct Persisted: Codable {
        var daily: [String: Int]
        var totalPopped: Int
        var totalWaves: Int
    }
}

// MARK: - Imported word bank persistence

final class WordBankStore: ObservableObject {
    static let shared = WordBankStore()

    @Published private(set) var imported: [WordEntry] = []
    private var fileURL: URL

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("WordPop", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("bank.json")
        load()
    }

    func replaceImported(with entries: [WordEntry]) {
        imported = entries
        save()
    }

    func remove(ids: Set<UUID>) {
        imported.removeAll { ids.contains($0.id) }
        save()
    }

    func clearImported() {
        imported = []
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([WordEntry].self, from: data) else { return }
        imported = list
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(imported)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // 不再静默失败：输出错误并写一份兜底文件，便于排查与恢复
            let message = "[WordPop] 词库保存失败: \(error.localizedDescription)\n"
            FileHandle.standardError.write(Data(message.utf8))
            let fallback = FileManager.default.temporaryDirectory
                .appendingPathComponent("WordPop-bank-fallback.json")
            if let data = try? JSONEncoder().encode(imported) {
                try? data.write(to: fallback, options: .atomic)
                FileHandle.standardError.write(Data("[WordPop] 已写入兜底文件: \(fallback.path)\n".utf8))
            }
        }
    }
}

// MARK: - Import parsing

struct ImportResult {
    var entries: [WordEntry]
    var skipped: Int
    var summary: String
}

enum WordImportParser {
    static func parse(url: URL) -> ImportResult {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
            // Fallback: GB18030 / UTF-16 attempts for common Chinese exports
            if let gb = try? String(contentsOf: url, encoding: .init(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))) {
                return parse(text: gb)
            }
            if let u16 = try? String(contentsOf: url, encoding: .utf16) {
                return parse(text: u16)
            }
            return ImportResult(entries: [], skipped: 0, summary: "无法读取文件，请确认是 UTF-8 编码的 txt/csv")
        }
        return parse(text: raw)
    }

    static func parse(text rawText: String) -> ImportResult {
        var seen = Set<String>()
        var entries: [WordEntry] = []
        var skipped = 0

        // Strip BOM and split lines
        var text = rawText
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let lines = text.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            var word = ""
            var meaning = ""

            if trimmed.contains("\t") {
                let parts = trimmed.components(separatedBy: "\t")
                word = parts[0].trimmingCharacters(in: .whitespaces)
                meaning = parts.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespaces)
            } else if trimmed.contains(",") {
                // Simple CSV split (handles quoted fields)
                let fields = parseCSVLine(trimmed)
                word = (fields.first ?? "").trimmingCharacters(in: .whitespaces)
                meaning = fields.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespaces)
            } else {
                // Single word only, or "word meaning" separated by space
                let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                word = String(parts.first ?? "")
                if parts.count > 1 {
                    meaning = String(parts[1]).trimmingCharacters(in: .whitespaces)
                }
            }

            guard isValidWord(word) else {
                skipped += 1
                continue
            }

            let key = word.lowercased()
            guard !seen.contains(key) else {
                skipped += 1
                continue
            }
            seen.insert(key)
            entries.append(WordEntry(word: word, meaning: meaning))
        }

        let summary = "导入完成：新增 \(entries.count) 个单词" + (skipped > 0 ? "，跳过 \(skipped) 行（空行/重复/格式不符）" : "")
        return ImportResult(entries: entries, skipped: skipped, summary: summary)
    }

    static func isValidWord(_ word: String) -> Bool {
        let w = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !w.isEmpty, w.count <= 60 else { return false }
        // Allow letters, apostrophes, hyphens and a single space (short phrases)
        let allowed = CharacterSet.letters.union(CharacterSet(charactersIn: "'-’ "))
        let invalid = w.unicodeScalars.contains { !allowed.contains($0) }
        if invalid { return false }
        let letters = w.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        return letters >= 1
    }

    private static func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\"" {
                if inQuotes && i + 1 < chars.count && chars[i + 1] == "\"" {
                    current.append("\"")
                    i += 2
                    continue
                }
                inQuotes.toggle()
            } else if c == "," && !inQuotes {
                result.append(current)
                current = ""
            } else {
                current.append(c)
            }
            i += 1
        }
        result.append(current)
        return result
    }
}

// MARK: - Word pool assembly

enum WordPool {
    static func entries(for source: WordSource) -> [WordEntry] {
        switch source {
        case .builtinEssential:
            return BuiltinWords.essential
        case .builtinAdvanced:
            return BuiltinWords.advanced
        case .imported:
            return WordBankStore.shared.imported
        }
    }
}
