# Roadmap

## V0 — Local standalone

SwiftUI application, local Stable Audio Open Small generation, preview playback, looping, volume, WAV export, generation records, and a no-op provenance boundary.

## V1 — C2PA export (implemented)

Keep ordinary `NullProvenanceService` export and add an explicit C2PA path that consumes `GenerationRecord`, builds the frozen V1 assertion, signs with the external Conformance Test credential, embeds one manifest, validates against the Test Root, and preserves positive and tamper-negative evidence.

## V1.1 — Spec 2.4 alignment

Resolve the three frozen C2PA Asset Conformance 0.2 / Spec 2.4 failures: add `specVersion`, choose and document an explicit truthful `allActionsIncluded` value, and place the inception action first in signer-created assertions. Rebuild, rerun automated positive/tamper-negative validation, and require 31/31 on the hosted rubric before making a Spec 2.4 conformance claim.

## V2 — Production provenance preparation

Add production credential-provider options and define TSA, certificate lifecycle, secure-key, distribution-signing, and notarization requirements without weakening the V1 evidence boundary.

## V3 — Plugin shells (VST3 prototype implemented)

The JUCE 8.0.12 Apple-Silicon VST3 prototype is implemented as an audio effect with background Stable Audio generation, host-synchronized playback, saved state, and external WAV drag-out. Manual acceptance in the target DAW, signed/notarized distribution, AU support, and a production licensing decision remain open.

## V3.1 — Plug-in provenance

Define how a DAW session associates a generated asset with a later signed export before adding C2PA code to the plug-in. Keep cached generation metadata, DAW project state, routed audio, and final-file signing as separate evidence boundaries.

## V4 — Reference kit

Extract reusable generation-record and audio-provenance components into an Audio C2PA Reference Kit.
