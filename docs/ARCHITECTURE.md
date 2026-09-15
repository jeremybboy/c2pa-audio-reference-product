# Architecture

```text
Stable Audio helper process (offline during normal use)
        |
        +-- generated WAV + model metadata
        |
        +-----------------------------+
        |                             |
SwiftUI Application Shell      JUCE VST3 Effect Shell
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
                                      |
                                      +-- GenerationService (background thread)
                                      +-- GeneratedLoopStore (immutable snapshots)
                                      +-- AudioProcessor (real-time playback only)
                                      +-- Host position / tempo / time signature
                                      +-- APVTS parameters and state restore
                                      +-- External WAV file drag
```

## Boundaries

- `LoopGeneratorCore` has no dependency on SwiftUI or the standalone window.
- `ModelAdapter` returns a normal audio asset and model version; it does not control playback or export.
- `StableAudioAdapter` is the only Swift component aware of the helper process.
- `GenerationRecord` is model-neutral and provenance-neutral.
- `ExportService` encodes the WAV first, then invokes the selected `ProvenanceService` with an `ExportContext`.
- Ordinary WAV export keeps `NullProvenanceService`; C2PA export is a separate user action backed by `C2PAProvenanceService`.
- Signing credentials are supplied through an external provider and are not resources owned by the application bundle.
- The VST3 is an audio effect because the current reference sequencer loads VST3 effects but not instrument entries. Before a generated loop is loaded it preserves the input signal; after loading it emits the loop.
- `StableAudioGenerationService` launches inference on a background `std::thread`; `processBlock()` only reads an immutable audio snapshot and performs playback/resampling.
- Host-sync playback derives phase from PPQ, tempo, and time signature. The generated bar count is fixed, while playback stretches the audio to the current host bar length.
- The VST3 state stores parameters, prompt, instrument, seed, and the cached WAV path. Reload succeeds only while that external cached WAV still exists.
- External drag hands the generated WAV path to macOS through JUCE. File acceptance, copying, and placement are host responsibilities.
- The VST3 generation worker invokes the pinned external `c2patool` after inference, validates the test signature, claim signature, and WAV hard binding, and atomically replaces the unsigned cache file before exposing it. The external PEM remains outside the VST3; no signing or process launch occurs in `processBlock()`.

## Runtime contract

The app starts `runtime/stable_audio/infer.py` with a final prompt, duration, seed, output WAV path, and metadata path. The helper writes 44.1 kHz stereo floating-point PCM for preview; `AVFoundationWAVEncoder` creates the user-facing 24-bit PCM WAV.

Normal application and VST3 inference set Hugging Face and Transformers to offline mode. Model installation and any downloads are confined to `scripts/setup_runtime.sh` and the explicit first verification run.

The VST3 bundle contains the helper script but not Python, model weights, or signing credentials. `scripts/install_vst3.sh` links the ignored local model runtime into `~/Library/Application Support/LoopGenerator/runtime`; `scripts/setup_c2pa.sh` installs the public C2PA tooling and test trust files under `~/Library/Application Support/LoopGenerator/c2pa`; generated WAVs are written under `~/Library/Caches/LoopGenerator/generated`.
