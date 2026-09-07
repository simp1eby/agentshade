#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
MODULE_CACHE_PATH="$PROJECT_DIR/.build/ModuleCache"
SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX13.3.sdk"

if [[ ! -d "$SDK_PATH" ]]; then
    SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
fi

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_PATH" swift build \
    --disable-sandbox \
    --sdk "$SDK_PATH" \
    -c debug \
    --product AgentShadeCoreChecks

BIN_PATH="$(
    CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_PATH" swift build \
        --disable-sandbox \
        --sdk "$SDK_PATH" \
        -c debug \
        --show-bin-path
)"

"$BIN_PATH/AgentShadeCoreChecks"
