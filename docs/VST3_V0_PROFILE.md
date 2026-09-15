# VST3 Prototype Profile

## Scope

`Loop Generator.vst3` is an Apple-Silicon macOS audio effect built with JUCE 8.0.12. It generates Stable Audio Open Small WAV assets in a child process, plays the selected asset in sync with a host, saves enough state to reopen an existing cached asset, and exposes that WAV through an external file drag.

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
- Generated assets: `~/Library/Caches/LoopGenerator/generated`
- Generated assets are 44.1 kHz stereo Float32 WAV files and are not automatically pruned in this prototype.
- The VST3 contains `infer.py`, but no Python environment, model weights, C2PA credential, or private key.
- Normal inference is offline; only explicit runtime setup may download dependencies and model weights.

## Validation boundary

Automated tests cover request duration, argument isolation, WAV decoding, preview output, host-synchronized output, state restoration, bundle scanning, effect classification, editor creation, and pass-through before generation. A real local model generation verifies the shipped helper and external runtime separately.

Manual DAW acceptance remains required for discovery after installation, editor interaction, audible host-synchronized playback, external drag placement, project save/reopen, and behavior across tempo changes. Automated host tests do not prove those perceptual and interactive results.

## Deferred

- C2PA signing/export and its external test credential
- A DAW-to-final-export provenance association model
- AU/CLAP formats
- Universal binary, Developer ID signing, notarization, installer packaging
- Distribution licensing decision for JUCE and Stable Audio
