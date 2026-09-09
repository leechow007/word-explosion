#!/bin/bash
# 词爆 WordPop 一键构建脚本：编译 → 图标 → .app 装配 → 广告签名
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUILD="$ROOT/build"
APP="$ROOT/dist/词爆.app"
MODCACHE="$ROOT/.cache/module"
export TMPDIR="$ROOT/.tmp"

mkdir -p "$BUILD" "$MODCACHE" "$ROOT/dist" "$TMPDIR"

echo "==> 1/5 生成应用图标"
xcrun swiftc scripts/make_icon.swift -module-cache-path "$MODCACHE" -o "$BUILD/iconmaker"
"$BUILD/iconmaker" "$BUILD"

ICONSET="$BUILD/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
sips -z 16 16      "$BUILD/icon-1024.png" --out "$ICONSET/icon_16x16.png"      >/dev/null
sips -z 32 32      "$BUILD/icon-1024.png" --out "$ICONSET/icon_16x16@2x.png"   >/dev/null
sips -z 32 32      "$BUILD/icon-1024.png" --out "$ICONSET/icon_32x32.png"      >/dev/null
sips -z 64 64      "$BUILD/icon-1024.png" --out "$ICONSET/icon_32x32@2x.png"   >/dev/null
sips -z 128 128    "$BUILD/icon-1024.png" --out "$ICONSET/icon_128x128.png"    >/dev/null
sips -z 256 256    "$BUILD/icon-1024.png" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256    "$BUILD/icon-1024.png" --out "$ICONSET/icon_256x256.png"    >/dev/null
sips -z 512 512    "$BUILD/icon-1024.png" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512    "$BUILD/icon-1024.png" --out "$ICONSET/icon_512x512.png"    >/dev/null
cp "$BUILD/icon-1024.png" "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$BUILD/AppIcon.icns"
echo "    图标完成: build/AppIcon.icns"

echo "==> 2/5 编译 (release, arm64)"
FILES=$(find Sources/WordPop -name '*.swift' | sort)
xcrun swiftc -parse-as-library \
    -module-cache-path "$MODCACHE" \
    -O $FILES -o "$BUILD/WordPop"
echo "    二进制完成: build/WordPop"

echo "==> 3/5 装配 $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/WordPop" "$APP/Contents/MacOS/WordPop"
cp "$BUILD/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
    <key>CFBundleExecutable</key><string>WordPop</string>
    <key>CFBundleIdentifier</key><string>com.wordpop.desktop</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>WordPop</string>
    <key>CFBundleDisplayName</key><string>词爆</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.education</string>
    <key>NSHumanReadableCopyright</key><string>© 2026 词爆 WordPop. 用爱发电.</string>
</dict>
</plist>
PLIST

echo "==> 4/5 广告签名"
codesign --force --sign - "$APP" 2>/dev/null
echo "==> 5/5 完成 ✅"
echo "应用位置: $APP"
echo "运行: open \"$APP\""
