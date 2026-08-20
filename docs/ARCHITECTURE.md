# Architecture

```text
SwiftUI Application Shell
        |
        +-- AppViewModel
        |      |
        |      +-- GenerationController
        |      |      |
        |      |      +-- ModelAdapter
        |      |             |
        |      |             +-- StableAudioAdapter
        |      |                    |
        |      |                    +-- local Python helper
        |      |
        |      +-- AudioPlaybackEngine
        |      |
        |      +-- ExportService
        |             |
        |             +-- AudioExportEncoding
        |             |
        |             +-- ProvenanceService
        |                    |
        |                    +-- NullProvenanceService (V0)
        |
        +-- Waveform viewer
```

## Boundaries

- `LoopGeneratorCore` has no dependency on SwiftUI or the standalone window.
- `ModelAdapter` returns a normal audio asset and model version; it does not control playback or export.
- `StableAudioAdapter` is the only Swift component aware of the helper process.
- `GenerationRecord` is model-neutral and provenance-neutral.
- `ExportService` encodes the WAV first, then invokes `ProvenanceService` with an `ExportContext`.
- `NullProvenanceService` is intentionally inert; the next implementation can build and sign C2PA assertions without restructuring generation, playback, or UI code.
- The in-memory audio playback implementation stays in the standalone target. A later iPlug2 shell can supply its own real-time-safe playback/DSP implementation while reusing the request, record, model, export, and provenance contracts.

## Runtime contract

The app starts `runtime/stable_audio/infer.py` with a final prompt, duration, seed, output WAV path, and metadata path. The helper writes 44.1 kHz stereo floating-point PCM for preview; `AVFoundationWAVEncoder` creates the user-facing 24-bit PCM WAV.

Normal application inference sets Hugging Face and Transformers to offline mode. Model installation and any downloads are confined to `scripts/setup_runtime.sh` and the explicit first verification run.
