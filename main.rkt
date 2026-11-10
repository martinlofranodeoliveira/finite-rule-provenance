#lang racket/base

(require racket/set
         "src/ast.rkt"
         "src/safety.rkt"
         "src/strata.rkt"
         "src/semi_naive.rkt"
         "src/replayer.rkt"
         "src/oracle.rkt"
         "src/json_io.rkt")

(provide
 (all-from-out "src/ast.rkt")
 (all-from-out "src/safety.rkt")
 (all-from-out "src/strata.rkt")
 (all-from-out "src/semi_naive.rkt")
 (all-from-out "src/replayer.rkt")
 (all-from-out "src/oracle.rkt")
 (all-from-out "src/json_io.rkt")
 evaluate-datalog
 run-program-rehearsal)

;; High-level safe evaluator
(define (evaluate-datalog prog-or-string)
  (define prog
    (if (string? prog-or-string)
        (parse-program-string prog-or-string)
        prog-or-string))

  (with-handlers ([budget-exceeded-exception?
                   (lambda (e)
                     (evaluation-result
                      'UNKNOWN_BUDGET
                      (format "Execution budget limit exceeded for ~a (limit ~a, observed ~a)"
                              (budget-exceeded-exception-metric e)
                              (budget-exceeded-exception-limit e)
                              (budget-exceeded-exception-value e))
                      '()
                      '()
                      (hash)
                      0
                      0))]
                  [exn:fail?
                   (lambda (e)
                     (evaluation-result
                      'INVALID_PROGRAM
                      (exn-message e)
                      '()
                      '()
                      (hash)
                      0
                      0))])
    (evaluate-program prog)))

;; Runs complete evaluation, proof replay, and optional SQLite oracle verification
(define (run-program-rehearsal prog-or-string #:oracle? [oracle? #t])
  (define prog
    (if (string? prog-or-string)
        (parse-program-string prog-or-string)
        prog-or-string))

  (define res (evaluate-datalog prog))
  (when (equal? (evaluation-result-status res) 'COMPLETE)
    ;; 1. Replay and verify all proofs
    (replay-all-proofs prog res)

    ;; 2. Optional SQLite oracle verification
    (when oracle?
      (define consts (extract-constants prog))
      (when (<= (length (for/list ([c (in-set consts)]) c)) 8)
        (define sqlite-facts (evaluate-sqlite-oracle prog))
        (define-values (ok? msg) (compare-with-oracle (evaluation-result-facts res) sqlite-facts))
        (unless ok?
          (error 'run-program-rehearsal "Oracle check failed: ~a" msg)))))

  res)
