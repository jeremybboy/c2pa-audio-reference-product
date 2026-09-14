#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SOURCE="$ROOT/build-vst3/LoopGeneratorVST3_artefacts/Release/VST3/Loop Generator.vst3"
DESTINATION="$HOME/Library/Audio/Plug-Ins/VST3/Loop Generator.vst3"
RUNTIME_SOURCE=${LOOP_GENERATOR_RUNTIME_SOURCE:-$ROOT/runtime/stable_audio}
RUNTIME_PARENT="$HOME/Library/Application Support/LoopGenerator"
RUNTIME_LINK="$RUNTIME_PARENT/runtime"

[ -d "$SOURCE" ] || {
    echo "VST3 is not built; run scripts/build_vst3.sh first." >&2
    exit 2
}
[ -x "$RUNTIME_SOURCE/.venv/bin/python" ] || {
    echo "Stable Audio runtime is missing; run scripts/setup_runtime.sh first." >&2
    exit 2
}
[ -d "$RUNTIME_SOURCE/.model-cache" ] || {
    echo "Stable Audio model cache is missing; run scripts/setup_runtime.sh first." >&2
    exit 2
}

mkdir -p "$(dirname "$DESTINATION")" "$RUNTIME_PARENT"
if [ -L "$RUNTIME_LINK" ]; then
    [ "$(readlink "$RUNTIME_LINK")" = "$RUNTIME_SOURCE" ] || {
        echo "A different LoopGenerator runtime link already exists: $RUNTIME_LINK" >&2
        exit 2
    }
elif [ -e "$RUNTIME_LINK" ]; then
    echo "A non-link runtime already exists: $RUNTIME_LINK" >&2
    exit 2
else
    ln -s "$RUNTIME_SOURCE" "$RUNTIME_LINK"
fi

ditto "$SOURCE" "$DESTINATION"
codesign --verify --deep --strict "$DESTINATION"
echo "$DESTINATION"
