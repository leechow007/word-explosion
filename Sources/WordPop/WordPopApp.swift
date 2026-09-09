import SwiftUI
import AppKit

// MARK: - 菜单栏内容

struct MenuBarRootView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        // 状态头
        Text("词爆 WordPop · v0.1")
            .font(.system(size: 12, weight: .semibold))

        Text(app.running ? "距下一波 \(app.countdownText) · 运行中"
                         : "已暂停 · 点「继续」恢复倒计时")
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)

        Divider()

        Button {
            app.fireNow()
        } label: {
            Label("立即弹一波", systemImage: "bubble.right.fill")
        }

        Button {
            app.toggleRunning()
        } label: {
            Label(app.running ? "暂停弹出" : "继续弹出",
                  systemImage: app.running ? "pause.circle.fill" : "play.circle.fill")
        }

        Divider()

        Text("今日已点掉 \(StatsStore.shared.todayCount) 个单词 · 累计 \(StatsStore.shared.totalPopped)")
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)

        Divider()

        Button {
            SettingsWindowController.open()
        } label: {
            Label("设置…", systemImage: "gearshape.fill")
        }

        Button {
            NSApp.terminate(nil)
        } label: {
            Label("退出词爆", systemImage: "power")
        }
    }
}

// MARK: - App 入口

@main
struct WordPopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarRootView()
                .environmentObject(AppState.shared)
        } label: {
            Label("词爆", systemImage: "sparkles")
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Task { @MainActor in
            AppState.shared.applicationDidFinishLaunching()
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
