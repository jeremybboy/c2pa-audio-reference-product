# Technical Handoff

Snapshot date: 2026-08-20

## Current state

Loop Generator 0.2.0 is a native SwiftUI macOS reference application with local Stable Audio Open Small generation, ordinary 24-bit WAV export, and a separate C2PA-signed WAV test export. V1 is implemented on `feature/v1-c2pa-export` from merged `main` commit `93be230`; use `git rev-parse HEAD` for the final feature commit.

The V1 working proof is complete:

```text
real local model output
-> 44.1 kHz stereo 24-bit PCM WAV
-> one embedded C2PA manifest
-> official Conformance Test signing credential
-> trusted validation against the Conformance Test Root
-> one-byte tamper
-> data-hash mismatch and Invalid state
```

This is test infrastructure, not production PKI and not a full conformance claim. The hosted C2PA Asset Conformance 0.2 / Spec 2.4 rubric passed 28 of 31 checks; the exact three failures are documented below and deferred to V1.1.

## Product capabilities

- Local Stable Audio Open Small inference for 4-, 8-, or 11-second instrumental loops.
- Synth, Bass, Drums, Piano, Guitar, Strings, and FX prompt conditioning.
- Deterministic or random seed selection.
- Waveform preview, playback, restart, loop, and volume controls.
- Ordinary 44.1 kHz stereo 24-bit PCM WAV export.
- Separate `Export C2PA WAV (Test)` UI action.
- JSON generation records and ignored C2PA evidence records.
- App version `0.2.0`, build `2`.

## Modular architecture

```text
SwiftUI/AppViewModel
    |-- GenerationController
    |     `-- ModelAdapter
    |           `-- StableAudioAdapter -> local Python runtime
    |-- AudioPlaybackEngine
    `-- ExportService
          |-- AudioExportEncoding -> AVFoundationWAVEncoder
          `-- ProvenanceService
                |-- NullProvenanceService
                `-- C2PAProvenanceService
                      |-- SigningCredentialProvider
                      |-- C2PAManifestBuilder
                      |-- C2PAToolRunner
                      |-- C2PAValidationInspection
                      `-- C2PAEvidenceStore
```

`LoopGeneratorCore` has no SwiftUI dependency. The model creates an ordinary audio asset; provenance is applied only after export encoding. This keeps model execution, UI, playback, export, signing, validation, and future plugin shells separable.

## C2PA implementation

The frozen manifest profile is documented in `docs/C2PA_V1_PROFILE.md`. The core policy is:

- One active embedded manifest.
- One `c2pa.actions.v2` assertion.
- One `c2pa.created` action.
- Exact trained-algorithmic-media digital source type URI.
- Stable Audio Open Small and the exact model revision as action software agent.
- Loop Generator and actual app version as claim generator.
- No ingredients, prompt, seed, `allActionsIncluded`, or TSA.

`C2PAProvenanceService` writes a temporary manifest definition, invokes c2patool with explicit create intent, independently validates trust and the frozen profile, atomically replaces the unsigned destination with the signed WAV, and records evidence. If signing or validation fails, `ExportService` removes the partial output and propagates the specific provenance error.

## Credential and trust boundary

The official C2PA Conformance Test signing credential remains external at `~/Downloads/test-signing-bundle.pem` by default. `LOOP_GENERATOR_C2PA_SIGNING_BUNDLE` can override that path. The combined PEM is passed as both c2patool certificate and private-key input; it is not split, copied, packaged, or committed.

The app bundle contains only:

- Pinned c2patool `0.27.15`.
- Public C2PA Conformance Test Root.
- Public C2PA trust-purpose configuration.

The setup script verifies the external certificate fingerprint, cert/key match, EKU-compatible chain, pinned public root, and pinned tool checksums. Test-mode trust proves the signer chains to the Test Root; it deliberately does not imply production trust.

## Runtime pins

```text
macOS validation host:      26.6.2 / Apple Silicon
declared minimum macOS:     14.0
Swift compiler:             6.3, Swift language mode 5
Python:                     3.10.21
Stable Audio Tools:         0.0.20
Stable Audio model commit:  dc620d91535857b72ebb59b4ca45978db6d417f5
c2patool:                   0.27.15
c2pa-rs reported by tool:   0.90.15
Conformance Tool commit:    44c81e07fc92b39a525412f4e7a1c2cda0757beb
```

Model weights, Python environments, generated audio, C2PA evidence, c2patool, trust-test files, and signing credentials are ignored local dependencies.

## Reproduce

From the repository root:

```bash
cd "/Users/uzanj/Documents/Codex/2026-08-20/files-mentioned-by-the-user-chatgpt/loop-generator"
```

Set up and verify the model:

```bash
./scripts/setup_runtime.sh
./scripts/verify_model.sh
```

Set up and verify C2PA with the external credential:

```bash
./scripts/setup_c2pa.sh "$HOME/Downloads/test-signing-bundle.pem"
./scripts/verify_c2pa.sh
```

Run the normal suite:

```bash
CLANG_MODULE_CACHE_PATH="$PWD/.cache/clang" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.cache/clang" \
swift test --disable-sandbox \
  --cache-path "$PWD/.cache/swiftpm" \
  --config-path "$PWD/.cache/swiftpm/configuration" \
  --security-path "$PWD/.cache/swiftpm/security" \
  --scratch-path "$PWD/.build"
```

Run the real C2PA integration test directly:

```bash
LOOP_GENERATOR_C2PA_LIVE_TEST=1 \
CLANG_MODULE_CACHE_PATH="$PWD/.cache/clang" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.cache/clang" \
swift test --disable-sandbox \
  --filter C2PAExportTests.testLiveC2PASigningTrustAndTamperDetectionWhenEnabled \
  --cache-path "$PWD/.cache/swiftpm" \
  --config-path "$PWD/.cache/swiftpm/configuration" \
  --security-path "$PWD/.cache/swiftpm/security" \
  --scratch-path "$PWD/.build"
```

Build and launch:

```bash
./scripts/build_app.sh
open "build/Loop Generator.app"
```

## Validation evidence

`build/c2pa-evidence/v1/` is generated and ignored. The verified run contains the unsigned source, signed WAV, tampered WAV, embedded-manifest JSON, trusted validation JSON, negative validation JSON, service evidence, checksums, and a browser observation record.

The positive validator report contains:

- `validation_state: Trusted`
- `signingCredential.trusted`
- `claimSignature.validated`
- `assertion.dataHash.match`
- zero failures

The negative validator report contains:

- `validation_state: Invalid`
- `assertion.dataHash.mismatch`

The official hosted C2PA Conformance Tool was also run with one Test Mode certificate loaded. It reported `Signature Trusted via Test Certificate`, issuer `C2PA Conformance Test Root`, claim generator `Loop Generator v0.2.0`, and one `c2pa.actions.v2` assertion.

The hosted C2PA Asset Conformance 0.2 / Spec 2.4 rubric result was 28/31, overall Fail. The missing items are `specVersion` in `claim_generator_info`, an explicit `allActionsIncluded` field, and attribution of the inception action as the first actions assertion in `created_assertions`; the current tool output places it in `gathered_assertions`.

## Known limitations and next work

- The signing credential and Test Root are strictly test-only.
- No TSA, production certificate lifecycle, hardware-backed key, Developer ID signature, notarization, or public distribution workflow exists.
- Formal Spec 2.4 conformance is not claimed: the hosted rubric passed 28/31 and the three failed checks are frozen for V1.1.
- Omitting `allActionsIncluded` produces an informational `Contains ambiguous actions` signal in the Conformance Tool; the omission is required by the frozen V1 policy unless completeness can be substantiated.
- The `.app` depends on the external Python environment/model cache and external signing PEM.
- The model helper reloads the model per request; there is no persistent inference service, cancellation, or queue.
- No VST3, Audio Unit, or CLAP target exists.
- C2PA trust proves signature and byte integrity under the configured trust root; it does not prove descriptive truth.

## Guardrails

- Never commit or package the signing bundle or any private key.
- Never replace test trust with production trust language.
- Never add prompt or seed to the V1 manifest without a profile decision.
- Never introduce ingredients or `allActionsIncluded` through c2patool defaults.
- Keep signing and model inference outside real-time audio threads.
- Preserve ordinary WAV export and the protocol boundaries required by future plugin shells.
