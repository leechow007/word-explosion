import AppKit
import SwiftUI
import Charts
import UniformTypeIdentifiers

// MARK: - 通用页

struct GeneralPage: View {
    @EnvironmentObject private var app: AppState

    private var intervalBinding: Binding<Double> {
        Binding(
            get: { Double(app.settings.intervalMinutes) },
            set: { app.settings.intervalMinutes = Int($0) }
        )
    }

    private var wordsBinding: Binding<Double> {
        Binding(
            get: { Double(app.settings.wordsPerWave) },
            set: { app.settings.wordsPerWave = Int($0) }
        )
    }

    private var ttlBinding: Binding<Double> {
        Binding(
            get: { Double(app.settings.ttlMinutes) },
            set: { app.settings.ttlMinutes = Int($0) }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "通用",
                           subtitle: "节奏由你定——弹出频率、每波数量与自动飘走的时长。")

                SettingsCard {
                    SettingRow(title: "弹出间隔", hint: "每过多久自动弹出一波新单词") {
                        HStack(spacing: 14) {
                            Text("\(app.settings.intervalMinutes) 分钟")
                                .font(.system(size: 15, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(AppPalette.accent(app.settings.accentHex))
                                .frame(minWidth: 78, alignment: .trailing)
                            Slider(value: intervalBinding, in: 1 ... 180, step: 1)
                                .frame(width: 200)
                        }
                    }
                    Divider()
                    SettingRow(title: "每波词数", hint: "同时浮在屏幕上的单词数量") {
                        HStack(spacing: 14) {
                            Text("\(app.settings.wordsPerWave) 个")
                                .font(.system(size: 15, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(AppPalette.accent(app.settings.accentHex))
                                .frame(minWidth: 78, alignment: .trailing)
                            Slider(value: wordsBinding, in: 4 ... 16, step: 1)
                                .frame(width: 200)
                        }
                    }
                    Divider()
                    SettingRow(title: "留存时长", hint: "没被点爆的词泡多久后自动飘走") {
                        HStack(spacing: 14) {
                            Text("\(app.settings.ttlMinutes) 分钟")
                                .font(.system(size: 15, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(AppPalette.accent(app.settings.accentHex))
                                .frame(minWidth: 78, alignment: .trailing)
                            Slider(value: ttlBinding, in: 1 ... 15, step: 1)
                                .frame(width: 200)
                        }
                    }
                }

                SectionCaption(text: "行为")
                SettingsCard {
                    Toggle(isOn: $app.settings.clearRemainderBeforeNewWave) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("新一波前先让残留词泡飘走")
                                .font(.system(size: 13.5, weight: .semibold))
                            Text("保持桌面清爽；关闭后可叠加最多 24 个词泡")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .toggleStyle(.switch)
                    .padding(.vertical, 12)

                    Divider()

                    Toggle(isOn: $app.settings.autoStartOnLaunch) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("启动时自动开始")
                                .font(.system(size: 13.5, weight: .semibold))
                            Text("打开 App 后立即进入定时循环")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .toggleStyle(.switch)
                    .padding(.vertical, 12)

                    Divider()

                    Toggle(isOn: $app.settings.hapticsEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("点爆时触感反馈")
                                .font(.system(size: 13.5, weight: .semibold))
                            Text("在支持的 Mac 上提供轻触反馈")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .toggleStyle(.switch)
                    .padding(.vertical, 12)
                }

                HStack(spacing: 12) {
                    Button {
                        app.fireNow()
                    } label: {
                        Label("立即试弹一波", systemImage: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppPalette.accent(app.settings.accentHex))

                    Button {
                        app.clearAllBubbles()
                    } label: {
                        Label("清空当前词泡", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 4)

                Text("设置即时生效：修改间隔后，下一波会按新间隔重新计时。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(.horizontal, 34)
            .padding(.vertical, 26)
        }
    }
}

// MARK: - 词库页

struct LibraryPage: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject private var store = WordBankStore.shared

    @State private var resultMessage: String?
    @State private var confirmClear = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "词库", subtitle: "选择词源，或导入你自己的 TXT / CSV 单词本。")

                SectionCaption(text: "词库来源")
                Picker("", selection: $app.settings.source) {
                    ForEach(WordSource.allCases) { source in
                        Label(source.title, systemImage: source.symbol)
                            .tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                sourceSummary
                Divider()

                HStack(spacing: 10) {
                    Button {
                        importFile()
                    } label: {
                        Label("导入 TXT / CSV", systemImage: "square.and.arrow.down")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppPalette.accent(app.settings.accentHex))

                    if app.settings.source == .imported, !store.imported.isEmpty {
                        Button("清空我的词本", role: .destructive) {
                            confirmClear = true
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if app.settings.source == .imported {
                    importedList
                }

                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 9) {
                        formatRow("word", "abandon  放弃", "TXT 每行一个单词；可用空格/Tab 分隔中文释义")
                        formatRow("csv", "abandon,放弃", "CSV 第一列为单词，第二列为释义（支持引号与 UTF-8 BOM）")
                        formatRow("comment", "# 开头是注释", "空行与 # 注释行会被自动忽略")
                        formatRow("dedupe", "重复词自动去重", "大小写不敏感；每行只保留第一个释义")
                    }
                    .padding(.top, 4)
                } label: {
                    Label("支持的文件格式", systemImage: "doc.text.magnifyingglass")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 10)
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(.horizontal, 34)
            .padding(.vertical, 26)
        }
        .alert(resultMessage ?? "", isPresented: Binding(
            get: { resultMessage != nil },
            set: { if !$0 { resultMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        }
        .confirmationDialog("确定清空我的词本吗？", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("清空全部 \(store.imported.count) 个单词", role: .destructive) {
                store.clearImported()
            }
        } message: {
            Text("删除后需要重新导入，此操作无法撤销。")
        }
    }

    private func formatRow(_ symbol: String, _ sample: String, _ explain: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(sample)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(AppPalette.accent("#5E5CE6"))
                .frame(minWidth: 190, alignment: .leading)
            Text(explain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var sourceSummary: some View {
        let entries = WordPool.entries(for: app.settings.source)
        SettingsCard {
            HStack(spacing: 14) {
                Image(systemName: app.settings.source.symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(AppPalette.accent(app.settings.accentHex))
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.settings.source.title)
                        .font(.system(size: 13.5, weight: .semibold))
                    Text(entries.isEmpty ? "词库为空，定时弹出会暂停等待补充"
                         : "共 \(entries.count) 个单词 · 每波随机抽取 \(app.settings.wordsPerWave) 个，已点爆的词近期不重复出现")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text("\(entries.count)")
                    .font(.system(size: 21, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(AppPalette.accent(app.settings.accentHex))
                Text("词")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 9)
        }
    }

    @ViewBuilder
    private var importedList: some View {
        if store.imported.isEmpty {
            SettingsCard {
                HStack(spacing: 10) {
                    Image(systemName: "tray")
                        .foregroundStyle(.secondary)
                    Text("还没有导入任何单词。点击上方按钮选择你的词本文件。")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 12)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                SectionCaption(text: "我的词本 · \(store.imported.count) 词")
                SettingsCard {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(store.imported) { entry in
                                HStack(spacing: 12) {
                                    Text(entry.word)
                                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                                        .frame(minWidth: 120, alignment: .leading)
                                    Text(entry.meaning)
                                        .font(.system(size: 12.5))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    Spacer(minLength: 8)
                                    Button {
                                        store.remove(ids: [entry.id])
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 11.5))
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.vertical, 7)
                                if entry.id != store.imported.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                }
            }
        }
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.title = "导入单词本"
        panel.message = "选择 UTF-8 编码的 .txt 或 .csv 文件"
        panel.allowedContentTypes = [.plainText, .commaSeparatedText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let result = WordImportParser.parse(url: url)

            var merged = store.imported
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
            store.replaceImported(with: merged)
            app.statsRevision += 1

            var summary = result.summary
            if duplicate > 0 {
                summary += "；与词本已有 \(duplicate) 条重复"
            }
            summary += "。当前词本共 \(store.imported.count) 词。"
            resultMessage = summary
        }
    }
}

// MARK: - 外观页

struct AppearancePage: View {
    @EnvironmentObject private var app: AppState

    private var accentColorBinding: Binding<Color> {
        Binding(
            get: { AppPalette.accent(app.settings.accentHex) },
            set: { app.settings.accentHex = $0.hexString }
        )
    }

    private var backgroundBinding: Binding<Color> {
        Binding(
            get: { Color(hex: app.settings.bubbleBackgroundHex) },
            set: { app.settings.bubbleBackgroundHex = $0.hexString }
        )
    }

    private var currentAccentName: String {
        if let preset = AppPalette.accentOptions.first(where: { $0.hex.caseInsensitiveCompare(app.settings.accentHex) == .orderedSame }) {
            return preset.name
        }
        return "自定义"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "外观", subtitle: "让词泡在壁纸上依然好看——玻璃、渐变与强调色。")

                SectionCaption(text: "词泡主题")
                HStack(spacing: 14) {
                    ForEach(BubbleTheme.allCases) { theme in
                        ThemeCard(theme: theme,
                                  accentHex: app.settings.accentHex,
                                  selected: app.settings.theme == theme) {
                            app.settings.theme = theme
                        }
                    }
                }

                SectionCaption(text: "强调色")
                SettingsCard {
                    HStack(spacing: 14) {
                        ForEach(AppPalette.accentOptions, id: \.hex) { option in
                            Button {
                                app.settings.accentHex = option.hex
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(AppPalette.accent(option.hex))
                                        .frame(width: 26, height: 26)
                                        .overlay {
                                            if app.settings.accentHex == option.hex {
                                                Circle().strokeBorder(.white, lineWidth: 2)
                                                    .frame(width: 26, height: 26)
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 11, weight: .bold))
                                                    .foregroundStyle(.white)
                                            }
                                        }
                                }
                            }
                            .buttonStyle(.plain)
                            .help(option.name)
                        }
                        Spacer()
                        VStack(spacing: 2) {
                            ColorPicker("", selection: accentColorBinding, supportsOpacity: false)
                                .labelsHidden()
                                .frame(width: 42)
                            Text("自定义")
                                .font(.system(size: 9.5))
                                .foregroundStyle(.tertiary)
                        }
                        Text(currentAccentName)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 62, alignment: .leading)
                    }
                    .padding(.vertical, 11)
                }

                SectionCaption(text: "词泡背景")
                SettingsCard {
                    SettingRow(title: "背景颜色", hint: "可任选颜色，文字会自动转为黑或白以保证可读") {
                        HStack(spacing: 12) {
                            ColorPicker("", selection: backgroundBinding, supportsOpacity: false)
                                .labelsHidden()
                                .frame(width: 42)
                            Text(app.settings.bubbleBackgroundHex.uppercased())
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 76, alignment: .leading)
                            Button("恢复默认") {
                                app.settings.bubbleBackgroundHex = "#FFFFFF"
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    Divider()
                    SettingRow(title: "背景不透明度", hint: "越低越通透；越高越清晰、越不干扰阅读") {
                        HStack(spacing: 14) {
                            Text("\(Int((app.settings.bubbleFillOpacity * 100).rounded()))%")
                                .font(.system(size: 15, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(AppPalette.accent(app.settings.accentHex))
                                .frame(minWidth: 52, alignment: .trailing)
                            Slider(value: $app.settings.bubbleFillOpacity, in: 0.10 ... 1.0)
                                .frame(width: 190)
                        }
                    }
                }

                SectionCaption(text: "词泡文字")
                SettingsCard {
                    SettingRow(title: "字号", hint: "词泡内英文单词的大小") {
                        Picker("", selection: $app.settings.fontSize) {
                            ForEach(BubbleFontSize.allCases) { size in
                                Text(size.title).tag(size)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 170)
                        .labelsHidden()
                    }
                    Divider()
                    SettingRow(title: "字体风格", hint: "圆体更活泼，衬线更书卷气") {
                        Picker("", selection: $app.settings.serifFont) {
                            Text("现代圆体").tag(false)
                            Text("经典衬线").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 170)
                        .labelsHidden()
                    }
                }

                SectionCaption(text: "实时预览")
                LiveBubblePreview()
                    .padding(.bottom, 30)
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(.horizontal, 34)
            .padding(.vertical, 26)
        }
    }
}

struct ThemeCard: View {
    let theme: BubbleTheme
    let accentHex: String
    let selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .quaternarySystemFill))
                    miniCapsule
                }
                .frame(width: 138, height: 64)

                VStack(alignment: .leading, spacing: 1) {
                    Text(theme.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                    Text(theme.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .strokeBorder(selected ? AppPalette.accent(accentHex) : Color.primary.opacity(0.08),
                                          lineWidth: selected ? 2 : 1)
                    }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var miniCapsule: some View {
        switch theme {
        case .glassLight:
            capsule(over: AnyView(
                Capsule().fill(
                    LinearGradient(stops: [
                        .init(color: .white.opacity(0.72), location: 0.00),
                        .init(color: .white.opacity(0.58), location: 1.00)
                    ], startPoint: .top, endPoint: .bottom)
                )
            ), textColor: AppPalette.ink, accent: AppPalette.accent(accentHex))
        case .glassDark:
            capsule(over: AnyView(
                Capsule().fill(LinearGradient(colors: [.black.opacity(0.5), .black.opacity(0.3)],
                                              startPoint: .top, endPoint: .bottom))
            ), textColor: .white, accent: AppPalette.accent(accentHex))
        case .aurora:
            capsule(over: AnyView(
                Capsule().fill(LinearGradient(colors: [AppPalette.accent(accentHex).opacity(0.95),
                                                       AppPalette.partner(for: accentHex)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
            ), textColor: .white, accent: AppPalette.accent(accentHex))
        }
    }

    private func capsule(over fill: AnyView, textColor: Color, accent: Color) -> some View {
        ZStack {
            fill
            Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.8), .white.opacity(0.1)],
                                                  startPoint: .top, endPoint: .bottom), lineWidth: 1)
            Text("Word")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(textColor)
        }
        .frame(width: 88, height: 34)
        .shadow(color: accent.opacity(0.35), radius: 7, y: 3)
    }
}

struct LiveBubblePreview: View {
    @EnvironmentObject private var app: AppState

    private var appearance: BubbleAppearance { BubbleAppearance.from(settings: app.settings) }

    var body: some View {
        SettingsCard {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.4))

                // 直接复用真实词泡组件，所见即所得（含自定义背景色与不透明度）
                BubbleCapsuleView(appearance: appearance, text: "serendipity")
                    .scaleEffect(1.02)
            }
            .frame(maxWidth: .infinity, minHeight: 132)
        }
    }
}

// MARK: - 统计页

struct StatsPage: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "统计", subtitle: "每一次双击点爆，都是一次主动回忆。")

                HStack(spacing: 12) {
                    statCard(value: "\(StatsStore.shared.todayCount)",
                             label: "今日点掉", symbol: "hand.tap.fill",
                             tint: AppPalette.accent(app.settings.accentHex))
                    statCard(value: "\(StatsStore.shared.totalPopped)",
                             label: "累计点掉", symbol: "flame.fill",
                             tint: AppPalette.accent("#FF6482"))
                    statCard(value: "\(StatsStore.shared.totalWaves)",
                             label: "弹出波次", symbol: "sparkles",
                             tint: AppPalette.accent("#BF5AF2"))
                }

                SectionCaption(text: "近 7 日点掉趋势")
                SettingsCard {
                    chart
                        .padding(.vertical, 14)
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(.horizontal, 34)
            .padding(.vertical, 26)
        }
    }

    private func statCard(value: String, label: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 27, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.primary)
            Text(label)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                }
        }
    }

    @ViewBuilder
    private var chart: some View {
        let data = StatsStore.shared.lastDays(7)
        if data.allSatisfy({ $0.count == 0 }) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar")
                    .foregroundStyle(.secondary)
                Text("还没有数据——双击点爆第一颗词泡后，这里会长出小柱子。")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
            .frame(height: 190)
        } else {
            Chart(data) { item in
                BarMark(
                    x: .value("日期", item.day, unit: .day),
                    y: .value("点掉", item.count)
                )
                .foregroundStyle(
                    LinearGradient(colors: [AppPalette.accent(app.settings.accentHex),
                                            AppPalette.accent(app.settings.accentHex).opacity(0.35)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .cornerRadius(6)
                .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                    if item.count > 0 {
                        Text("\(item.count)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .offset(y: -2)
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 190)
        }
    }
}

// MARK: - 关于页

struct AboutPage: View {
    @EnvironmentObject private var app: AppState

    private var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.1.0"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "关于", subtitle: "让背单词成为桌面上最轻、最好看的打扰。")

                VStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(LinearGradient(colors: [AppPalette.accent("#6D6AF6"),
                                                      AppPalette.accent("#FF8FB2")],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 88, height: 88)
                        .overlay {
                            Image(systemName: "sparkles")
                                .font(.system(size: 38, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .shadow(color: AppPalette.accent("#5E5CE6").opacity(0.35), radius: 18, y: 8)
                    Text("词爆 WordPop")
                        .font(.system(size: 20, weight: .bold))
                    Text("版本 \(version) · 为 Apple Silicon 原生打造")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                    Text("单词像泡泡一样冒出来 · hover 回忆 · 双击点爆")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(AppPalette.accent("#5E5CE6"))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

                SettingsCard {
                    factRow("lock.shield", "本地优先", "词库与统计只存在你的 Mac 上，无网络、无追踪。")
                    Divider()
                    factRow("cursorarrow.click.2", "随手完成", "鼠标穿透悬浮，边工作边双击，不打断输入。")
                    Divider()
                    factRow("sparkles", "审美驱动", "玻璃词泡 + 粒子点爆，复习也可以很好看。")
                }

                SettingsCard {
                    Button {
                        app.resetSettings()
                    } label: {
                        Label("恢复默认设置", systemImage: "arrow.counterclockwise")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .padding(.vertical, 6)
                }

                Text("词爆 WordPop · v0.1 · 用爱发电 💙")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(.horizontal, 34)
            .padding(.vertical, 26)
        }
    }

    private func factRow(_ symbol: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppPalette.accent("#5E5CE6"))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                Text(body)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
    }
}
