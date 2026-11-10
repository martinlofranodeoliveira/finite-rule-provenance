#lang racket/base
(require racket/set "src/ast.rkt" "src/safety.rkt" "src/strata.rkt"
         "src/semi_naive.rkt" "src/replayer.rkt" "src/oracle.rkt" "src/json_io.rkt")
(provide (all-from-out "src/ast.rkt" "src/safety.rkt" "src/strata.rkt"
                       "src/semi_naive.rkt" "src/replayer.rkt" "src/oracle.rkt" "src/json_io.rkt")
         evaluate-datalog run-program-rehearsal)
(define (empty-result status message)
  (evaluation-result status message null null (hash) 0 0))
;; Invalid input and failure after admission are deliberately distinct.
(define (evaluate-datalog input #:max-output-bytes [maximum MAX-OUTPUT-BYTES])
  (unless (and (exact-integer? maximum) (<= 512 maximum MAX-OUTPUT-BYTES))
    (raise-argument-error 'evaluate-datalog "integer output budget in 512..8388608" maximum))
  (define admitted
    (with-handlers ([exn:fail? (lambda (_) #f)])
      (define prog (if (string? input) (parse-program-string input) input))
      (validate-program-shape prog)
      (validate-program-safety prog)
      (compute-stratification prog)
      prog))
  (if (not admitted)
      (empty-result 'INVALID_PROGRAM "Invalid program")
      (with-handlers ([budget-exceeded-exception?
                      (lambda (_) (empty-result 'UNKNOWN_BUDGET "Evaluation budget exceeded"))]
                     [exn:fail? (lambda (_) (empty-result 'INCOMPLETE "Computation failed"))])
        (define result (evaluate-program admitted))
        (define-values (bounded _frame)
          (evaluation-result->json-frame result #:max-bytes maximum))
        bounded)))
(define (run-program-rehearsal input #:oracle? [oracle? #t])
  (define result (evaluate-datalog input))
  (when (eq? (evaluation-result-status result) 'COMPLETE)
    (define prog (if (string? input) (parse-program-string input) input))
    (replay-all-proofs prog result)
    (when (and oracle? (<= (set-count (extract-constants prog)) 8))
      (define reference (evaluate-sqlite-oracle prog))
      (define-values (ok? _message)
        (compare-with-oracle (evaluation-result-facts result) reference))
      (unless ok? (error 'run-program-rehearsal "Independent oracle mismatch"))))
  result)
