# finite-rule-provenance

[![CI](https://github.com/martinlofranodeoliveira/finite-rule-provenance/actions/workflows/ci.yml/badge.svg)](https://github.com/martinlofranodeoliveira/finite-rule-provenance/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Racket](https://img.shields.io/badge/Racket-8.7-blue.svg)](https://racket-lang.org/)

Bounded stratified Datalog engine in Racket that computes finite relational fixed points and records deterministic derivation provenance with explicit lower-stratum absence evidence.

Read this in [Português](README.pt-BR.md).

## Features

- **Stratified Evaluation**: Resolves signed predicate dependency graphs and assigns optimal strata, strictly rejecting negative cycles as `INVALID_PROGRAM`.
- **Indexed Semi-Naive Evaluation**: Minimizes redundant joins across recursive fixed-point rounds using differential $\Delta$ relations.
- **Deterministic Derivation Provenance**: Generates exactly one immutable derivation node per derived fact with monotonically earlier premise ordinals.
- **Explicit Negative Absence Evidence**: Negative body literals record explicit absence witnesses from closed lower strata.
- **Independent Proof Replayer**: Replays derivations step-by-step, verifying variable unification and detecting proof tampering.
- **Isolated SQLite Oracle**: Independently verifies relational fixed points using in-memory SQLite joins and `NOT EXISTS` clauses with synthetic table names (`rel_0`).
- **Hard Resource Bounds**: Enforces limits on predicates ($\le 16$), constants ($\le 32$), input facts ($\le 4096$), rules ($\le 64$), materialized facts ($\le 32768$), and binding steps ($\le 2000000$), returning `UNKNOWN_BUDGET` when limits are reached.
- **Zero External Dependencies**: Implemented entirely with Racket standard library components (`racket/base`, `json`, `db`, `rackunit`).

## Quick Start

### Run Tests and Assertions Offline

```bash
# Execute unit tests via raco test
./scripts/test-offline.sh

# Run self-test assertions via the CLI executable
./scripts/demo-offline.sh --assert

# Run demo with JSON output
./scripts/demo-offline.sh --json
```

### Command Line Interface

```bash
# Evaluate a Datalog JSON file
./dist/finite-rule-provenance eval program.json --json

# Replay and independently verify derivation proofs
./dist/finite-rule-provenance replay program.json

# Cross-validate results against SQLite relational engine
./dist/finite-rule-provenance oracle program.json
```

## Programmatic Usage

```racket
#lang racket/base

(require finite-rule-provenance)

(define prog
  (program
   (list
    (rule 'r_step
          (literal 'path (list (var-term 'X) (var-term 'Y)) #t)
          (list (literal 'edge (list (var-term 'X) (var-term 'Y)) #t)))
    (rule 'r_trans
          (literal 'path (list (var-term 'X) (var-term 'Z)) #t)
          (list (literal 'path (list (var-term 'X) (var-term 'Y)) #t)
                (literal 'edge (list (var-term 'Y) (var-term 'Z)) #t))))
   (list
    (fact 'edge #(a b))
    (fact 'edge #(b c)))))

(define res (run-program-rehearsal prog #:oracle? #t))

(printf "Status: ~a\n" (evaluation-result-status res))
(printf "Total facts derived: ~a\n" (length (evaluation-result-facts res)))
```

## Documentation

- [Contract & Resource Boundaries](docs/contract.md)
- [Architectural Design](docs/design.md)
- [Product Vision](PRODUCT.md)

## License

This project is licensed under the [MIT License](LICENSE) © 2026 Lofrano Tecnologia.
