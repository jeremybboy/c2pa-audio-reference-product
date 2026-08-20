#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_ROOT="$REPO_ROOT/build"
APP_BUNDLE="$BUILD_ROOT/Loop Generator.app"
CONTENTS="$APP_BUNDLE/Contents"
CACHE_ROOT="$REPO_ROOT/.cache"

mkdir -p \
    "$CACHE_ROOT/clang" \
    "$CACHE_ROOT/swiftpm/configuration" \
    "$CACHE_ROOT/swiftpm/security"

export CLANG_MODULE_CACHE_PATH="$CACHE_ROOT/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$CACHE_ROOT/clang"

cd "$REPO_ROOT"
swift build \
    --disable-sandbox \
    --configuration release \
    --cache-path "$CACHE_ROOT/swiftpm" \
    --config-path "$CACHE_ROOT/swiftpm/configuration" \
    --security-path "$CACHE_ROOT/swiftpm/security" \
    --scratch-path "$REPO_ROOT/.build"

mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources/runtime/stable_audio"
cp "$REPO_ROOT/.build/release/LoopGenerator" "$CONTENTS/MacOS/LoopGenerator"
cp "$REPO_ROOT/packaging/Info.plist" "$CONTENTS/Info.plist"
cp "$REPO_ROOT/runtime/stable_audio/infer.py" "$CONTENTS/Resources/runtime/stable_audio/infer.py"
cp "$REPO_ROOT/runtime/stable_audio/requirements.txt" "$CONTENTS/Resources/runtime/stable_audio/requirements.txt"
chmod +x "$CONTENTS/MacOS/LoopGenerator" "$CONTENTS/Resources/runtime/stable_audio/infer.py"
codesign --force --deep --sign - "$APP_BUNDLE"

echo "$APP_BUNDLE"
