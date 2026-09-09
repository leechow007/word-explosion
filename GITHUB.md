# 📦 发布到 GitHub（命令行版指南）

本仓库已完成 git 初始化与首次提交，本地作者已设为：

```bash
user.name  = leechow007
user.email = leechow007@users.noreply.github.com   # GitHub 隐私邮箱
```

> 想用真实邮箱？执行一次即可：
> ```bash
> git config user.email "你的邮箱@example.com"
> ```

---

## 第 1 步：在 GitHub 网页创建空仓库（2 分钟）

1. 打开 <https://github.com/new>
2. **Repository name** 填：`word-explosion`
3. 选择 Public（公开）或 Private（私有）
4. **不要勾选** “Add a README / .gitignore / license”（仓库已有内容，避免冲突）
5. 点 **Create repository**

创建后页面会显示仓库地址（HTTPS 或 SSH 均可）。

## 第 2 步：在终端推送（1 分钟）

打开「终端」，粘贴执行（把地址换成你在第 1 步看到的）：

```bash
cd /Users/leechow/workshop/word-explosion

# HTTPS 方式（推荐，弹出登录框时用 GitHub 密码/PAT）
git remote add origin https://github.com/leechow007/word-explosion.git

# 或 SSH 方式（需已配置 SSH key）
# git remote add origin git@github.com:leechow007/word-explosion.git

git push -u origin main
```

如果 HTTPS 推送要求认证：推荐先装 GitHub CLI 并登录一次，之后永久免密：

```bash
brew install gh
gh auth login     # 选 GitHub.com → HTTPS → 浏览器登录
```

---

## 日常版本管理（推荐习惯）

```bash
git status                          # 查看改动
git add .                           # 暂存全部改动（或用 git add <具体文件>）
git commit -m "feat: 增加 XX 功能"   # 提交
git push                            # 推送到 GitHub
git pull                            # 拉取远端最新
```

提交信息风格建议（Conventional Commits）：

| 前缀 | 场景 |
|---|---|
| `feat:` | 新功能 |
| `fix:` | 修 bug |
| `docs:` | 文档 |
| `style:` / `refactor:` / `perf:` | 样式 / 重构 / 性能 |
| `chore:` | 杂务（依赖、脚本） |

常用版本管理命令：

```bash
git log --oneline           # 看提交历史
git diff                    # 看未暂存改动
git branch                  # 看分支
git checkout -b feature-x   # 建新分支干活
git merge feature-x         # 合并回主分支
git reset --soft HEAD~1     # 撤回最近一次提交（保留改动）
```

## 注意事项

- 构建产物（`dist/`、`build/`）已被 `.gitignore` 忽略，不进入版本库；
  别人 clone 后执行 `./scripts/build_app.sh` 即可得到 `词爆.app`。
- 仓库中的 `.cache/`、`.tmp/` 是本地编译缓存，同样不会被提交。
- 首次 push 后想检查结果：浏览器打开
  <https://github.com/leechow007/word-explosion>。
