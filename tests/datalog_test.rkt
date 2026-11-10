#lang racket/base

(require rackunit
         racket/set
         "../src/ast.rkt"
         "../src/safety.rkt"
         "../src/strata.rkt"
         "../src/semi_naive.rkt"
         "../src/replayer.rkt"
         "../src/oracle.rkt"
         "../src/json_io.rkt")

(provide run-all-datalog-tests)

;; Test 1: Recursive Reachability (Transitive Closure)
(define (test-reachability)
  (define prog
    (program
     (list
      (rule 'r_base
            (literal 'path (list (var-term 'X) (var-term 'Y)) #t)
            (list (literal 'edge (list (var-term 'X) (var-term 'Y)) #t)))
      (rule 'r_rec
            (literal 'path (list (var-term 'X) (var-term 'Z)) #t)
            (list (literal 'path (list (var-term 'X) (var-term 'Y)) #t)
                  (literal 'edge (list (var-term 'Y) (var-term 'Z)) #t))))
     (list
      (fact 'edge #(a b))
      (fact 'edge #(b c))
      (fact 'edge #(c d)))))

  (define res (evaluate-program prog))
  (check-equal? (evaluation-result-status res) 'COMPLETE)
  ;; Edges: 3. Paths: (a b), (b c), (c d), (a c), (b d), (a d) -> 6. Total: 9.
  (check-equal? (length (evaluation-result-facts res)) 9)

  ;; Verify proofs replay cleanly
  (check-true (replay-all-proofs prog res)))

;; Test 2: Mutually Recursive Positive Predicates
(define (test-mutually-recursive)
  (define prog
    (program
     (list
      (rule 'r_odd_base
            (literal 'odd_path (list (var-term 'X) (var-term 'Y)) #t)
            (list (literal 'edge (list (var-term 'X) (var-term 'Y)) #t)))
      (rule 'r_even
            (literal 'even_path (list (var-term 'X) (var-term 'Z)) #t)
            (list (literal 'odd_path (list (var-term 'X) (var-term 'Y)) #t)
                  (literal 'edge (list (var-term 'Y) (var-term 'Z)) #t)))
      (rule 'r_odd_rec
            (literal 'odd_path (list (var-term 'X) (var-term 'Z)) #t)
            (list (literal 'even_path (list (var-term 'X) (var-term 'Y)) #t)
                  (literal 'edge (list (var-term 'Y) (var-term 'Z)) #t))))
     (list
      (fact 'edge #(1 2))
      (fact 'edge #(2 3))
      (fact 'edge #(3 4)))))

  (define res (evaluate-program prog))
  (check-equal? (evaluation-result-status res) 'COMPLETE)

  (define facts (evaluation-result-facts res))
  ;; Check that even_path(1, 3) and odd_path(1, 4) exist
  (define facts-set (list->set (for/list ([f (in-list facts)]) (cons (fact-predicate f) (fact-args f)))))
  (check-true (set-member? facts-set '(even_path . #(1 3))))
  (check-true (set-member? facts-set '(odd_path . #(1 4))))

  (check-true (replay-all-proofs prog res)))

;; Test 3: Multiple Derivations & Deterministic Proof Selection
(define (test-multiple-derivations)
  ;; diamond graph: a -> b -> d, and a -> c -> d
  ;; path(a, d) can be derived through b or c
  (define prog
    (program
     (list
      (rule 'r_base
            (literal 'path (list (var-term 'X) (var-term 'Y)) #t)
            (list (literal 'edge (list (var-term 'X) (var-term 'Y)) #t)))
      (rule 'r_rec
            (literal 'path (list (var-term 'X) (var-term 'Z)) #t)
            (list (literal 'path (list (var-term 'X) (var-term 'Y)) #t)
                  (literal 'edge (list (var-term 'Y) (var-term 'Z)) #t))))
     (list
      (fact 'edge #(a b))
      (fact 'edge #(a c))
      (fact 'edge #(b d))
      (fact 'edge #(c d)))))

  (define res (evaluate-program prog))
  (check-equal? (evaluation-result-status res) 'COMPLETE)

  ;; path(a, d) must have exactly one proof node
  (define proofs (evaluation-result-proofs res))
  (define p-node (hash-ref proofs '(path . #(a d)) #f))
  (check-not-false p-node)
  (check-equal? (proof-node-rule-id p-node) 'r_rec)

  (check-true (replay-all-proofs prog res)))

;; Test 4: Nullary Predicates (Arity 0)
(define (test-nullary-predicates)
  (define prog
    (program
     (list
      (rule 'r_flag
            (literal 'has_edge '() #t)
            (list (literal 'edge (list (var-term 'X) (var-term 'Y)) #t)))
      (rule 'r_alert
            (literal 'system_active '() #t)
            (list (literal 'has_edge '() #t))))
     (list
      (fact 'edge #(node1 node2)))))

  (define res (evaluate-program prog))
  (check-equal? (evaluation-result-status res) 'COMPLETE)
  (define facts-set (list->set (for/list ([f (in-list (evaluation-result-facts res))]) (cons (fact-predicate f) (fact-args f)))))
  (check-true (set-member? facts-set '(has_edge . #())))
  (check-true (set-member? facts-set '(system_active . #())))

  (check-true (replay-all-proofs prog res)))

;; Test 5: Stratified Negation
(define (test-safe-negation)
  ;; nodes: a, b, c
  ;; edge: a -> b
  ;; disconnected(X, Y) :- node(X), node(Y), not edge(X, Y)
  (define prog
    (program
     (list
      (rule 'r_disc
            (literal 'no_edge (list (var-term 'X) (var-term 'Y)) #t)
            (list (literal 'node (list (var-term 'X)) #t)
                  (literal 'node (list (var-term 'Y)) #t)
                  (literal 'edge (list (var-term 'X) (var-term 'Y)) #f))))
     (list
      (fact 'node #(a))
      (fact 'node #(b))
      (fact 'edge #(a b)))))

  (define res (evaluate-program prog))
  (check-equal? (evaluation-result-status res) 'COMPLETE)

  (define facts-set (list->set (for/list ([f (in-list (evaluation-result-facts res))]) (cons (fact-predicate f) (fact-args f)))))
  ;; (a, a), (b, a), (b, b) must be in no_edge; (a, b) must NOT be in no_edge
  (check-true (set-member? facts-set '(no_edge . #(a a))))
  (check-true (set-member? facts-set '(no_edge . #(b a))))
  (check-true (set-member? facts-set '(no_edge . #(b b))))
  (check-false (set-member? facts-set '(no_edge . #(a b))))

  (check-true (replay-all-proofs prog res)))

;; Test 6: Empty Relations
(define (test-empty-relations)
  (define prog
    (program
     (list
      (rule 'r_empty
            (literal 'target (list (var-term 'X)) #t)
            (list (literal 'source (list (var-term 'X)) #t))))
     '()))

  (define res (evaluate-program prog))
  (check-equal? (evaluation-result-status res) 'COMPLETE)
  (check-equal? (length (evaluation-result-facts res)) 0)
  (check-true (replay-all-proofs prog res)))

;; Test 7: Tampering Detection in Proof Replay
(define (test-tampering-detection)
  (define prog
    (program
     (list
      (rule 'r_step
            (literal 'reach (list (var-term 'X) (var-term 'Y)) #t)
            (list (literal 'edge (list (var-term 'X) (var-term 'Y)) #t))))
     (list
      (fact 'edge #(x y)))))

  (define res (evaluate-program prog))
  (check-equal? (evaluation-result-status res) 'COMPLETE)

  ;; Tamper with proof: alter premises ordinal to an invalid number
  (define proofs (make-hash (hash->list (evaluation-result-proofs res))))
  (define orig-node (hash-ref proofs '(reach . #(x y))))
  (define tampered-node
    (proof-node (proof-node-fact orig-node)
                (proof-node-ordinal orig-node)
                (proof-node-rule-id orig-node)
                '(999) ;; Non-existent premise ordinal
                (proof-node-negative-evidence orig-node)))
  (hash-set! proofs '(reach . #(x y)) tampered-node)

  (define tampered-res
    (evaluation-result
     (evaluation-result-status res)
     (evaluation-result-message res)
     (evaluation-result-strata res)
     (evaluation-result-facts res)
     proofs
     (evaluation-result-derivation-count res)
     (evaluation-result-binding-examinations res)))

  (check-exn replayer-failure?
             (lambda () (replay-all-proofs prog tampered-res))))

;; Test 8: SQLite Relational Oracle Equivalence
(define (test-sqlite-oracle)
  (define prog
    (program
     (list
      (rule 'r_step
            (literal 'path (list (var-term 'X) (var-term 'Y)) #t)
            (list (literal 'edge (list (var-term 'X) (var-term 'Y)) #t)))
      (rule 'r_trans
            (literal 'path (list (var-term 'X) (var-term 'Z)) #t)
            (list (literal 'path (list (var-term 'X) (var-term 'Y)) #t)
                  (literal 'edge (list (var-term 'Y) (var-term 'Z)) #t)))
      (rule 'r_unreach
            (literal 'unreachable (list (var-term 'X) (var-term 'Y)) #t)
            (list (literal 'node (list (var-term 'X)) #t)
                  (literal 'node (list (var-term 'Y)) #t)
                  (literal 'path (list (var-term 'X) (var-term 'Y)) #f))))
     (list
      (fact 'node #(1))
      (fact 'node #(2))
      (fact 'node #(3))
      (fact 'edge #(1 2))
      (fact 'edge #(2 3)))))

  (define res (evaluate-program prog))
  (check-equal? (evaluation-result-status res) 'COMPLETE)

  (define sqlite-facts (evaluate-sqlite-oracle prog))
  (define-values (ok? msg) (compare-with-oracle (evaluation-result-facts res) sqlite-facts))
  (check-true ok? msg))

;; Test 9: Negative Program Rejections (INVALID_PROGRAM)
(define (test-negative-program-rejections)
  ;; 1. Unsafe rule: head variable not in positive body literal
  (define unsafe-rule-prog
    (program
     (list
      (rule 'r_unsafe
            (literal 'bad (list (var-term 'X) (var-term 'Y)) #t)
            (list (literal 'node (list (var-term 'X)) #t))))
     (list (fact 'node #(1)))))

  (check-exn exn:fail? (lambda () (validate-program-safety unsafe-rule-prog)))

  ;; 2. Unsafe negation: variable in negative literal not bound by positive literal
  (define unsafe-neg-prog
    (program
     (list
      (rule 'r_bad_neg
            (literal 'bad (list (var-term 'X)) #t)
            (list (literal 'node (list (var-term 'X)) #t)
                  (literal 'missing (list (var-term 'Z)) #f))))
     (list (fact 'node #(1)))))

  (check-exn exn:fail? (lambda () (validate-program-safety unsafe-neg-prog)))

  ;; 3. Negative dependency cycle: p depends negatively on q, q depends on p
  (define neg-cycle-prog
    (program
     (list
      (rule 'r1
            (literal 'p (list (var-term 'X)) #t)
            (list (literal 'node (list (var-term 'X)) #t)
                  (literal 'q (list (var-term 'X)) #f)))
      (rule 'r2
            (literal 'q (list (var-term 'X)) #t)
            (list (literal 'p (list (var-term 'X)) #t))))
     (list (fact 'node #(1)))))

  (check-exn exn:fail? (lambda () (compute-stratification neg-cycle-prog))))

;; Test 10: JSON Serialization Roundtrip
(define (test-json-roundtrip)
  (define json-str
    #<<JSON
{
  "edb_facts": [
    {"predicate": "link", "args": ["u1", "u2"]}
  ],
  "rules": [
    {
      "id": "r_conn",
      "head": {"predicate": "conn", "terms": [{"var": "A"}, {"var": "B"}]},
      "body": [
        {"predicate": "link", "terms": [{"var": "A"}, {"var": "B"}], "positive": true}
      ]
    }
  ]
}
JSON
)
  (define prog (parse-program-string json-str))
  (define res (evaluate-program prog))
  (check-equal? (evaluation-result-status res) 'COMPLETE)

  (define res-json (evaluation-result->json-string res))
  (check-true (string? res-json))
  (check-true (> (string-length res-json) 20)))

;; Runner for all unit tests
(define (run-all-datalog-tests [verbose? #t])
  (define tests
    (list
     (cons "Recursive reachability (transitive closure)" test-reachability)
     (cons "Mutually recursive positive predicates" test-mutually-recursive)
     (cons "Multiple derivations & deterministic proof selection" test-multiple-derivations)
     (cons "Nullary predicates (arity 0)" test-nullary-predicates)
     (cons "Stratified negation" test-safe-negation)
     (cons "Empty relations" test-empty-relations)
     (cons "Proof tampering detection" test-tampering-detection)
     (cons "SQLite relational oracle comparison" test-sqlite-oracle)
     (cons "Negative program rejection (unsafe rules & cycles)" test-negative-program-rejections)
     (cons "JSON serialization roundtrip" test-json-roundtrip)))

  (define passed-count 0)
  (define failed-count 0)

  (for ([t (in-list tests)])
    (define name (car t))
    (define fn (cdr t))
    (with-handlers ([exn:fail?
                     (lambda (e)
                       (set! failed-count (+ failed-count 1))
                       (when verbose?
                         (printf "  [FAIL] ~a: ~a\n" name (exn-message e))))])
      (fn)
      (set! passed-count (+ passed-count 1))
      (when verbose?
        (printf "  [PASS] ~a\n" name))))

  (when verbose?
    (printf "\nTest summary: ~a/~a passed.\n" passed-count (+ passed-count failed-count)))

  (= failed-count 0))

(module+ test
  (run-all-datalog-tests #t))
