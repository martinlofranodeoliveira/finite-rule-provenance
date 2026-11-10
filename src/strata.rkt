#lang racket/base

(require racket/set
         "ast.rkt"
         "safety.rkt")

(provide compute-stratification
         (struct-out stratum-info))

(struct stratum-info (index predicates rules idb-predicates) #:transparent)

;; Computes predicate stratification.
;; Returns a list of stratum-info ordered by stratum index (0, 1, ...).
;; If there is a cycle containing a negative edge, raises an error with 'INVALID_PROGRAM reason.
(define (compute-stratification prog)
  (define pred-arities (extract-predicates prog))
  (define all-preds (hash-keys pred-arities))

  ;; Positive dependencies: head -> set of body preds
  (define pos-deps (make-hash))
  ;; Negative dependencies: head -> set of body preds
  (define neg-deps (make-hash))

  (for ([p (in-list all-preds)])
    (hash-set! pos-deps p (mutable-set))
    (hash-set! neg-deps p (mutable-set)))

  ;; Rules per head predicate
  (define rules-by-head (make-hash))
  (for ([p (in-list all-preds)])
    (hash-set! rules-by-head p '()))

  (for ([r (in-list (program-rules prog))])
    (define h (literal-predicate (rule-head r)))
    (hash-set! rules-by-head h (cons r (hash-ref rules-by-head h '())))
    (for ([lit (in-list (rule-body r))])
      (define body-p (literal-predicate lit))
      (if (literal-positive? lit)
          (set-add! (hash-ref pos-deps h) body-p)
          (set-add! (hash-ref neg-deps h) body-p))))

  ;; 1. Check for negative cycles using Bellman-Ford / Floyd-Warshall / DFS.
  ;; We have at most 16 predicates, so Floyd-Warshall or Tarjan's SCC is extremely fast.
  ;; Let's compute reachability with edge types.
  ;; A negative cycle exists iff there is a path from P to P that traverses at least one negative edge.
  ;; Let has-path(A, B, neg?) be whether there is a path from A to B with or without negative edges.
  ;; Notice: dependency edge is from body to head (body is computed before head).
  ;; So B -> H: H depends on B.
  ;; If H depends on B negatively, edge is B -neg-> H.
  ;; If H depends on B positively, edge is B -pos-> H.
  ;; A cycle means H1 depends on H2 ... depends on H1.
  ;; If any step is negative, then H1 must be in a strictly higher stratum than H1, which is impossible!

  ;; Let's define directed dependency edges: from body-pred to head-pred
  ;; edge(U, V) = 'pos or 'neg
  (define preds-list all-preds)
  (define n (length preds-list))
  (define pred->idx (make-hash))
  (for ([p (in-list preds-list)] [i (in-naturals)])
    (hash-set! pred->idx p i))

  ;; dist[i][j]: minimal negative cost or -infinity.
  ;; Alternatively: let longest path in DAG where pos=0, neg=1.
  ;; If there is a cycle with weight >= 1, then invalid!
  ;; Let's check with Bellman-Ford on all pairs.
  (define dist (make-vector (* n n) -1000000))
  (define (get-dist u v) (vector-ref dist (+ (* u n) v)))
  (define (set-dist! u v val) (vector-set! dist (+ (* u n) v) val))

  (for ([i (in-range n)])
    (set-dist! i i 0))

  (for ([h (in-list all-preds)])
    (define v (hash-ref pred->idx h))
    (for ([b (in-set (hash-ref pos-deps h))])
      (define u (hash-ref pred->idx b))
      (when (> 0 (get-dist u v))
        (set-dist! u v 0)))
    (for ([b (in-set (hash-ref neg-deps h))])
      (define u (hash-ref pred->idx b))
      (when (> 1 (get-dist u v))
        (set-dist! u v 1))))

  ;; Floyd-Warshall for longest paths
  (for ([k (in-range n)])
    (for ([i (in-range n)])
      (for ([j (in-range n)])
        (define dik (get-dist i k))
        (define dkj (get-dist k j))
        (when (and (> dik -500000) (> dkj -500000))
          (define new-d (+ dik dkj))
          (when (> new-d (get-dist i j))
            (set-dist! i j new-d))))))

  ;; Check for negative cycle: if dist[i][i] > 0 for any i, negative cycle detected!
  (for ([i (in-range n)])
    (when (> (get-dist i i) 0)
      (define p (list-ref preds-list i))
      (error 'compute-stratification
             "Program contains a cycle with negative dependency involving predicate ~a (not stratifiable)"
             p)))

  ;; Helper to update max-s
  (define-syntax-rule (set-max-s! var val)
    (when (> val var) (set! var val)))

  ;; Calculate stratum number for each predicate:
  ;; stratum(p) = max(0, max_{b} dist[b][p])
  (define pred-stratum (make-hash))
  (for ([p (in-list preds-list)])
    (define v (hash-ref pred->idx p))
    (define max-s 0)
    (for ([u (in-range n)])
      (define d (get-dist u v))
      (set-max-s! max-s d))
    (hash-set! pred-stratum p max-s))

  ;; Find maximum stratum index
  (define max-stratum 0)
  (for ([(p s) (in-hash pred-stratum)])
    (set-max-s! max-stratum s))

  ;; Group predicates and rules into strata
  (define strata-result '())
  (for ([s (in-range (+ max-stratum 1))])
    (define stratum-preds
      (for/list ([p (in-list preds-list)]
                 #:when (= (hash-ref pred-stratum p) s))
        p))
    (define stratum-rules
      (for/fold ([acc '()]) ([p (in-list stratum-preds)])
        (append acc (hash-ref rules-by-head p '()))))
    (define idb-preds
      (for/list ([p (in-list stratum-preds)]
                 #:when (not (null? (hash-ref rules-by-head p '()))))
        p))
    (set! strata-result
          (cons (stratum-info s stratum-preds stratum-rules idb-preds) strata-result)))

  (reverse strata-result))
