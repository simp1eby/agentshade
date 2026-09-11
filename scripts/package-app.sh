#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX13.3.sdk"
MODULE_CACHE_PATH="$PROJECT_DIR/.build/ModuleCache"
APP_PATH="$PROJECT_DIR/outputs/AgentShade.app"
SIGNING_IDENTITY="${AGENTSHADE_SIGNING_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
    # Reuse the dedicated local identity when installed. Never silently fall
    # back to ad-hoc if that certificate exists but cannot currently sign.
    if security find-certificate -c "AgentShade Local Signing" >/dev/null 2>&1; then
        SIGNING_IDENTITY="AgentShade Local Signing"
    else
        SIGNING_IDENTITY="-"
    fi
fi

if [[ ! -d "$SDK_PATH" ]]; then
    SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
fi

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_PATH" swift build \
    --disable-sandbox \
    --sdk "$SDK_PATH" \
    -c release \
    --product AgentShade

BIN_PATH="$(CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_PATH" swift build --disable-sandbox --sdk "$SDK_PATH" -c release --show-bin-path)/AgentShade"

mkdir -p "$PROJECT_DIR/outputs"
PACKAGE_TEMP_DIR="$(mktemp -d "$PROJECT_DIR/outputs/.agentshade-package.XXXXXX")"
trap 'rm -rf -- "$PACKAGE_TEMP_DIR"' EXIT
STAGED_APP_PATH="$PACKAGE_TEMP_DIR/AgentShade.app"
mkdir -p "$STAGED_APP_PATH/Contents/MacOS" "$STAGED_APP_PATH/Contents/Resources"
cp "$BIN_PATH" "$STAGED_APP_PATH/Contents/MacOS/AgentShade"
cp "$PROJECT_DIR/Resources/Info.plist" "$STAGED_APP_PATH/Contents/Info.plist"
cp "$PROJECT_DIR/Resources/AgentShade.icns" "$STAGED_APP_PATH/Contents/Resources/AgentShade.icns"
codesign --force --deep --sign "$SIGNING_IDENTITY" "$STAGED_APP_PATH"
codesign --verify --strict --verbose=2 "$STAGED_APP_PATH"

# Keep the installed bundle intact if signing is denied or verification fails.
if [[ -d "$APP_PATH" ]]; then
    rm -rf "$APP_PATH"
fi
mv "$STAGED_APP_PATH" "$APP_PATH"
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    echo "Ad-hoc build: Screen Recording access may need to be granted again after rebuilding."
fi
cp "$PROJECT_DIR/README.zh-CN.md" "$PROJECT_DIR/outputs/使用说明.md"

echo "$APP_PATH"
