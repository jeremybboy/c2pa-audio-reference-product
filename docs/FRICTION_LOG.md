# C2PA Implementation Friction Log

This file records every obstacle encountered while implementing C2PA export, signing, embedding, validation, and conformance preparation. Entries must separate verified behavior from hypotheses, include reproducible evidence where possible, and record both unresolved blockers and successful workarounds. The accumulated evidence will inform the reusable Audio C2PA Reference Kit.

## V1 entries

### 2026-08-20 — c2patool default intent violates the no-ingredient profile

- Category: Assertions
- Pipeline stage: Manifest embedding
- Status: Resolved
- Environment and versions: c2patool 0.27.15 / c2pa-rs 0.90.15
- Expected behavior: Embed only one `c2pa.created` action with no ingredients.
- Observed behavior: The default edit intent automatically added a parent ingredient and `c2pa.opened`.
- Reproduction steps: Sign an existing WAV with `--manifest` but without an explicit create-intent flag.
- Impact: The output violates the frozen V1 profile even when the supplied JSON contains only the intended action.
- Workaround or resolution: Sign with `--create trainedAlgorithmicMedia`; profile inspection then confirms one action and no ingredients.
- Remaining question: None for V1.

### 2026-08-20 — Conformance Test Root location differs from documentation

- Category: Documentation
- Pipeline stage: Trust setup
- Status: Mitigated
- Environment and versions: C2PA Conformance Tool commit `44c81e07fc92b39a525412f4e7a1c2cda0757beb`
- Expected behavior: The README-referenced `public/test-certs/test-root-cert.pem` would be present.
- Observed behavior: The current source does not contain that standalone file; Test Mode embeds `TEST_ROOT_CERT_PEM` in `src/lib/CertificateManager.svelte`.
- Impact: A setup script following the apparent public path cannot reproduce Test Mode trust.
- Workaround or resolution: `setup_c2pa.sh` fetches the pinned source file, verifies its checksum, extracts the public root, and verifies the resulting canonical PEM checksum.
- Remaining question: Whether the upstream project will publish the root as a stable standalone artifact.

### 2026-08-20 — Official signing bundle is one combined PEM

- Category: Certificates
- Pipeline stage: Credential loading
- Status: Resolved
- Environment and versions: Official `test-signing-bundle.pem`, c2patool 0.27.15
- Expected behavior: Signer APIs often expose separate certificate-chain and private-key paths.
- Observed behavior: The official ZIP contains one PEM with one certificate and one EC private key; c2patool accepts the same path for both fields.
- Impact: Splitting or copying files into the repository would add unnecessary secret-handling risk.
- Workaround or resolution: `SigningCredentialProvider` supplies the same external path for certificate and key after readability checks. Setup verifies fingerprint, key match, and chain without copying the file.
- Remaining question: Production providers will need Keychain, HSM, or remote-signing implementations rather than a file provider.

### 2026-08-20 — Signing output is untrusted without explicit test trust

- Category: Trust
- Pipeline stage: Validation
- Status: Resolved
- Environment and versions: c2patool 0.27.15, C2PA Conformance Test Root
- Expected behavior: Test output should validate as trusted only when Test Mode trust is intentionally enabled.
- Observed behavior: Signing-time inspection reports `signingCredential.untrusted`; validation with the Test Root and purpose configuration reports `Trusted` and `signingCredential.trusted`.
- Impact: Signature validity and signer trust can be easily conflated.
- Workaround or resolution: V1 treats validation as a separate mandatory step and requires `signingCredential.trusted`, `claimSignature.validated`, and `assertion.dataHash.match` with no failures.
- Remaining question: Production trust policy is deferred.

### 2026-08-20 — Trust subcommand does not accept output-path option

- Category: Developer experience
- Pipeline stage: Evidence capture
- Status: Resolved
- Environment and versions: c2patool 0.27.15
- Expected behavior: The general `--output` option would save detailed trust JSON.
- Observed behavior: The `trust` subcommand rejects `--output`; its report is emitted on standard output.
- Impact: A naive evidence command fails after successful signing.
- Workaround or resolution: `C2PAToolRunner` captures standard output directly and the verification executable writes it atomically to the evidence directory.
- Remaining question: None.

### 2026-08-20 — Hard binding detects WAV payload modification

- Category: Audio/WAV embedding
- Pipeline stage: Negative validation
- Status: Resolved
- Environment and versions: Four-second 44.1 kHz stereo 24-bit PCM WAV
- Expected behavior: Changing bound audio bytes should invalidate the asset.
- Observed behavior: Flipping one byte at offset 1000 changed validation from `Trusted` to `Invalid` with `assertion.dataHash.mismatch`; claim signature and signing trust remained independently valid.
- Impact: Confirms the validator distinguishes manifest-signature validity from media hard-binding integrity.
- Workaround or resolution: The real integration test and `verify_c2pa.sh` preserve this as a required negative test.
- Remaining question: Broader mutation and metadata round-trip cases belong in V2.

### 2026-08-20 — Omitted completeness flag creates an ambiguity signal

- Category: Conformance requirements
- Pipeline stage: Conformance Tool review
- Status: Deferred
- Environment and versions: Official hosted C2PA Conformance Tool, Test Mode with one Test Root
- Expected behavior: V1 omits `allActionsIncluded` because completeness is not substantiated.
- Observed behavior: Trust and integrity succeed, while the overview also displays the informational signal `Contains ambiguous actions`.
- Impact: The frozen V1 profile is valid and trusted but deliberately does not assert a complete action history.
- Workaround or resolution: Keep the omission in frozen V1, document the signal, and defer the explicit value and policy decision to V1.1.
- Remaining question: What product evidence is sufficient to set `allActionsIncluded` truthfully for generated audio?

### 2026-08-20 — Formal Spec 2.4 rubric passes 28 of 31 checks

- Category: Conformance requirements
- Pipeline stage: Hosted Conformance Tool rubric
- Status: Deferred to V1.1
- Environment and versions: C2PA Asset Conformance 0.2 / Spec 2.4 rubric v1.0, Test Mode enabled
- Expected behavior: The trusted V1 WAV would be assessed against the mandatory Spec 2.4 asset checks.
- Observed behavior: The export passed 28 of 31 checks. It failed mandatory `specVersion`, mandatory `allActionsIncluded`, and inception-action position because the actions assertion was reported in `gathered_assertions` instead of first in `created_assertions`.
- Impact: The signed WAV remains test-trusted and tamper-detecting, but V1 cannot claim full Spec 2.4 conformance.
- Workaround or resolution: Freeze the working V1 implementation and document the exact result. V1.1 may add `specVersion`, an explicit truthful `allActionsIncluded` value, and signer-created assertion attribution, followed by a full rubric rerun.
- Remaining question: Confirm the emitted `created_assertions` order after the V1.1 attribution change.

## Entry template

```markdown
### YYYY-MM-DD — Short title

- Category:
- Pipeline stage:
- Status: Open | Mitigated | Resolved | Deferred
- Environment and versions:
- Expected behavior:
- Observed behavior:
- Reproduction steps:
- Evidence or error output:
- Impact:
- Workaround or resolution:
- Remaining question:
- Related commit, issue, or specification section:
```

## Categories

### Specification ambiguity

Record unclear, conflicting, or underspecified requirements in the C2PA specification or supporting guidance.

### SDK/API friction

Record integration problems, unstable interfaces, language bindings, version incompatibilities, and missing capabilities.

### Audio/WAV embedding

Record container-layout, chunk-ordering, size, compatibility, metadata-preservation, and round-trip problems.

### Assertions

Record assertion selection, schema, serialization, claim scope, and interoperability issues.

### Generation metadata mapping

Record decisions and failures when mapping `GenerationRecord` fields into C2PA assertions or ingredients.

### Signing

Record signing configuration, algorithms, key handling, signature generation, and verification problems.

### Certificates

Record certificate profiles, chains, extensions, development credentials, and interoperability problems. Never commit private keys or certificate containers that include private keys.

### TSA

Record timestamp-authority requirements, protocols, availability, policy, and validation behavior.

### Validation

Record validator differences, positive and negative test results, error interpretation, and reproducibility.

### Trust

Record trust-anchor configuration, chain-building behavior, trust-list assumptions, and the distinction between cryptographic validity and trusted identity.

### Security requirements

Record threat-model, key-protection, sandboxing, dependency, and secure-distribution concerns.

### Conformance requirements

Record conformance-test expectations, unsupported cases, evidence requirements, and submission-readiness gaps.

### Documentation

Record missing, outdated, contradictory, or misleading implementation documentation.

### Developer experience

Record setup cost, tooling discoverability, diagnostics, iteration time, and integration ergonomics.
