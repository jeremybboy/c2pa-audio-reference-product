# C2PA V1 WAV Profile

Status: frozen working V1, validated for test use on 2026-08-20; not fully Spec 2.4 conformant.

This profile defines the deliberately narrow first C2PA export produced by Loop Generator 0.2.0. It is a working reference implementation, not a production credentialing system and not a claim of full C2PA product conformance.

## Frozen manifest profile

| Field | V1 value |
| --- | --- |
| Container | WAV with one embedded active manifest |
| Audio | 44.1 kHz, stereo, 24-bit PCM |
| Assertion | `c2pa.actions.v2` |
| Action | `c2pa.created` |
| Digital source type | `http://cv.iptc.org/newscodes/digitalsourcetype/trainedAlgorithmicMedia` |
| Action software agent | `Stable Audio Open Small` |
| Software-agent version | Exact model revision from `GenerationRecord` |
| Description | `AI-generated audio created by Loop Generator using Stable Audio Open Small.` |
| Claim generator | `Loop Generator` and the bundle's actual application version |
| Ingredients | None |
| Prompt disclosure | None |
| Seed disclosure | None |
| `allActionsIncluded` | Omitted because V1 does not substantiate completeness |
| TSA | None |

The signer passes `--create trainedAlgorithmicMedia` to c2patool. This is essential: c2patool's default edit intent creates a parent ingredient and a `c2pa.opened` action, which violates this profile.

## Signing boundary

V1 uses the official C2PA Conformance Test signing credential only:

- Certificate common name: `C2PA Conformance Test Signing`
- Issuer: `C2PA Conformance Test Root`
- Algorithm: ES256 / P-256
- Extended key usage: `1.3.6.1.5.5.7.3.36`
- Signing-certificate SHA-256 fingerprint: `B2:7C:27:D4:50:19:DC:80:D4:75:5A:26:20:7B:9E:02:E2:36:E5:4D:70:92:85:73:D6:8E:4E:CE:18:06:87:55`

`SigningCredentialProvider` resolves the combined certificate/private-key PEM from an external file. The default development location is `~/Downloads/test-signing-bundle.pem`; `LOOP_GENERATOR_C2PA_SIGNING_BUNDLE` can point to another external location. The file is never copied into source control or the application bundle.

The `.app` contains only c2patool, the public C2PA Conformance Test Root, and its public trust configuration. This credential is explicitly unsuitable for production identity or public distribution.

## Tool and trust pins

- c2patool: `0.27.15`
- c2pa-rs reported by c2patool: `0.90.15`
- C2PA Conformance Tool source commit: `44c81e07fc92b39a525412f4e7a1c2cda0757beb`
- Test Root PEM SHA-256: `ad66f955c63d7fc28771a40b730b3d594643dd2ff3a764858d97615245bb9216`
- Test Root certificate SHA-256 fingerprint: `41:BD:E3:25:75:33:13:FC:3D:C6:32:F1:8C:2B:7F:AD:E7:29:B9:4A:64:29:FE:E5:24:E3:47:11:0C:34:6D:BA`

`scripts/setup_c2pa.sh` verifies the c2patool archive and binary checksums, extracts the public Test Root from the pinned Conformance Tool source, verifies the external signing-certificate fingerprint, verifies that its private key matches, and verifies the certificate chain. It does not download or copy a private credential.

CLI validation supplies the Test Root and trust configuration directly to c2patool. This is the command-line equivalent of enabling Test Mode. The same signed WAV was also checked in the official hosted C2PA Conformance Tool with `Test Mode (1)` active; the UI reported `Signature Trusted via Test Certificate` and identified the issuer as `C2PA Conformance Test Root`.

## Runtime flow

```text
ordinary Export WAV
    -> AVFoundationWAVEncoder
    -> NullProvenanceService

Export C2PA WAV (Test)
    -> AVFoundationWAVEncoder
    -> C2PAProvenanceService
       -> SigningCredentialProvider
       -> C2PAManifestBuilder
       -> C2PAToolRunner sign
       -> C2PAToolRunner trust validation
       -> C2PAValidationInspection
       -> JSONC2PAEvidenceStore
```

Signing occurs after WAV encoding, outside the model and playback layers. The output is not handed to the caller unless trusted validation and profile inspection both succeed; a failure removes the partial destination.

## Reproduce validation

From the repository root:

```bash
./scripts/setup_c2pa.sh "$HOME/Downloads/test-signing-bundle.pem"
./scripts/verify_model.sh
./scripts/verify_c2pa.sh
```

The generated, ignored evidence directory is `build/c2pa-evidence/v1/`:

- `unsigned-source.wav`
- `signed-c2pa.wav`
- `tampered-c2pa.wav`
- `manifest.json`
- `validation-report.json`
- `negative-validation-report.json`
- `evidence-summary.json`
- `conformance-tool-browser-observation.json`
- `service-evidence/<generation-id>/manifest.json`
- `service-evidence/<generation-id>/validation.json`

## Verified definition of done

The real Stable Audio output generated with model revision `dc620d91535857b72ebb59b4ca45978db6d417f5` produced these results:

- Exactly one embedded active manifest was discovered.
- `signingCredential.trusted`, `claimSignature.validated`, and `assertion.dataHash.match` succeeded.
- Validation state was `Trusted` against the C2PA Conformance Test Root.
- The frozen action, source type, app version, model name, model revision, and description were present.
- Ingredients, prompt, seed, and `allActionsIncluded` were absent.
- A one-byte audio-payload modification changed validation state to `Invalid` with `assertion.dataHash.mismatch`.
- The signed file remained a four-second, 44.1 kHz, stereo, 24-bit PCM WAV.
- The official hosted Conformance Tool independently reported trust through the Test Certificate while Test Mode was active.

## Frozen V1 conformance result

The official hosted **C2PA Asset Conformance 0.2 / Spec 2.4** rubric evaluated the same export and passed 28 of 31 checks. The overall rubric result was Fail because all mandatory checks must pass.

The three failed checks are frozen as known V1 limitations:

1. `validation:mandatory_spec_version` — `claim_generator_info` does not contain `specVersion`.
2. `validation:mandatory_all_actions_included` — the actions assertion omits `allActionsIncluded` under the original V1 policy.
3. `validation:inception_action_position` — the `c2pa.created` action is emitted under `gathered_assertions`, not as the first actions assertion in `created_assertions`.

These failures concern required manifest metadata and assertion attribution. They do not reverse the separately verified test-certificate trust, claim-signature validation, WAV hard binding, or tamper detection; they do mean V1 must not be described as Spec 2.4 conformant.

No exporter or manifest behavior was changed after this result. The proposed V1.1 work is to add `specVersion`, choose and document an explicit truthful `allActionsIncluded` value, mark the actions assertion as signer-created, and rerun both automated tests and the hosted rubric.

## Evidence boundary

C2PA validation establishes that the manifest was signed by the configured test credential and that the bound media bytes have not changed. It does not prove that the descriptive claims are factually true, does not create production trust, and does not replace model-license review, product conformance testing, or secure production key management.

The Conformance Tool overview also emits the informational signal `Contains ambiguous actions` when `allActionsIncluded` is omitted. That omission is intentional under the frozen V1 profile; it is recorded as a V1.1 conformance-policy item rather than hidden or silently changed.
