# Loop Generator

Loop Generator is an experimental, local-only macOS application for creating short instrumental samples with Stable Audio Open Small. Version 0.2.0 adds a separate C2PA-signed WAV export while preserving ordinary WAV export and the modular path toward future plugin shells.

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

## V1 release status

The current C2PA export is frozen as the V1 working reference: it signs a WAV with the official Conformance Test credential, validates as trusted when Test Mode is enabled, and detects a one-byte media change through the C2PA data hash. The official C2PA Asset Conformance 0.2 / Spec 2.4 rubric passed 28 of 31 checks; therefore this repository does **not** claim full Spec 2.4 conformance.

Three manifest-alignment items are intentionally deferred to V1.1: add `specVersion` to `claim_generator_info`, provide an explicit `allActionsIncluded` value, and attribute the inception action as the first item in `created_assertions`. These omissions do not invalidate the demonstrated test signature or hard binding, but they do prevent a conformance claim.

## Requirements

- Apple Silicon Mac
- macOS 14 or later
- Xcode command-line tools
- CMake is not required for the SwiftUI V0
- Authenticated Hugging Face CLI access to `stabilityai/stable-audio-open-small`
- Acceptance of the model's license terms by the person running setup
- Official C2PA Conformance Test signing bundle stored externally as `~/Downloads/test-signing-bundle.pem`

## Build and run

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

The SwiftUI shell depends on `LoopGeneratorCore`, not the other way around. Model execution, generation records, export, and provenance are expressed as independent protocols/services; a future iPlug2 VST3/AU shell can reuse or bridge these boundaries without moving ML code into the UI or plugin process.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for component boundaries and [docs/C2PA_V1_PROFILE.md](docs/C2PA_V1_PROFILE.md) for the exact manifest, trust, and validation profile.

## Current limitations

- Experimental test implementation for Apple Silicon macOS
- Python helper and model files are local development dependencies, not embedded in the `.app`
- C2PA uses a public test credential and Test Root, not production PKI
- C2PA Asset Conformance 0.2 / Spec 2.4 result is 28/31; three documented items are deferred to V1.1
- No TSA, Developer ID distribution signature, notarization, or full conformance claim
- No VST3, Audio Unit, or CLAP targets yet
- No project saving, generation-history UI, or audio editing

## Roadmap

- V0 — Working local AI audio standalone
- V1 — C2PA signed WAV export + validation
- V2 — Conformance preparation
- V3 — VST3/AU reference integration
- V4 — Extract reusable Audio C2PA Reference Kit

## Licensing

Application source code is licensed under MIT. Stable Audio Open Small and its runtime dependencies are separately licensed; review [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) before use or redistribution.
