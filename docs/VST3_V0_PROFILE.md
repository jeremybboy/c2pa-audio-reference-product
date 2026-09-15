# VST3 Prototype Profile

## Scope

`Loop Generator.vst3` is an Apple-Silicon macOS audio effect built with JUCE 8.0.12. It generates Stable Audio Open Small WAV assets in a child process, applies the existing test-only C2PA manifest, validates the result, plays the selected asset in sync with a host, saves enough state to reopen an existing cached asset, and exposes that WAV through an external file drag.

The target is deliberately an effect, not an instrument: the current C2PA Audio Sequencer VST3 host accepts effect entries and rejects instrument entries. The processor passes input through until a generated asset is loaded, then emits the generated loop while the host runs or while plug-in Preview is enabled.

## Host timing

- Length choices: 1, 2, or 4 bars.
- Generation duration: bars x time-signature quarter notes x 60 / host BPM.
- Stable Audio boundary: 1.0 through 11.0 seconds; requests outside it are rejected before inference.
- Playback sync: host PPQ, BPM, and time signature determine loop phase and time-fit.
- If host timing is absent, the last known/default 120 BPM and 4/4 values are shown and preview remains available.

## Runtime and files

- Installed plug-in: `~/Library/Audio/Plug-Ins/VST3/Loop Generator.vst3`
- External ignored runtime: `~/Library/Application Support/LoopGenerator/runtime`
- External public C2PA runtime: `~/Library/Application Support/LoopGenerator/c2pa`
- External test signing credential: `~/Downloads/test-signing-bundle.pem`
- Generated assets: `~/Library/Caches/LoopGenerator/generated`
- Newly generated assets are 44.1 kHz stereo Float32 WAV files with a validated test C2PA manifest and are not automatically pruned in this prototype.
- The VST3 contains `infer.py`, but no Python environment, model weights, C2PA credential, or private key.
- Normal inference is offline; only explicit runtime setup may download dependencies and model weights.

`scripts/setup_c2pa.sh` verifies the external Conformance Test credential and installs only `c2patool`, the public Test Root, and trust configuration under Application Support. Generation is rejected before model inference when that external signing configuration is unavailable. After inference, signing and validation run on the generation worker; the WAV does not become previewable or draggable unless the signature, claim signature, and asset data hash validate as trusted in Test Mode.

## Validation boundary

Automated tests cover request duration, argument isolation, C2PA manifest construction, the sign/validate/atomic-commit sequence, WAV decoding, preview output, host-synchronized output, state restoration, bundle scanning, effect classification, editor creation, and pass-through before generation. A real local model generation plus independent `c2patool` inspection verifies the external model and C2PA runtimes.

Manual DAW acceptance remains required for discovery after installation, editor interaction, audible host-synchronized playback, external drag placement, project save/reopen, and behavior across tempo changes. Automated host tests do not prove those perceptual and interactive results.

## Deferred

- A DAW-to-final-export provenance association model
- AU/CLAP formats
- Universal binary, Developer ID signing, notarization, installer packaging
- Distribution licensing decision for JUCE and Stable Audio
