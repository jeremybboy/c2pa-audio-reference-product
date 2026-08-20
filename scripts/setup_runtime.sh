#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNTIME_DIR="$REPO_ROOT/runtime/stable_audio"
TOOLING_DIR="$REPO_ROOT/.tooling"
UV_BOOTSTRAP="$TOOLING_DIR/uv-bootstrap"
UV_CACHE_DIR="$REPO_ROOT/.cache/uv"
UV_PYTHON_INSTALL_DIR="$TOOLING_DIR/python"
MODEL_CACHE="$RUNTIME_DIR/.model-cache"

mkdir -p "$TOOLING_DIR" "$UV_CACHE_DIR" "$MODEL_CACHE"

if command -v uv >/dev/null 2>&1; then
    UV_BIN="$(command -v uv)"
else
    if [[ ! -x "$UV_BOOTSTRAP/bin/uv" ]]; then
        python3 -m venv "$UV_BOOTSTRAP"
        "$UV_BOOTSTRAP/bin/python" -m pip install --disable-pip-version-check uv
    fi
    UV_BIN="$UV_BOOTSTRAP/bin/uv"
fi

export UV_CACHE_DIR
export UV_PYTHON_INSTALL_DIR
"$UV_BIN" python install 3.10
"$UV_BIN" venv --allow-existing --python 3.10 "$RUNTIME_DIR/.venv"
"$UV_BIN" pip install \
    --python "$RUNTIME_DIR/.venv/bin/python" \
    --requirement "$RUNTIME_DIR/requirements.txt"

if ! command -v hf >/dev/null 2>&1; then
    echo "Hugging Face CLI is required. Install it and authenticate before setup." >&2
    exit 1
fi

hf auth whoami >/dev/null
hf download stabilityai/stable-audio-open-small --cache-dir "$MODEL_CACHE"
hf download t5-base --cache-dir "$MODEL_CACHE"

echo "Runtime installed at $RUNTIME_DIR/.venv"
echo "Model cached at $MODEL_CACHE"
echo "Run scripts/verify_model.sh to perform a real local generation."
