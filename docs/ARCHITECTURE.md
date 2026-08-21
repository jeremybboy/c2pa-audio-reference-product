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
        |      +-- ExportService (ordinary and C2PA instances)
        |             |
        |             +-- AudioExportEncoding
        |             |
        |             +-- ProvenanceService
        |                    |
        |                    +-- NullProvenanceService
        |                    |
        |                    +-- C2PAProvenanceService
        |                           |
        |                           +-- SigningCredentialProvider
        |                           +-- C2PAManifestBuilder
        |                           +-- C2PAToolRunner
        |                           +-- C2PAValidationInspection
        |                           +-- C2PAEvidenceStore
        |
        +-- Waveform viewer
```

## Boundaries

- `LoopGeneratorCore` has no dependency on SwiftUI or the standalone window.
- `ModelAdapter` returns a normal audio asset and model version; it does not control playback or export.
- `StableAudioAdapter` is the only Swift component aware of the helper process.
- `GenerationRecord` is model-neutral and provenance-neutral.
- `ExportService` encodes the WAV first, then invokes the selected `ProvenanceService` with an `ExportContext`.
- Ordinary WAV export keeps `NullProvenanceService`; C2PA export is a separate user action backed by `C2PAProvenanceService`.
- Signing credentials are supplied through an external provider and are not resources owned by the application bundle.
- The in-memory audio playback implementation stays in the standalone target. A later iPlug2 shell can supply its own real-time-safe playback/DSP implementation while reusing the request, record, model, export, and provenance contracts.

## Runtime contract

The app starts `runtime/stable_audio/infer.py` with a final prompt, duration, seed, output WAV path, and metadata path. The helper writes 44.1 kHz stereo floating-point PCM for preview; `AVFoundationWAVEncoder` creates the user-facing 24-bit PCM WAV.

Normal application inference sets Hugging Face and Transformers to offline mode. Model installation and any downloads are confined to `scripts/setup_runtime.sh` and the explicit first verification run.
