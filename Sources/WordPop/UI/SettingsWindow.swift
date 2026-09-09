import AppKit
import SwiftUI

// MARK: - 设置窗口

@MainActor
enum SettingsWindowController {
    private static var window: NSWindow?

    static func open() {
        if window == nil {
            let root = NSHostingController(
                rootView: SettingsRootView().environmentObject(AppState.shared)
            )
            let win = NSWindow(contentViewController: root)
            win.title = "词爆设置"
            win.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            win.titlebarAppearsTransparent = true
            win.titleVisibility = .hidden
            win.isReleasedWhenClosed = false
            win.setContentSize(NSSize(width: 820, height: 640))
            win.minSize = NSSize(width: 820, height: 560)
            win.center()
            window = win
        }
        if let win = window {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    static func close() {
        window?.orderOut(nil)
    }
}

// MARK: - 根视图

enum SettingsPage: String, CaseIterable, Identifiable {
    case general
    case library
    case appearance
    case stats
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "通用"
        case .library: return "词库"
        case .appearance: return "外观"
        case .stats: return "统计"
        case .about: return "关于"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .library: return "books.vertical"
        case .appearance: return "paintpalette"
        case .stats: return "chart.bar.xaxis"
        case .about: return "info.circle"
        }
    }
}

struct SettingsRootView: View {
    @State private var page: SettingsPage = .general

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(page: $page)
                .frame(width: 212)
            Divider()
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                Group {
                    switch page {
                    case .general: GeneralPage()
                    case .library: LibraryPage()
                    case .appearance: AppearancePage()
                    case .stats: StatsPage()
                    case .about: AboutPage()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(minWidth: 820, minHeight: 640)
        .padding(.top, 34)   // 给透明标题栏的交通灯让位
    }
}

// MARK: - 侧边栏

struct SidebarView: View {
    @Binding var page: SettingsPage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 11) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LinearGradient(colors: [AppPalette.accent("#6D6AF6"),
                                                   AppPalette.accent("#FF8FB2")],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 34, height: 34)
                    .overlay {
                        Image(systemName: "sparkles")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                VStack(alignment: .leading, spacing: 1) {
                    Text("词爆")
                        .font(.system(size: 15, weight: .bold))
                    Text("WordPop")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 16)

            ForEach(SettingsPage.allCases) { item in
                Button {
                    withAnimation(.easeOut(duration: 0.16)) {
                        page = item
                    }
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 13.5, weight: .medium))
                            .frame(width: 20)
                        Text(item.title)
                            .font(.system(size: 13.5, weight: page == item ? .semibold : .regular))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(page == item ? AppPalette.accent("#5E5CE6") : Color.primary.opacity(0.8))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(page == item ? AppPalette.accent("#5E5CE6").opacity(0.12) : Color.clear)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 9)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 3) {
                Text("词爆 WordPop")
                    .font(.system(size: 11.5, weight: .semibold))
                Text("v0.1 · 本地运行 · 无网络")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
        }
        .padding(.top, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - 通用小组件

struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.3)
            Text(subtitle)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 20)
    }
}

struct SettingRow<Content: View>: View {
    let title: String
    var hint: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                if let hint {
                    Text(hint)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            content
        }
        .padding(.vertical, 13)
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                }
        }
    }
}

struct SectionCaption: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.4)
            .padding(.top, 4)
    }
}
