#lang racket/base
;; Original coordinator-owned test helper. The reference uses only fixed native
;; SQLite recursive joins/set difference; it does not use the project's oracle,
;; safety analysis, rule ordering or stratification to compute expected facts.
(require db racket/set racket/list (file "/work/source/main.rkt"))

(define x (var-term 'X))
(define y (var-term 'Y))
(define z (var-term 'Z))
(define rules
  (list
   (rule 'base (literal 'path (list x y) #t)
         (list (literal 'edge (list x y) #t)))
   (rule 'step (literal 'path (list x z) #t)
         (list (literal 'path (list x y) #t) (literal 'edge (list y z) #t)))
   (rule 'missing (literal 'missing (list x y) #t)
         (list (literal 'node (list x) #t) (literal 'node (list y) #t)
               (literal 'path (list x y) #f)))
   (rule 'flag (literal 'has_edge null #t)
         (list (literal 'edge (list x y) #t)))))

(define candidates (for*/list ([a (in-range 3)] [b (in-range 3)]) (vector a b)))
(define closure-sql
  "WITH RECURSIVE reach(a,b) AS (SELECT a,b FROM edge UNION SELECT r.a,e.b FROM reach r JOIN edge e ON r.b=e.a) ")

(for ([mask (in-range 512)])
  (define edges
    (for/list ([pair (in-list candidates)] [bit (in-naturals)]
               #:when (bitwise-bit-set? mask bit)) pair))
  (define connection (sqlite3-connect #:database 'memory))
  (query-exec connection "CREATE TABLE edge(a INTEGER,b INTEGER)")
  (query-exec connection "CREATE TABLE node(a INTEGER)")
  (for ([n (in-range 3)]) (query-exec connection "INSERT INTO node VALUES(?)" n))
  (for ([edge (in-list edges)])
    (query-exec connection "INSERT INTO edge VALUES(?,?)" (vector-ref edge 0) (vector-ref edge 1)))
  (define expected-path
    (list->set (query-rows connection (string-append closure-sql "SELECT a,b FROM reach"))))
  (define expected-missing
    (list->set
     (query-rows connection
                 (string-append closure-sql
                                "SELECT n.a,m.a FROM node n CROSS JOIN node m WHERE NOT EXISTS(SELECT 1 FROM reach r WHERE r.a=n.a AND r.b=m.a)"))))
  (define expected-flag (not (zero? (query-value connection "SELECT EXISTS(SELECT 1 FROM edge)"))))
  (disconnect connection)
  (define problem
    (program rules
             (append (for/list ([n (in-range 3)]) (fact 'node (vector n)))
                     (for/list ([edge (in-list edges)]) (fact 'edge edge)))))
  (define result (evaluate-datalog problem))
  (unless (eq? (evaluation-result-status result) 'COMPLETE)
    (error 'independent-oracle "unexpected noncomplete result for synthetic mask ~a" mask))
  (define (actual predicate)
    (list->set
     (for/list ([f (in-list (evaluation-result-facts result))]
                #:when (eq? (fact-predicate f) predicate))
       (fact-args f))))
  (unless (and (set=? (actual 'path) expected-path)
               (set=? (actual 'missing) expected-missing)
               (equal? (not (set-empty? (actual 'has_edge))) expected-flag))
    (error 'independent-oracle "relational mismatch for synthetic mask ~a" mask))
  (unless (replay-all-proofs problem result)
    (error 'independent-oracle "proof replay failed for synthetic mask ~a" mask)))
(displayln "PASS: 512 exhaustive directed graphs; native SQLite recursive joins, lower-stratum set difference, nullary evidence and proof replay")
