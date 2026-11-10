# Architectural Design

## 1. Engine Architecture

`finite-rule-provenance` is organized into distinct phases with clear mathematical boundaries:

```
                  [ JSON / AST Input ]
                           │
                           ▼
                 Phase 1: Rule Safety
          Range restriction, arity consistency,
                 pred/const bounds checks
                           │
                           ▼
              Phase 2: Stratification Engine
          Signed dependency graph (Floyd-Warshall)
            Negative cycle rejection (INVALID_PROGRAM)
                           │
                           ▼
          Phase 3: Stratified Semi-Naive Evaluator
          Evaluates stratum by stratum; joins via Delta_k;
          guards budgets (materialized facts, examinations)
                           │
                           ▼
              Phase 4: Provenance Recorder
          Assigns derivation ordinals; records premises
          and lower-stratum absence evidence
                           │
            ┌──────────────┴──────────────┐
            ▼                             ▼
 Phase 5: Proof Replayer       Phase 6: Relational Oracle
 Verifies variable unifications    In-memory SQLite evaluator;
 and ordinals; detects tampering   synthetic table names only
```

## 2. Stratification & Dependency Analysis

The dependency graph contains nodes for all predicates $P \in \mathcal{P}$ and signed edges:
- Positive edge $Q \xrightarrow{+} P$: predicate $Q$ occurs in a positive body literal of a rule for $P$.
- Negative edge $Q \xrightarrow{-} P$: predicate $Q$ occurs in a negative body literal of a rule for $P$.

Using an all-pairs longest path algorithm where positive edges have weight $0$ and negative edges have weight $1$:
- Any path from node $i$ back to node $i$ with total weight $\ge 1$ constitutes a cycle containing a negative edge.
- If such a cycle exists, the program is unstratifiable and rejected immediately with `INVALID_PROGRAM`.
- Otherwise, the stratum of predicate $P$ is given by:
  $$\text{stratum}(P) = \max_{Q} \text{dist}(Q, P)$$

## 3. Indexed Semi-Naive Evaluation

Within each stratum $s$:
1. Base rules (rules whose positive body literals reference only lower strata) are evaluated first to generate the initial differential $\Delta_1$.
2. In subsequent rounds $k \ge 1$:
   - For each recursive rule, candidate variable bindings are formed such that at least one recursive positive literal is bound to an element of $\Delta_k$.
   - This eliminates redundant re-derivations of previously known tuples.
3. Negative literals reference relations in lower strata $< s$, which are already completely closed and immutable, avoiding temporary negation oscillation.

## 4. Independent SQLite Relational Oracle

To guard against engine implementation bugs, smaller fixtures ($\le 8$ constants) are verified against an independent relational execution in SQLite:
- Every predicate $P$ is mapped to a synthetic identifier `rel_i`.
- Every argument position is mapped to `col_j`.
- User identifiers never become SQL tokens.
- Datalog rules are translated to relational queries:
  ```sql
  INSERT OR IGNORE INTO rel_head (col_0, col_1)
  SELECT DISTINCT t_0.col_0, t_1.col_1
  FROM rel_0 AS t_0, rel_1 AS t_1
  WHERE t_0.col_1 = t_1.col_0
    AND NOT EXISTS (SELECT 1 FROM rel_neg AS neg_0 WHERE neg_0.col_0 = t_0.col_0)
  ```
- The fixed-point relations from SQLite are converted back to Datalog facts and compared via set equivalence against the semi-naive evaluator's results.
