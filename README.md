# Finite Rule Provenance

Development version 0.1.0: a bounded, offline stratified Datalog library with one derivation per fact and lower-stratum absence evidence. Original source belongs to Lofrano Tecnologia; adoption is a hypothesis, not a claim of users or production certification. [Português](README.pt-BR.md).

The library accepts `program`, `rule`, `literal`, `var-term`, `const-term` and `fact` structures exported by `main.rkt`. `evaluate-datalog` returns an `evaluation-result`; `run-program-rehearsal` additionally replays proofs and compares small programs with SQLite. The original semi-naive evaluator uses relation sets and differential rounds. No general Prolog, arithmetic, aggregates, function terms, persistence, incremental updates or external predicates are supported. This is not an authorization, legal, medical or financial decision engine.

## Build and installation

Qualified native platform: Linux x86-64, Racket 8.7 CS (Debian `8.7+dfsg1-1`) and SQLite `3.40.1-2+deb12u2`. Racket's maintained `json`, `db`, package tools and RackUnit retain their responsibilities. The actual resolved package checksums and exact Debian artifacts are recorded in `qualification/`; there is no invented Racket lockfile and no third-party package download during offline gates.

```sh
docker build --target sdk -t finite-rule-sdk .
docker run --rm --network none --user 1000:1000 --cap-drop ALL --security-opt no-new-privileges --pids-limit 256 --memory 1g --cpus 2 finite-rule-sdk /bin/sh scripts/package-gate.sh
docker build -t finite-rule-provenance .
docker run --rm --network none --user 1000:1000 --cap-drop ALL --security-opt no-new-privileges --pids-limit 256 --memory 1g --cpus 2 finite-rule-provenance demo --assert --json
```

The Dockerfile separates official artifact preparation, an offline SDK and the distributed runtime. The final image has no Racket compiler, source checkout or package resolver. A local native checkout can use `/bin/sh scripts/test-offline.sh`, then `/bin/sh scripts/build-offline.sh` and `/bin/sh scripts/demo-offline.sh --assert`. Runtime demo scripts never compile an executable.

To install the real source package, build it with `raco pkg create --source --format zip --dest /your/artifacts /your/checkout`; install the resulting archive under an explicit controlled HOME with `raco pkg install --scope user --deps fail --batch --no-setup --name finite-rule-provenance /your/artifacts/checkout.zip`. The qualified Racket distribution must already supply the dependency closure. The package gate verifies the archive's exact intended source bytes, installs into a fresh user scope and exercises a separate outside-checkout consumer. Raco excludes version-control/workflow files; these are explicitly outside the package inventory.

## CLI and API

This development update uses **stdin only** for JSON input; the previous input-path argument is removed. Shell redirection is the caller's responsibility. The program never opens an arbitrary input pathname.

```sh
printf '%s' '{"edb_facts":[{"predicate":"ready","args":[]}],"rules":[]}' | ./dist/distribution/bin/finite-rule-provenance eval --json
./dist/distribution/bin/finite-rule-provenance replay < examples/program.json
./dist/distribution/bin/finite-rule-provenance oracle < examples/program.json
./dist/distribution/bin/finite-rule-provenance demo --json
```

`examples/program.json` is supplied. `eval` computes; `replay` recomputes then verifies its generated proof; `oracle` also requires at most eight distinct constants and checks SQLite. It does not ingest a third-party proof receipt. Demo modes are plain text, `--assert`, `--json`, or both; every mode checks the same original eight-fact synthetic example. `--help` prints the complete usage. Unknown, duplicate or misplaced arguments are invalid.

```racket
#lang racket/base
(require finite-rule-provenance)
(define result (evaluate-datalog (program null (list (fact 'ready #())))))
(displayln (evaluation-result-status result)) ; COMPLETE
(displayln (evaluation-result->json-string result))
```

Results are `COMPLETE`, `UNKNOWN_BUDGET`, `INVALID_PROGRAM`, or `INCOMPLETE`. CLI exits are respectively 0, 1, 2 and 3; usage/input errors also exit 2. Verification, computation and I/O failures are incomplete, not mathematical negatives. Oracle errors and timeouts never count as successful rejections. Incomplete/budget wrappers expose no partial facts or proofs. The low-level `evaluate-program` retains its explicit exception contract; callers should normally use `evaluate-datalog`.

JSON output is one UTF-8 value followed by a newline, with a matching successful process exit for that status; consumers must require the entire frame and exit code. Stdout is not atomic and I/O failure can truncate it. The maintained JSON reader uses last-member-wins for duplicate object members; unknown schema properties are rejected. JSON constants are strings or exact integers; predicate, rule and variable names are nonempty strings. Terms contain exactly one of `var` or `const`; rule IDs are unique and `edb` is reserved.

## Bounds and limitations

At most 16 predicates of arity 0..3, 32 constants, 4096 input facts, 64 rules, and six variables/body literals per rule are admitted. Head/negative variables must occur positively. Negative dependency cycles are invalid. Evaluation caps are 32768 facts, 131072 positive proof edges and 2000000 candidate examinations; input is at most 262144 UTF-8 bytes and complete output, including its newline, is at most 8388608 bytes. `evaluate-datalog` and the frame encoder also accept a lower output budget of 512..8388608 bytes for callers/tests. A budget result contains no partial relation and is not a proof of emptiness.

Logical counters do not bound parser, VM, JSON-object, string-conversion or native SQLite allocations, RSS or wall-clock time. The output byte sink checks before appending; an internal representation may allocate first. A stalled inherited stdin/stdout is incomplete under the external container owner. Use only cooperative local Linux filesystems, stable owned checkouts and nonconcurrent access to caller AST/receipt objects; no hostile-filesystem snapshot or deep object sandbox is promised. No numeric PID/PGID signaling, runtime subprocesses, network, telemetry, credentials or external APIs are used by the application.

See [contract](docs/contract.md), [design](docs/design.md) and [third-party notices](THIRD_PARTY_NOTICES.md). Original source is [MIT](LICENSE), © 2026 Lofrano Tecnologia; the distribution and its dependencies retain their own licenses. Official site: https://lofranotecnologia.com.br.
