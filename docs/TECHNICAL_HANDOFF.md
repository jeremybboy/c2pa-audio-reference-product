# Technical Handoff

Snapshot date: 2026-08-20

## Project purpose

This repository is a reference product for studying the practical implementation path from an ordinary audio product to reusable C2PA infrastructure:

```text
ordinary audio product
→ local AI generation
→ C2PA export
→ validation
→ conformance candidate
→ reusable Audio C2PA Reference Kit
```

The current application makes that work concrete without coupling provenance to a specific model or UI. Stable Audio Open Small is the present interchangeable model dependency; it is not part of the C2PA architecture and its weights are not licensed under this repository's MIT source-code license.

## Current repository state

```text
Repository:  c2pa-audio-reference-product
Visibility:  private
Branch:      feature/v0-swiftui
Code HEAD:   b3304a0763a10b61f44f223a6f5e598fb3275aae
Remote:      https://github.com/jeremybboy/c2pa-audio-reference-product.git
GitHub:      https://github.com/jeremybboy/c2pa-audio-reference-product
Worktree:    clean after the documentation commit
```

`Code HEAD` is the exact application commit inspected while this report was written. The documentation commit cannot embed its own Git object ID because changing that value would change the ID; use `git rev-parse HEAD` for the containing documentation commit.

Relevant history before this documentation commit:

```text
b3304a0 fix: complete offline Stable Audio runtime
017b807 feat: build Loop Generator V0
b20e82c chore: initialize loop-generator repository
```

The original Git history is preserved. `main` remains at `b20e82c`; the working implementation and this handoff are on `feature/v0-swiftui`. This task does not merge the feature branch into `main`.

## Current V0

The demonstrated V0 is a native SwiftUI macOS standalone with:

- Local Stable Audio Open Small inference for instrumental generation.
- Synth, Bass, Drums, Piano, Guitar, Strings, and FX categories.
- 4-, 8-, and 11-second generation.
- Random or user-specified deterministic seeds.
- Waveform preview.
- Play/pause and restart controls.
- Loop playback and volume control.
- 44.1 kHz stereo 24-bit PCM WAV export.
- JSON generation metadata records.
- A model-neutral `ModelAdapter` abstraction.
- An export-time `ProvenanceService` boundary.

V0 does not generate C2PA manifests and has no VST3 or Audio Unit target.

## Architecture

Generation path:

```text
SwiftUI App
    ↓
AppViewModel
    ↓
GenerationController
    ↓
ModelAdapter
    ↓
StableAudioAdapter
    ↓
Local Python Stable Audio runtime
```

Export path:

```text
ExportService
    ├── AudioExportEncoding
    │       └── AVFoundationWAVEncoder
    └── ProvenanceService
            └── NullProvenanceService (V0)
```

`LoopGeneratorCore` is independent of SwiftUI. `StableAudioAdapter` is the only Swift component that knows about the Python inference subprocess. `GenerationRecord` is model-neutral and provenance-neutral. `ExportService` writes the WAV and then invokes `ProvenanceService` with both the generation record and exported asset.

That export boundary is the key V1 seam: `NullProvenanceService` can be replaced by `C2PAProvenanceService` without moving C2PA logic into the UI, model adapter, playback engine, or real-time audio code. It also keeps future VST3/AU shells from owning provenance policy.

## Runtime state

Verified on the current machine:

```text
Architecture:              arm64 / Apple Silicon
macOS:                     26.6.2 (build 25G83)
Declared minimum macOS:    14.0
Swift compiler:            Apple Swift 6.3
Swift language mode:       5
Python:                    3.10.21
PyTorch:                   2.7.1
NumPy:                     1.26.4
SoundFile:                 0.13.1
PyTorch Lightning:         2.5.5
Stable Audio Tools:        pinned to 0.0.20
Acceleration:              MPS verified available and used
Stable Audio model commit: dc620d91535857b72ebb59b4ca45978db6d417f5
```

The live inference log states:

```text
Loading stabilityai/stable-audio-open-small on mps
```

The Python environment and Hugging Face caches are repository-local ignored data:

```text
runtime/stable_audio/.venv/        approximately 692 MB
runtime/stable_audio/.model-cache/ approximately 8.8 GB
```

The model cache contains Stable Audio Open Small plus its separate `t5-base` text encoder. Model setup is an explicit authenticated workflow; normal inference sets Hugging Face and Transformers to offline mode.

## Validation state

The current application code at `b3304a0` was validated before this documentation-only commit:

- Normal Swift suite: 9 tests executed, 1 opt-in live test skipped, 0 failures.
- Opt-in live adapter test: 1 test executed, 0 failures, 8.159 seconds.
- Direct model verification produced an exactly four-second, 44.1 kHz, stereo Float32 preview WAV with seed `424242`.
- The packaged app produced valid eight-second audio and JSON generation records through the UI.
- The local app bundle passed strict `codesign --verify` with an ad-hoc signature.
- App and source archives passed ZIP integrity checks.

This documentation task does not rebuild or change the application architecture.

## Build, test, and launch

From the repository root:

```bash
cd "/Users/uzanj/Documents/Codex/2026-08-20/files-mentioned-by-the-user-chatgpt/loop-generator"
```

Install or refresh the repository-local runtime and download the gated model after the user has completed the required upstream access steps:

```bash
./scripts/setup_runtime.sh
```

Perform real model verification:

```bash
./scripts/verify_model.sh
```

Run the normal tests:

```bash
CLANG_MODULE_CACHE_PATH="$PWD/.cache/clang" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.cache/clang" \
swift test --disable-sandbox \
  --cache-path .cache/swiftpm \
  --config-path .cache/swiftpm/configuration \
  --security-path .cache/swiftpm/security \
  --scratch-path .build
```

Run the real-model integration test:

```bash
LOOP_GENERATOR_LIVE_TEST=1 \
CLANG_MODULE_CACHE_PATH="$PWD/.cache/clang" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.cache/clang" \
swift test --disable-sandbox \
  --filter LoopGeneratorCoreTests.testLiveStableAudioAdapterWhenEnabled \
  --cache-path .cache/swiftpm \
  --config-path .cache/swiftpm/configuration \
  --security-path .cache/swiftpm/security \
  --scratch-path .build
```

Build and launch:

```bash
./scripts/build_app.sh
open "build/Loop Generator.app"
```

## Known limitations

- The app is not self-contained for distribution.
- The Python environment and model cache are external to the `.app`.
- The bundle has no Developer ID signature or notarization.
- No C2PA manifest is generated or embedded.
- No production C2PA signing credential exists.
- No trusted timestamp authority is integrated.
- No independent C2PA validation flow exists.
- No VST3 or Audio Unit target exists.
- The Python/model subprocess architecture is prototype-grade: each request starts a process and reloads the model.
- There is no persistent inference service, cancellation, request queue, or granular progress reporting.
- Generated caches and records have no retention or cleanup policy.
- macOS 14 is declared as the minimum but has not been independently validated; current validation was on macOS 26.6.2.

## V1 — C2PA Export

The next milestone is deliberately narrow:

```text
GenerationRecord
    ↓
Generated audio
    ↓
WAV export
    ↓
C2PAProvenanceService
    ↓
C2PA manifest
    ↓
development signing credential
    ↓
embedded C2PA WAV
    ↓
independent validation
```

The first C2PA milestone does not require:

- Production signing credentials.
- A trusted timestamp authority.
- Conformance submission.
- VST3 or Audio Unit targets.
- Notarized public distribution.

The proof target is:

```text
generate → export → sign → embed → validate
```

with development credentials. Every implementation obstacle must be captured in `docs/FRICTION_LOG.md` so the evidence can later inform the reusable Audio C2PA Reference Kit.

## Guardrails

- Do not commit model weights, Hugging Face caches, Python environments, generated audio, logs, build products, credentials, tokens, private keys, or private signing material.
- Do not imply that Stable Audio weights use this repository's MIT license.
- Do not claim C2PA functionality until an exported WAV contains a signed manifest and passes an independent validation flow.
- Keep model inference and future plugin work outside real-time audio threads.
- Preserve the `ModelAdapter`, `ExportService`, and `ProvenanceService` boundaries.
- Use normal feature-branch commits and non-force pushes; do not rewrite the existing history.
