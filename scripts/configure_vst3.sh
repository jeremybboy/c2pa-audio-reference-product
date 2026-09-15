#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
JUCE_DIR=${1:-${LOOP_GENERATOR_JUCE_DIR:-$ROOT/.tooling/JUCE}}

[ -f "$JUCE_DIR/CMakeLists.txt" ] || {
    echo "JUCE is missing; run scripts/setup_vst3.sh or pass its source path." >&2
    exit 2
}

cmake -S "$ROOT" -B "$ROOT/build-vst3" -G "Unix Makefiles" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DLOOP_GENERATOR_JUCE_DIR="$JUCE_DIR" \
    -DBUILD_TESTING=ON
