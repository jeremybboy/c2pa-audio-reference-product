# Loop Generator

Loop Generator is an experimental, local-only macOS application for creating short instrumental samples with Stable Audio Open Small. V0 is a SwiftUI standalone so the working product can be validated before plugin shells are added.

## Reference product

This repository is a reference audio product used to study the end-to-end implementation path from an existing AI audio application to C2PA-enabled export and ultimately C2PA conformance. Stable Audio Open Small is the current interchangeable `ModelAdapter` implementation; it is a separately licensed model dependency, not part of the C2PA architecture.

## Current capabilities

- Instrument-conditioned text-to-audio
- Stable Audio Open Small through an isolated local helper process
- 4, 8, or 11-second generation with random or fixed seeds
- Waveform preview, play/pause, restart, looping, and volume
- Native 44.1 kHz, 24-bit stereo WAV export
- Internal generation records and a no-op provenance insertion point

## Requirements

- Apple Silicon Mac
- macOS 14 or later
- Xcode command-line tools
- CMake is not required for the SwiftUI V0
- Authenticated Hugging Face CLI access to `stabilityai/stable-audio-open-small`
- Acceptance of the model's license terms by the person running setup

## Build and run

From the repository root:

```bash
./scripts/setup_runtime.sh
./scripts/verify_model.sh
./scripts/build_app.sh
open "build/Loop Generator.app"
```

`setup_runtime.sh` installs Python 3.10, the official Stable Audio tooling, Stable Audio Open Small, and its `t5-base` text encoder into repository-local ignored directories. The application launches inference with offline mode enabled and selects Apple Metal (MPS) when available, with CPU fallback; network access is only permitted by the explicit setup workflow.

## Architecture

The SwiftUI shell depends on `LoopGeneratorCore`, not the other way around. Model execution, generation records, export, and provenance are expressed as independent protocols/services; a future iPlug2 VST3/AU shell can reuse or bridge these boundaries without moving ML code into the UI or plugin process.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for component boundaries.

## Current limitations

- Experimental V0 for Apple Silicon macOS
- Python helper and model files are local development dependencies, not embedded in the `.app`
- No C2PA manifest generation or signing yet
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
