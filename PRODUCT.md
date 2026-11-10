# PRODUCT.md - finite-rule-provenance

## Overview

`finite-rule-provenance` is an enterprise-grade, memory-safe stratified Datalog engine in Racket that computes finite relational fixed points and records deterministic, verifiable derivation provenance for every derived fact.

In distributed policy evaluation, compliance auditing, access control verification, and semantic knowledge graph analysis, automated rule evaluation frequently suffers from two critical flaws:
1. **Opaque Deductions ("Black-Box Derivations")**: Systems infer conclusions or access grants without explaining *how* or *why* the conclusion was derived, making compliance verification and security audits impossible.
2. **Infinite Loops & Memory Exhaustion**: Naive recursive evaluation engines without strict stratification or combinatorial budgets easily hang on circular definitions or consume excessive memory when processing untrusted rules.

`finite-rule-provenance` solves both challenges:
- **Provable Explanations**: Every derived fact is paired with an immutable proof node recording the exact rule and monotonically earlier derivation ordinals of positive premises, along with explicit absence witnesses for lower-stratum negative literals.
- **Strict Bounded Execution**: Enforces compile-time range restriction, signed dependency cycle rejection (detecting unstratifiable negation upfront), and runtime limits on facts, proof edges, and binding examinations.

## Key Capabilities

1. **Stratified Negation with Signed Dependency Analysis**:
   - Decomposes rules into dependency strata where negative literals strictly reference closed, immutable relations from lower strata.
   - Immediately detects and rejects negative dependency cycles as `INVALID_PROGRAM`.

2. **Indexed Semi-Naive Evaluation**:
   - Avoids redundant joins across fixed-point iteration rounds by joining at least one recursive positive literal from $\Delta_k$.
   - Maintains strict memory budgets ($\le 32,768$ facts, $\le 131,072$ proof edges, $\le 2,000,000$ candidate binding steps), returning `UNKNOWN_BUDGET` if thresholds are exceeded.

3. **Deterministic Single-Proof Recording**:
   - Rather than storing an exponential graph of all possible derivations, deterministically selects and preserves exactly one canonical derivation per fact.
   - Guarantees that positive proof edges reference strictly earlier derivation ordinals, yielding acyclic, easily auditable proof trees.

4. **Independent Proof Replayer & Tampering Detection**:
   - Ships with an independent proof verification engine (`replay-all-proofs`) that re-checks each step, verifying variable bindings, premise ordinals, and absence witnesses.
   - Detects premise swapping, altered ordinals, or forged EDB claims with typed failure exceptions.

5. **Relational Oracle Validation**:
   - Includes an independent SQLite relational evaluator that translates Datalog programs with up to 8 constants into relational queries (`JOIN`, `NOT EXISTS`).
   - Completely isolates user predicate and variable names by translating them into synthetic SQL identifiers (`rel_0`, `col_0`).

## Distribution boundary

This development SDK uses stdin-only JSON and explicit complete/incomplete result framing. Original MIT source, Racket/SQLite runtime and Debian tooling have separate licenses described in THIRD_PARTY_NOTICES.md. Logical bounds are not memory or deadline guarantees. No production adoption, authorization certification or commercial delivery is asserted.
