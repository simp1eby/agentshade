#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX13.3.sdk"
MODULE_CACHE_PATH="$PROJECT_DIR/.build/ModuleCache"
APP_PATH="$PROJECT_DIR/outputs/AgentShade.app"

if [[ ! -d "$SDK_PATH" ]]; then
    SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
fi

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_PATH" swift build \
    --disable-sandbox \
    --sdk "$SDK_PATH" \
    -c release \
    --product AgentShade

BIN_PATH="$(CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_PATH" swift build --disable-sandbox --sdk "$SDK_PATH" -c release --show-bin-path)/AgentShade"

if [[ -d "$APP_PATH" ]]; then
    rm -rf "$APP_PATH"
fi
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"
cp "$BIN_PATH" "$APP_PATH/Contents/MacOS/AgentShade"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
cp "$PROJECT_DIR/Resources/AgentShade.icns" "$APP_PATH/Contents/Resources/AgentShade.icns"
codesign --force --deep --sign - "$APP_PATH"
cp "$PROJECT_DIR/README.zh-CN.md" "$PROJECT_DIR/outputs/使用说明.md"

echo "$APP_PATH"
