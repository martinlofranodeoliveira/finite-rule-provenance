#lang racket/base
(require racket/set "../main.rkt")
(provide demo-result)
;; Runtime-owned synthetic fixture; no test modules or RackUnit dependency.
(define (demo-result)
  (define x (var-term 'X)) (define y (var-term 'Y)) (define z (var-term 'Z))
  (define p
    (program
     (list (rule 'base (literal 'path (list x y) #t)
                 (list (literal 'edge (list x y) #t)))
           (rule 'step (literal 'path (list x z) #t)
                 (list (literal 'path (list x y) #t) (literal 'edge (list y z) #t)))
           (rule 'safe (literal 'safe_reach (list x y) #t)
                 (list (literal 'path (list x y) #t) (literal 'blocked (list x) #f))))
     (list (fact 'edge #(a b)) (fact 'edge #(b c)) (fact 'blocked #(b)))))
  (define result (run-program-rehearsal p #:oracle? #t))
  (define actual
    (list->set (for/list ([f (in-list (evaluation-result-facts result))])
                 (cons (fact-predicate f) (fact-args f)))))
  (define expected
    (set '(edge . #(a b)) '(edge . #(b c)) '(blocked . #(b))
         '(path . #(a b)) '(path . #(b c)) '(path . #(a c))
         '(safe_reach . #(a b)) '(safe_reach . #(a c))))
  (unless (and (eq? (evaluation-result-status result) 'COMPLETE) (set=? actual expected))
    (error 'demo "Synthetic assertion failed"))
  result)
