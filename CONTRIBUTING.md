# Contributing to finite-rule-provenance

Thank you for your interest in contributing to `finite-rule-provenance`!

## Architectural Principles

1. **Zero Unvetted Dependencies**: We use only Racket standard library components (`racket/base`, `json`, `db`, `rackunit`). Any additional dependency requires explicit security audit and qualification.
2. **Deterministic Offline Execution**: All builds, unit tests, fixed-point derivations, and oracle evaluations run strictly offline (`--network none`).
3. **Range Restriction & Safety**: Every variable appearing in a rule head or negative literal must occur in at least one positive body literal.
4. **Stratified Negation**: Negative dependencies must strictly reference closed lower strata; cyclic negative dependencies are rejected as `INVALID_PROGRAM`.
5. **Exact Single Provenance**: Every derived fact records exactly one deterministic proof node with monotonically earlier premise ordinals.
6. **Bounded Resource Consumption**: Limits on predicates ($\le 16$), constants ($\le 32$), input facts ($\le 4096$), rules ($\le 64$), materialized facts ($\le 32768$), proof edges ($\le 131072$), and candidate binding examinations ($\le 2000000$) are strictly enforced.

## Development Workflow

```bash
# Run unit tests offline
./scripts/test-offline.sh

# Run self-test assertions
./scripts/demo-offline.sh --assert

# Run demo with JSON output
./scripts/demo-offline.sh --json
```

## Pull Request Guidelines

- Ensure `scripts/test-offline.sh` and `scripts/demo-offline.sh --assert` pass cleanly.
- Maintain code formatting conforming to `.editorconfig`.
- Preserve documentation and test coverage across recursive reachability, negation, proof replay, and SQLite oracle comparisons.
