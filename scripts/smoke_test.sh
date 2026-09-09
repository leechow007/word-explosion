#!/bin/bash
# 冒烟自测：构建 + 启动演示模式（自动弹一波，9 秒后自退）+ 进程/窗口验证
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export TMPDIR="$ROOT/.tmp"
mkdir -p "$TMPDIR"

./scripts/build_app.sh >/dev/null 2>&1 || { echo "BUILD FAILED"; exit 1; }

pkill -f "词爆.app/Contents/MacOS/WordPop" 2>/dev/null
sleep 1

WORDPOP_SMOKE=1 WORDPOP_SMOKE_QUIT=1 "dist/词爆.app/Contents/MacOS/WordPop" \
    >/tmp/wordpop.log 2>&1 &
APP_PID=$!
echo "launched pid=$APP_PID"

sleep 3
echo "--- process ---"
pgrep -fl "词爆.app" || echo "NOT RUNNING"

echo "--- app log ---"
cat /tmp/wordpop.log

sleep 4
echo "--- windows (owner=词爆/WordPop) ---"
BIN="$ROOT/build/wincheck"
xcrun swiftc "$ROOT/scripts/wincheck.swift" -module-cache-path "$ROOT/.cache/module" -o "$BIN" 2>/dev/null
"$BIN" 2>/dev/null | grep -iE "wordpop|词爆" | head -20 || echo "(no window list)"

echo "--- final ---"
sleep 3
if kill -0 "$APP_PID" 2>/dev/null; then
    echo "still running after quit window; will kill"
    kill "$APP_PID" 2>/dev/null
else
    echo "app exited cleanly after smoke (auto-quit)"
fi
