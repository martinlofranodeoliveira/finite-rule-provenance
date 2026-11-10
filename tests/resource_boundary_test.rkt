#lang racket/base
(require rackunit racket/list "../main.rkt")
(define x (var-term 'X)) (define y (var-term 'Y)) (define z (var-term 'Z))
(define nodes (for/list ([n (in-range 32)]) (fact 'node (vector n))))
(define positive-nodes (list (literal 'node (list x) #t) (literal 'node (list y) #t) (literal 'node (list z) #t)))
(define fact-exhaustion
  (program (list (rule 'cartesian (literal 'triple (list x y z) #t) positive-nodes)) nodes))
(define proof-exhaustion
  (program (list (rule 'six-premises (literal 'triple (list x y z) #t)
                       (append positive-nodes (make-list 3 (literal 'flag null #t)))))
           (cons (fact 'flag #()) nodes)))
(define u (var-term 'U)) (define v (var-term 'V)) (define a (var-term 'A)) (define b (var-term 'B))
(define work-exhaustion
  (program (list (rule 'join (literal 'exists null #t)
                       (list (literal 'edge (list x y) #t)
                             (literal 'edge (list u v) #t)
                             (literal 'edge (list a b) #t))))
           (for*/list ([i (in-range 32)] [j (in-range 32)]) (fact 'edge (vector i j)))))
(module+ test
  (for ([problem (in-list (list fact-exhaustion proof-exhaustion work-exhaustion))]
        [metric (in-list '(materialized-facts provenance-edges binding-examinations))])
    ;; A crash, deadline or unrelated exception cannot satisfy this predicate.
    (check-exn (lambda (e) (and (budget-exceeded-exception? e)
                                (eq? (budget-exceeded-exception-metric e) metric)
                                (> (budget-exceeded-exception-value e)
                                   (budget-exceeded-exception-limit e))))
               (lambda () (evaluate-program problem)))
    (define incomplete (evaluate-datalog problem))
    (check-equal? (evaluation-result-status incomplete) 'UNKNOWN_BUDGET)
    (check-equal? (evaluation-result-facts incomplete) null)
    (check-equal? (hash-count (evaluation-result-proofs incomplete)) 0)))
