# 📦 发布到 GitHub（已完成 · 日常用法速查）

仓库已发布：**<https://github.com/leechow007/word-explosion>**

- 远程：`origin` → `git@github.com:leechow007/word-explosion.git`（SSH）
- 本分支：`main`（已设置上游跟踪，之后直接 `git push` 即可）
- 本地作者：`leechow007 <leechow007@users.noreply.github.com>`（GitHub 隐私邮箱）

> 想改用真实邮箱：`git config user.email "你的邮箱@example.com"`

---

## 关于本机推送的 SSH 密钥（重要）

发布时使用的 SSH 密钥存放在工作区（沙箱无法写入 `~/.ssh`）：

```
/Users/leechow/workshop/word-explosion/.cache/ssh/id_ed25519
```

**推荐安装到系统目录一次**，之后在任何终端都能直接 `git push`：

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
cp /Users/leechow/workshop/word-explosion/.cache/ssh/id_ed25519 ~/.ssh/id_ed25519
chmod 600 ~/.ssh/id_ed25519
```

验证：`ssh -T git@github.com` 应显示 `Hi leechow007!`。

## 日常版本管理

```bash
cd /Users/leechow/workshop/word-explosion

git status                          # 查看改动
git add .                           # 暂存全部改动（或 git add <具体文件>）
git commit -m "feat: 增加 XX 功能"   # 提交
git push                            # 推送到 GitHub（main 已跟踪上游）
git pull                            # 拉取远端最新
```

提交信息风格（Conventional Commits）：

| 前缀 | 场景 |
|---|---|
| `feat:` | 新功能 |
| `fix:` | 修 bug |
| `docs:` | 文档 |
| `style:` / `refactor:` / `perf:` | 样式 / 重构 / 性能 |
| `chore:` | 杂务（依赖、脚本） |

常用命令：

```bash
git log --oneline           # 看提交历史
git diff                    # 看未暂存改动
git branch                  # 看分支
git checkout -b feature-x   # 建新分支干活
git merge feature-x         # 合并回主分支
git reset --soft HEAD~1     # 撤回最近一次提交（保留改动）
```

## 注意事项

- 构建产物与缓存（`dist/`、`build/`、`.cache/`、`.tmp/`）已被 `.gitignore`
  排除，不进入版本库；clone 后执行 `./scripts/build_app.sh` 即可构建 `词爆.app`。
- 若换电脑/换用户后无法推送：把 `~/.ssh/id_ed25519.pub` 公钥登记到
  <https://github.com/settings/ssh/new> 即可。
