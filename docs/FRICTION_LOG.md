# C2PA Implementation Friction Log

This file records every obstacle encountered while implementing C2PA export, signing, embedding, validation, and conformance preparation. Entries must separate verified behavior from hypotheses, include reproducible evidence where possible, and record both unresolved blockers and successful workarounds. The accumulated evidence will inform the reusable Audio C2PA Reference Kit.

V1 implementation has not started, so there are no C2PA friction entries yet.

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
