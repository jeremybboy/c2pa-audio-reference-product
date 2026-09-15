#!/bin/sh
set -eu

BUNDLE=${1:?usage: scripts/validate_vst3.sh path/to/Loop Generator.vst3}
BINARY="$BUNDLE/Contents/MacOS/Loop Generator"
SCRIPT="$BUNDLE/Contents/Resources/runtime/stable_audio/infer.py"

[ -d "$BUNDLE" ]
[ -f "$BINARY" ]
[ -x "$SCRIPT" ]
file "$BINARY" | grep -q "Mach-O 64-bit bundle arm64"
codesign --verify --deep --strict --verbose=2 "$BUNDLE"
plutil -extract CFBundleIdentifier raw "$BUNDLE/Contents/Info.plist" \
    | grep -qx "com.loopgenerator.vst3"
find "$BUNDLE" -type f \( -name '*.key' -o -name '*.pem' -o -name '*.p12' -o -name '*.pfx' \) \
    | grep -q . && {
        echo "Signing material must not be packaged in the VST3." >&2
        exit 2
    }
echo "VST3 bundle validation passed: $BUNDLE"
