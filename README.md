<img width="1267" height="756" alt="Screenshot 2026-09-14 at 8 21 38 AM" src="https://github.com/user-attachments/assets/6985163b-0d29-41fd-93f7-8ef640ef1499" />


# Loop Generator

Loop Generator is an experimental, local-only macOS tool for creating short instrumental samples with Stable Audio Open Small. The repository now contains the original SwiftUI standalone and an Apple-Silicon VST3 audio-effect prototype; C2PA export remains in the standalone and is deliberately deferred from the plug-in.

## Reference product

This repository is a reference audio product used to study the end-to-end implementation path from an existing AI audio application to C2PA-enabled export and ultimately C2PA conformance. Stable Audio Open Small is the current interchangeable `ModelAdapter` implementation; it is a separately licensed model dependency, not part of the C2PA architecture.

## Current capabilities

- Instrument-conditioned text-to-audio
- Stable Audio Open Small through an isolated local helper process
- 4, 8, or 11-second generation with random or fixed seeds
- Waveform preview, play/pause, restart, looping, and volume
- Native 44.1 kHz, 24-bit stereo WAV export
- Separate C2PA-signed WAV test export with one embedded manifest
- Trusted validation against the C2PA Conformance Test Root
- Positive and tamper-negative evidence generation
- Internal generation records and modular provenance services
- JUCE 8.0.12 VST3 audio effect with generation outside the real-time callback
- 1, 2, or 4-bar generation based on host tempo and time signature
- Host-synchronized loop playback, preview playback, gain, and saved plug-in state
- External WAV drag-out for hosts that accept operating-system file drops

## V1 release status

The current C2PA export is frozen as the V1 working reference: it signs a WAV with the official Conformance Test credential, validates as trusted when Test Mode is enabled, and detects a one-byte media change through the C2PA data hash. The official C2PA Asset Conformance 0.2 / Spec 2.4 rubric passed 28 of 31 checks; therefore this repository does **not** claim full Spec 2.4 conformance.

Three manifest-alignment items are intentionally deferred to V1.1: add `specVersion` to `claim_generator_info`, provide an explicit `allActionsIncluded` value, and attribute the inception action as the first item in `created_assertions`. These omissions do not invalidate the demonstrated test signature or hard binding, but they do prevent a conformance claim.

## Requirements

- Apple Silicon Mac
- macOS 14 or later
- Xcode command-line tools
- CMake 3.25 or later for the VST3 (not required for the SwiftUI standalone)
- Authenticated Hugging Face CLI access to `stabilityai/stable-audio-open-small`
- Acceptance of the model's license terms by the person running setup
- Official C2PA Conformance Test signing bundle stored externally as `~/Downloads/test-signing-bundle.pem` only for the standalone C2PA test path

## Build and run

### VST3

From the repository root:

```bash
./scripts/setup_runtime.sh
JUCE_DIR="$(./scripts/setup_vst3.sh)"
./scripts/build_vst3.sh "$JUCE_DIR"
ctest --test-dir build-vst3 --output-on-failure
./scripts/install_vst3.sh
```

The installed bundle is `~/Library/Audio/Plug-Ins/VST3/Loop Generator.vst3`. Add it as an **audio effect** in the host, open its editor, choose a 1/2/4-bar length, generate, and press host Play; generation is a background helper process and never runs on the audio callback. `Drag WAV to DAW` exposes the cached generated file at `~/Library/Caches/LoopGenerator/generated`, but acceptance and placement of an external file drop depend on the host and require a manual DAW check.

The plug-in runtime stays external at `~/Library/Application Support/LoopGenerator/runtime`, linked by the installer to the ignored repository runtime. The model weights, Python environment, generated WAVs, and signing credentials are not packaged in the VST3 or tracked by Git.

### SwiftUI standalone

From the repository root:

```bash
./scripts/setup_runtime.sh
./scripts/verify_model.sh
./scripts/setup_c2pa.sh "$HOME/Downloads/test-signing-bundle.pem"
./scripts/verify_c2pa.sh
./scripts/build_app.sh
open "build/Loop Generator.app"
```

`setup_runtime.sh` installs Python 3.10, the official Stable Audio tooling, Stable Audio Open Small, and its `t5-base` text encoder into repository-local ignored directories. `setup_c2pa.sh` installs a pinned official c2patool binary and the public Conformance Test Root while verifying the external credential in place; it never copies the private key into the repository or app bundle.

## Architecture

The SwiftUI shell depends on `LoopGeneratorCore`, not the other way around. The VST3 is a separate JUCE shell with an immutable in-memory audio store, a background Stable Audio service, and host-facing playback/state code; both shells preserve a file/process boundary around inference, and neither runs model inference on a real-time audio thread.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for component boundaries, [docs/VST3_V0_PROFILE.md](docs/VST3_V0_PROFILE.md) for the exact plug-in scope, and [docs/C2PA_V1_PROFILE.md](docs/C2PA_V1_PROFILE.md) for the standalone manifest, trust, and validation profile.

## Current limitations

- Experimental test implementation for Apple Silicon macOS
- Python helper and model files are local development dependencies, not embedded in the `.app`
- VST3 is arm64-only, ad-hoc signed, and not notarized or packaged for distribution
- The current C2PA sequencer hosts audio effects, so the VST3 declares itself as an effect rather than an instrument
- Drag-out is implemented, but successful timeline placement remains host-specific manual acceptance
- Generated cache files are not automatically pruned in this prototype
- No C2PA signing or export occurs inside the VST3
- C2PA uses a public test credential and Test Root, not production PKI
- C2PA Asset Conformance 0.2 / Spec 2.4 result is 28/31; three documented items are deferred to V1.1
- No TSA, Developer ID distribution signature, notarization, or full conformance claim
- No Audio Unit or CLAP target yet
- No project saving, generation-history UI, or audio editing

## Roadmap

- V0 — Working local AI audio standalone
- V1 — C2PA signed WAV export + validation
- V2 — Conformance preparation
- V3 — VST3 reference prototype implemented; AU and provenance integration remain
- V4 — Extract reusable Audio C2PA Reference Kit

## Licensing

Application source code is licensed under MIT. Stable Audio Open Small and its runtime dependencies are separately licensed; review [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) before use or redistribution.
