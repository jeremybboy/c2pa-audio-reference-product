#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
"$ROOT/scripts/configure_vst3.sh" "${1:-${LOOP_GENERATOR_JUCE_DIR:-$ROOT/.tooling/JUCE}}"
cmake --build "$ROOT/build-vst3" --config Release --parallel 4 \
    --target LoopGeneratorVST3_VST3 LoopGeneratorVST3Tests LoopGeneratorVST3HostSmoke
echo "$ROOT/build-vst3/LoopGeneratorVST3_artefacts/Release/VST3/Loop Generator.vst3"
