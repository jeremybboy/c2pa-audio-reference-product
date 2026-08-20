# Roadmap

## V0 — Local standalone

SwiftUI application, local Stable Audio Open Small generation, preview playback, looping, volume, WAV export, generation records, and a no-op provenance boundary.

## V1 — C2PA export

Replace `NullProvenanceService` with a C2PA implementation that consumes `GenerationRecord`, builds assertions, signs a manifest, embeds it in the exported WAV, and returns independently verifiable output.

## V2 — Conformance preparation

Add validation, negative tests, trust-chain configuration, and documented evidence boundaries for supported WAV/C2PA workflows.

## V3 — Plugin shells

Add iPlug2 VST3 and Audio Unit targets around the reusable core. Keep model inference out of the real-time audio thread and define host-safe asset transfer.

## V4 — Reference kit

Extract reusable generation-record and audio-provenance components into an Audio C2PA Reference Kit.
