# Changelog

All notable changes to `finite-rule-provenance` will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-11-09

### Added
- Initial implementation of bounded stratified Datalog in Racket with relational fixed points and derivation provenance.
- Range-restriction and rule safety validator (`src/safety.rkt`).
- Signed dependency analysis and stratification engine with negative cycle detection (`src/strata.rkt`).
- Indexed semi-naive evaluation engine with strict budget guards (`src/semi_naive.rkt`).
- Deterministic single-derivation provenance recorder and proof node generator (`src/provenance.rkt` / `src/ast.rkt`).
- Independent derivation proof replayer and tampering detector (`src/replayer.rkt`).
- Independent relational SQLite oracle evaluator (`src/oracle.rkt`) with safe synthetic SQL table mappings.
- JSON serialization and parsing (`src/json_io.rkt`).
- CLI executable (`bin/cli.rkt`) supporting `demo --assert`, `eval`, `replay`, and `oracle`.
- Comprehensive test suite (`tests/datalog_test.rkt`) with 34 test assertions covering 10 test groups.
- Offline execution scripts (`scripts/test-offline.sh`, `scripts/demo-offline.sh`).
- GitHub Actions CI workflow with offline qualification.
