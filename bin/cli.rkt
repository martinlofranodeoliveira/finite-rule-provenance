#lang racket/base
(require racket/set "../main.rkt" "../src/demo.rkt")
(provide main)
(define (empty status message) (evaluation-result status message null null (hash) 0 0))
(define (exit-code result)
  (case (evaluation-result-status result)
    [(COMPLETE) 0] [(UNKNOWN_BUDGET) 1] [(INVALID_PROGRAM) 2] [else 3]))
(define (emit result)
  (define-values (admitted frame) (evaluation-result->json-frame result))
  (write-bytes frame)
  (flush-output)
  (exit-code admitted))
(define (usage)
  (displayln "Finite Rule Provenance 0.1.0")
  (displayln "Usage: finite-rule-provenance demo [--assert] [--json]")
  (displayln "       finite-rule-provenance eval|replay|oracle [--json] < program.json")
  (displayln "       finite-rule-provenance --help"))
;; Diagnostics are best effort: a second stream failure must not escape the
;; incomplete result boundary or replace exit 3 with Racket's exception exit.
(define (incomplete _failure)
  (with-handlers ([exn:fail? (lambda (_) (void))])
    (when (file-stream-port? (current-error-port))
      (file-stream-buffer-mode (current-error-port) 'none))
    (eprintf "INCOMPLETE: input/output or computation failed\n")
    (flush-output (current-error-port)))
  3)
(define (main args)
  (with-handlers ([exn:fail? incomplete]
                  [replayer-failure? incomplete]
                  [budget-exceeded-exception?
                   (lambda (_)
                     (with-handlers ([exn:fail? incomplete])
                       (emit (empty 'UNKNOWN_BUDGET "Evaluation budget exceeded"))))])
    ;; The CLI owns stdout. Unbuffered file streams expose write errors while
    ;; this boundary is active, including help and the human-readable demo.
    (when (file-stream-port? (current-output-port))
      (file-stream-buffer-mode (current-output-port) 'none))
    (define status
      (cond
      [(or (null? args) (equal? args '("--help")) (equal? args '("-h"))) (usage) 0]
      [(equal? (car args) "demo")
       (define flags (cdr args))
       (if (and (<= (length flags) 2)
                (= (length flags) (set-count (list->set flags)))
                (andmap (lambda (flag) (member flag '("--assert" "--json"))) flags))
           (let ([result (demo-result)])
             (if (member "--json" flags) (emit result)
                 (begin (displayln "COMPLETE: synthetic reachability, safe negation, proof replay and SQLite comparison; 8 facts") 0)))
           (emit (empty 'INVALID_PROGRAM "Invalid arguments")))]
      [(and (member (car args) '("eval" "replay" "oracle"))
            (or (null? (cdr args)) (equal? (cdr args) '("--json"))))
       ;; read-bytes retains at most this explicit bound, before JSON parsing.
       ;; A stalled inherited stream is left to the outer container owner.
       (define input (read-bytes (add1 MAX-INPUT-BYTES)))
       (define text
         (and (bytes? input) (<= (bytes-length input) MAX-INPUT-BYTES)
              (with-handlers ([exn:fail? (lambda (_) #f)]) (bytes->string/utf-8 input #f))))
       (cond
         [(not text) (emit (empty 'INVALID_PROGRAM "Invalid input"))]
         [else
          (define result (evaluate-datalog text))
          (when (and (eq? (evaluation-result-status result) 'COMPLETE)
                     (not (equal? (car args) "eval")))
            (define p (parse-program-string text))
            (replay-all-proofs p result)
            (when (equal? (car args) "oracle")
              (if (> (set-count (extract-constants p)) 8)
                  (set! result (empty 'INVALID_PROGRAM "Oracle supports at most 8 constants"))
                  (let ()
                    (define reference (evaluate-sqlite-oracle p))
                    (define-values (ok? _message) (compare-with-oracle (evaluation-result-facts result) reference))
                    (unless ok? (error 'oracle "Independent oracle mismatch"))))))
          (emit result)])]
      [else (emit (empty 'INVALID_PROGRAM "Invalid arguments"))]))
    (flush-output)
    status))
(module+ main (exit (main (vector->list (current-command-line-arguments)))))
