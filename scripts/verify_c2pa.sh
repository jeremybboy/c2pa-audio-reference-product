#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MODEL_WAV="$REPO_ROOT/build/model-verification/verified-loop.wav"
MODEL_JSON="$REPO_ROOT/build/model-verification/verified-loop.model.json"
EVIDENCE_DIRECTORY="$REPO_ROOT/build/c2pa-evidence/v1"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$REPO_ROOT/packaging/Info.plist")"

[[ -r "$MODEL_WAV" && -r "$MODEL_JSON" ]] || {
    echo "Run ./scripts/verify_model.sh before C2PA verification." >&2
    exit 1
}

"$SCRIPT_DIR/setup_c2pa.sh" "${LOOP_GENERATOR_C2PA_SIGNING_BUNDLE:-$HOME/Downloads/test-signing-bundle.pem}"

mkdir -p \
    "$REPO_ROOT/.cache/clang" \
    "$REPO_ROOT/.cache/swiftpm/configuration" \
    "$REPO_ROOT/.cache/swiftpm/security"
export CLANG_MODULE_CACHE_PATH="$REPO_ROOT/.cache/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$REPO_ROOT/.cache/clang"

cd "$REPO_ROOT"
swift run \
    --disable-sandbox \
    --cache-path "$REPO_ROOT/.cache/swiftpm" \
    --config-path "$REPO_ROOT/.cache/swiftpm/configuration" \
    --security-path "$REPO_ROOT/.cache/swiftpm/security" \
    --scratch-path "$REPO_ROOT/.build" \
    LoopGeneratorC2PAVerify \
    "$MODEL_WAV" \
    "$MODEL_JSON" \
    "$EVIDENCE_DIRECTORY" \
    "$APP_VERSION"

afinfo "$EVIDENCE_DIRECTORY/signed-c2pa.wav" | \
    grep -E 'Data format|estimated duration|audio bytes'
echo "$EVIDENCE_DIRECTORY"
