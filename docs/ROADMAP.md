# Roadmap

## V0 — Local standalone

SwiftUI application, local Stable Audio Open Small generation, preview playback, looping, volume, WAV export, generation records, and a no-op provenance boundary.

## V1 — C2PA export (implemented)

Keep ordinary `NullProvenanceService` export and add an explicit C2PA path that consumes `GenerationRecord`, builds the frozen V1 assertion, signs with the external Conformance Test credential, embeds one manifest, validates against the Test Root, and preserves positive and tamper-negative evidence.

## V1.1 — Spec 2.4 alignment

Resolve the three frozen C2PA Asset Conformance 0.2 / Spec 2.4 failures: add `specVersion`, choose and document an explicit truthful `allActionsIncluded` value, and place the inception action first in signer-created assertions. Rebuild, rerun automated positive/tamper-negative validation, and require 31/31 on the hosted rubric before making a Spec 2.4 conformance claim.

## V2 — Production provenance preparation

Add production credential-provider options and define TSA, certificate lifecycle, secure-key, distribution-signing, and notarization requirements without weakening the V1 evidence boundary.

## V3 — Plugin shells

Add iPlug2 VST3 and Audio Unit targets around the reusable core. Keep model inference out of the real-time audio thread and define host-safe asset transfer.

## V4 — Reference kit

Extract reusable generation-record and audio-provenance components into an Audio C2PA Reference Kit.
