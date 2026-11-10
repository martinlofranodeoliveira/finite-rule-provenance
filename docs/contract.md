# Numeric Contract and Resource Boundaries

`finite-rule-provenance` enforces strict deterministic execution under the following numeric limits and mathematical invariants:

## 1. Resource Limits

| Resource Metric | Limit | Description |
| :--- | :--- | :--- |
| `MAX-PREDICATES` | 16 | Maximum number of distinct predicates |
| `MAX-ARITY` | 3 | Maximum predicate arity (0, 1, 2, or 3) |
| `MAX-CONSTANTS` | 32 | Maximum number of distinct constants |
| `MAX-INPUT-FACTS` | 4,096 | Maximum number of EDB input facts |
| `MAX-RULES` | 64 | Maximum number of IDB rules |
| `MAX-VARS-PER-RULE` | 6 | Maximum distinct variables per rule |
| `MAX-LITERALS-PER-RULE` | 6 | Maximum body literals per rule |
| `MAX-MATERIALIZED-FACTS` | 32,768 | Hard cap on total facts in relations |
| `MAX-PROVENANCE-EDGES` | 131,072 | Hard cap on total positive derivation edges |
| `MAX-BINDING-EXAMINATIONS` | 2,000,000 | Maximum candidate rule binding examinations |
| `MAX-INPUT-BYTES` | 262,144 bytes (256 KiB) | Maximum input JSON payload size |
| `MAX-OUTPUT-BYTES` | 8,388,608 bytes (8 MiB) | Maximum serialized output size |

## 2. Syntactic & Safety Requirements

1. **Range Restriction (Safety)**:
   - Every variable appearing in the rule head must appear in at least one positive body literal.
   - Every variable appearing in a negative body literal (`(not (Q ...))`) must appear in at least one positive body literal.
2. **Ground EDB Facts**:
   - Facts cannot contain variables.
3. **No Function Symbols**:
   - Terms are strictly restricted to atomic constants (symbols, strings, integers) and variables. Compound functor terms (`f(X)`) are disallowed.
4. **Stratification**:
   - The dependency graph must contain zero cycles passing through a negative edge.
   - For any negative dependency $Q \xrightarrow{-} P$, $\text{stratum}(Q) < \text{stratum}(P)$.

## 3. Derivation Provenance Invariants

1. **Monotonic Derivation Ordinals**:
   - EDB facts are assigned ordinals $0 \le \text{ord} < E$.
   - IDB facts derived by rules receive ordinals $\text{ord} \ge E$.
   - For any derived fact $F$ with premises $P_1, \dots, P_k$:
     $$\forall i \in \{1, \dots, k\}, \quad \text{ordinal}(P_i) < \text{ordinal}(F)$$
2. **Deterministic Canonical Proof**:
   - Exactly one derivation is recorded per distinct fact. Once a fact is derived, alternative subsequent derivations are discarded.
3. **Negative Evidence**:
   - Each negative body literal produces an absence witness: $(\text{predicate}, \text{tuple}, \text{stratum})$.
   - The absence witness proves that $\text{tuple} \notin \text{relation}(\text{predicate})$ at the time stratum was closed.

## Framing, I/O and failure boundaries

The CLI accepts JSON only through stdin and retains at most 262145 bytes before rejecting excess. The input limit is UTF-8 bytes, not character count. No arbitrary pathname adapter is exposed. JSON uses the maintained reader's last-member-wins duplicate policy and rejects unknown schema properties. Typed AST calls accept only the documented structures/scalar constants; stable nonconcurrent caller objects are required.

`evaluate-datalog` admits complete output through a private bounded byte sink before returning COMPLETE. The 8388608-byte cap includes newline; an explicitly smaller output budget must be 512..8388608. Excess produces UNKNOWN_BUDGET with empty facts/proofs. JSON serializers apply the same admission. Parsing, object construction and VM/native allocation can precede byte-sink checks; counters do not guarantee RSS or deadlines.

CLI status/exit pairs are COMPLETE/0, UNKNOWN_BUDGET/1, INVALID_PROGRAM/2, INCOMPLETE/3. Verification and infrastructure errors are incomplete, never negative proofs. Require one full newline-terminated JSON frame and its matching exit. Output is not atomic and may be truncated by I/O failure. Stalled inherited streams remain incomplete under external container ownership. Only owned cooperative local Linux filesystems and stable evidence leases are qualified.
