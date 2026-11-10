#lang racket/base

(require racket/contract)

(provide
 (struct-out const-term)
 (struct-out var-term)
 (struct-out literal)
 (struct-out rule)
 (struct-out fact)
 (struct-out program)
 (struct-out evaluation-result)
 (struct-out proof-node)
 MAX-PREDICATES
 MAX-ARITY
 MAX-CONSTANTS
 MAX-INPUT-FACTS
 MAX-RULES
 MAX-VARS-PER-RULE
 MAX-LITERALS-PER-RULE
 MAX-MATERIALIZED-FACTS
 MAX-PROVENANCE-EDGES
 MAX-BINDING-EXAMINATIONS
 MAX-INPUT-BYTES
 MAX-OUTPUT-BYTES)

;; Resource bound constants
(define MAX-PREDICATES 16)
(define MAX-ARITY 3)
(define MAX-CONSTANTS 32)
(define MAX-INPUT-FACTS 4096)
(define MAX-RULES 64)
(define MAX-VARS-PER-RULE 6)
(define MAX-LITERALS-PER-RULE 6)
(define MAX-MATERIALIZED-FACTS 32768)
(define MAX-PROVENANCE-EDGES 131072)
(define MAX-BINDING-EXAMINATIONS 2000000)
(define MAX-INPUT-BYTES 262144)      ; 256 KiB
(define MAX-OUTPUT-BYTES 8388608)    ; 8 MiB

;; Term AST
(struct const-term (val) #:transparent)
(struct var-term (name) #:transparent)

;; Literal AST: predicate (symbol), terms (list of term), positive? (boolean)
(struct literal (predicate terms positive?) #:transparent)

;; Rule AST: id (symbol/string), head (literal, positive? must be #t), body (list of literal)
(struct rule (id head body) #:transparent)

;; Ground Fact: predicate (symbol), args (vector of values/symbols)
(struct fact (predicate args) #:transparent)

;; Program AST
(struct program (rules edb-facts) #:transparent)

;; Provenance Proof Node:
;; fact: fact struct
;; ordinal: integer (derivation sequence number >= 0)
;; rule-id: symbol or 'edb
;; premises: list of integers (earlier derivation ordinals for positive premises)
;; negative-evidence: list of pairs/hashes (lower stratum absence evidence)
(struct proof-node (fact ordinal rule-id premises negative-evidence) #:transparent)

;; Evaluation Result:
;; status: 'COMPLETE | 'UNKNOWN_BUDGET | 'INVALID_PROGRAM
;; message: string
;; strata: list of stratum info
;; facts: list of fact
;; proofs: hash of fact -> proof-node
;; derivation-count: integer
;; binding-examinations: integer
(struct evaluation-result
  (status
   message
   strata
   facts
   proofs
   derivation-count
   binding-examinations)
  #:transparent)
