#!/usr/bin/env bash
# 把 SwiftPM 编译产物组装成 .app bundle 并做 ad-hoc 签名（无需开发者账号）。
# 若同时存在 arm64 与 x86_64 两个架构的产物，则用 lipo 合并为通用二进制。
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="UniAI"
ARM_BIN=".build/arm64-apple-macosx/release/${APP_NAME}"
X86_BIN=".build/x86_64-apple-macosx/release/${APP_NAME}"
HOST_BIN=".build/release/${APP_NAME}"

OUT_DIR="build"
mkdir -p "$OUT_DIR"
MERGED="${OUT_DIR}/${APP_NAME}-universal"

if [[ -f "$ARM_BIN" && -f "$X86_BIN" ]]; then
    echo "合并通用二进制 (arm64 + x86_64)..."
    lipo -create -output "$MERGED" "$ARM_BIN" "$X86_BIN"
    BIN="$MERGED"
elif [[ -f "$ARM_BIN" ]]; then
    BIN="$ARM_BIN"
elif [[ -f "$X86_BIN" ]]; then
    BIN="$X86_BIN"
elif [[ -f "$HOST_BIN" ]]; then
    BIN="$HOST_BIN"
else
    echo "error: 未找到编译产物，请先执行 swift build -c release" >&2
    exit 1
fi

echo "使用二进制: $BIN"
file "$BIN"

APP_DIR="${OUT_DIR}/${APP_NAME}.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "Sources/UniAI/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$BIN" "$APP_DIR/Contents/MacOS/${APP_NAME}"

# 应用图标（CI 中由 generate_icon.swift 生成；也可以手工放一份在 build/ 或 Support/ 下）
for icon in "build/AppIcon.icns" "Support/AppIcon.icns"; do
    if [[ -f "$icon" ]]; then
        cp "$icon" "$APP_DIR/Contents/Resources/AppIcon.icns"
        echo "使用图标: $icon"
        break
    fi
done

codesign --force --sign - "$APP_DIR"

echo "打包完成: $APP_DIR"
