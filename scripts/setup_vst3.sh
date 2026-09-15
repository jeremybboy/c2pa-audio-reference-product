#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
JUCE_VERSION=8.0.12
JUCE_COMMIT=29396c22c93392d6738e021b83196283d6e4d850
TARGET="$ROOT/.tooling/JUCE"
SOURCE=${1:-${LOOP_GENERATOR_JUCE_DIR:-}}

verify_juce() {
    directory=$1
    [ -f "$directory/CMakeLists.txt" ] || return 1
    actual=$(git -C "$directory" rev-parse HEAD 2>/dev/null || true)
    [ "$actual" = "$JUCE_COMMIT" ]
}

if [ -n "$SOURCE" ]; then
    verify_juce "$SOURCE" || {
        echo "Expected JUCE $JUCE_VERSION at commit $JUCE_COMMIT: $SOURCE" >&2
        exit 2
    }
    echo "$SOURCE"
    exit 0
fi

if verify_juce "$TARGET"; then
    echo "$TARGET"
    exit 0
fi

[ ! -e "$TARGET" ] || {
    echo "Remove or repair the incomplete JUCE checkout at $TARGET" >&2
    exit 2
}
git clone --filter=blob:none https://github.com/juce-framework/JUCE.git "$TARGET"
git -C "$TARGET" checkout --detach "$JUCE_COMMIT"
verify_juce "$TARGET" || {
    echo "JUCE checkout verification failed" >&2
    exit 2
}
echo "$TARGET"
