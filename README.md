# 词爆 WordPop 🫧

> 让背单词成为桌面上**最轻、最好看的打扰**。
> macOS 菜单栏常驻小工具：按节奏把英文单词像泡泡一样喷到屏幕上——**hover 看释义，双击点爆**，鼠标穿透不打扰工作。

原生 SwiftUI + AppKit 构建 · Apple Silicon 原生支持 · 零第三方依赖 · 全本地运行

---

## ✨ 功能一览

- ⏱️ **定时弹出**：1–180 分钟可调，倒计时实时显示在菜单栏；也可以随时「立即弹一波」
- 🫧 **悬浮词泡**：玻璃拟态胶囊，随机散布在多屏可见区、互不重叠，带柔和浮动与弹簧入场
- 👀 **hover 出释义**：鼠标悬停 0.25s 弹出释义卡（英文 + 中文 + 🔊 发音），移开即消失
- 💥 **双击点爆**：粒子迸发动画 + 触感反馈（可关），点掉一个记一个
- 🍃 **自动飘走**：没点爆的词泡留存 N 分钟后优雅上飘消失，桌面永远干净
- 📚 **双词库**：内置「基础精选 110 + 进阶精选 90」共 200 条，或导入自己的 TXT/CSV 词本
- 🎨 **三套主题**：晨雾 Glass / 午夜 Glass / 晚霞 Aurora ＋ 8 色强调色、字号与字体
- 📊 **轻统计**：今日 / 累计点掉、弹出波次、近 7 日柱状图

---

## 🚀 快速开始

### 方式一：直接运行打包好的 App

```bash
open "dist/词爆.app"
```

菜单栏会出现 ✦ 图标；默认每 20 分钟弹 6 个词（通用设置里可改）。

### 方式二：一键构建（需要 Xcode Command Line Tools）

```bash
./scripts/build_app.sh
open "dist/词爆.app"
```

脚本会依次：生成图标 → release 编译 → 装配 `.app` → 广告签名。

### 方式三：用 Xcode 打开工程开发

```bash
open Package.swift
```

### 冒烟自测

```bash
./scripts/smoke_test.sh    # 启动 App → 自动弹一波 → 9 秒后自退，验证词泡窗口
```

---

## 🖱️ 使用说明

| 操作 | 说明 |
|---|---|
| 点击菜单栏 ✦ | 查看倒计时、今日战绩 |
| 立即弹一波 | 无视计时立刻弹出，不重置周期 |
| hover 词泡 | 约 0.25s 后显示释义卡；点 🔊 发音 |
| 双击词泡 | 点爆！粒子动画 + 计数 +1 |
| 不理它 | 到「留存时长」自动飘走 |
| 暂停 / 继续 | 冻结并恢复倒计时 |

### 词库格式（TXT / CSV，UTF-8）

```
# 这是注释，会被忽略
abandon  放弃            ← 单词 + 空格 + 中文
resilient	韧性的          ← 也可以用 Tab 分隔
candid,坦率的           ← CSV：第一列单词，第二列释义
serendipity              ← 只有单词也可以（释义显示「暂无」）
```

导入后自动去重（大小写不敏感），可从「设置 → 词库 → 我的词本」删除或清空。

---

## 🗂️ 项目结构

```
word-explosion/
├── PRD.md                     # 产品需求文档
├── DESIGN.md                  # 视觉与交互设计规范（玻璃拟态/动效/组件）
├── PLAN.md                    # 项目计划
├── docs/
│   ├── mockup.html            # 高保真 UI 稿（浏览器打开）
│   └── mockup-preview.png     # 视觉稿截图
├── Package.swift              # SwiftPM 工程（供 Xcode 打开）
├── Sources/WordPop/
│   ├── WordPopApp.swift       # 入口 + MenuBarExtra
│   ├── AppState.swift         # 调度 / 设置 / 冒烟测试钩子
│   ├── Models.swift           # 模型、解析、词库与统计存储
│   ├── Data/BuiltinWords.swift# 内置 200 词精选分级词库
│   ├── Overlay/               # 悬浮层引擎（词泡/释义卡/点爆粒子）
│   └── UI/                    # 主题、设置窗口五页、菜单栏
├── scripts/
│   ├── build_app.sh           # 一键构建 .app
│   ├── smoke_test.sh          # 冒烟自测
│   ├── make_icon.swift        # App 图标生成
│   └── wincheck.swift         # 窗口验证小工具
├── dist/词爆.app              # 构建产物
└── README.md
```

> 注：本仓库 `swift build` 直连 SwiftPM 时若沙箱限制模块缓存，请使用
> `scripts/build_app.sh`（已内置 `-module-cache-path`）或 Xcode 构建。

---

## 🔮 Roadmap（v0.2 → v1.0）

- 记忆曲线：点爆后按 1/2/4/7 天间隔复现，「总是点不掉」的词重点复习
- 四级 / 六级 / 考研 / 雅思完整分级词库与释义增强（音标、词性、例句）
- 导入 Anki / 欧陆词典导出格式；导出学习进度
- 全局热键（⌥W 立即弹一波 / 暂停）；「减弱动态效果」完整适配

## 🤍 致谢与说明

- 数据与设置仅存于本机（`~/Library/Application Support/WordPop`），无网络、无追踪。
- 图标与界面为原创设计，遵循 `DESIGN.md` 的玻璃拟态语言。
- v0.1 为个人学习工具，未做公证签名，首次打开请右键 → 打开（或系统设置允许）。

## 📄 License

[MIT License](LICENSE) · Copyright (c) 2026 leechow007

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
