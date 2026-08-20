#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNTIME_DIR="$REPO_ROOT/runtime/stable_audio"
VERIFY_DIR="$REPO_ROOT/build/model-verification"

mkdir -p "$VERIFY_DIR"
export HF_HUB_CACHE="$RUNTIME_DIR/.model-cache"
"$RUNTIME_DIR/.venv/bin/python" "$RUNTIME_DIR/infer.py" \
    --prompt "Synth loop, warm analog pulse, instrumental, 110 BPM" \
    --seconds 4 \
    --seed 424242 \
    --output "$VERIFY_DIR/verified-loop.wav" \
    --metadata-output "$VERIFY_DIR/verified-loop.model.json"

file "$VERIFY_DIR/verified-loop.wav"
afinfo "$VERIFY_DIR/verified-loop.wav"
