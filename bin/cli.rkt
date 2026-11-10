#lang racket/base

(require racket/cmdline
         racket/file
         json
         "../main.rkt"
         "../tests/datalog_test.rkt")

(define (print-help)
  (displayln "Finite Rule Provenance CLI - Bounded Stratified Datalog")
  (displayln "")
  (displayln "Usage:")
  (displayln "  finite-rule-provenance demo [--assert] [--json]")
  (displayln "  finite-rule-provenance eval <file.json> [--json]")
  (displayln "  finite-rule-provenance replay <file.json>")
  (displayln "  finite-rule-provenance oracle <file.json>")
  (displayln "  finite-rule-provenance --help")
  (displayln ""))

(define (main args)
  (cond
    [(or (null? args) (member "--help" args) (member "-h" args))
     (print-help)
     (exit 0)]

    [(or (equal? (car args) "demo") (member "--assert" args))
     (define do-assert (member "--assert" args))
     (define as-json (member "--json" args))
     (if do-assert
         (let ()
           (define passed (run-all-datalog-tests (not as-json)))
           (when as-json
             (displayln (jsexpr->string (hash 'assert_suite_passed passed
                                              'status (if passed "PASS" "FAIL")))))
           (exit (if passed 0 1)))
         (let ()
           ;; Run a small demonstration program
           (define sample-json
             #<<JSON
{
  "edb_facts": [
    {"predicate": "edge", "args": ["a", "b"]},
    {"predicate": "edge", "args": ["b", "c"]},
    {"predicate": "blocked", "args": ["b"]}
  ],
  "rules": [
    {
      "id": "r_base",
      "head": {"predicate": "path", "terms": [{"var": "X"}, {"var": "Y"}]},
      "body": [
        {"predicate": "edge", "terms": [{"var": "X"}, {"var": "Y"}], "positive": true}
      ]
    },
    {
      "id": "r_rec",
      "head": {"predicate": "path", "terms": [{"var": "X"}, {"var": "Z"}]},
      "body": [
        {"predicate": "path", "terms": [{"var": "X"}, {"var": "Y"}], "positive": true},
        {"predicate": "edge", "terms": [{"var": "Y"}, {"var": "Z"}], "positive": true}
      ]
    },
    {
      "id": "r_safe",
      "head": {"predicate": "safe_reach", "terms": [{"var": "X"}, {"var": "Y"}]},
      "body": [
        {"predicate": "path", "terms": [{"var": "X"}, {"var": "Y"}], "positive": true},
        {"predicate": "blocked", "terms": [{"var": "X"}], "positive": false}
      ]
    }
  ]
}
JSON
)
           (define res (run-program-rehearsal sample-json #:oracle? #t))
           (displayln (evaluation-result->json-string res))
           (exit 0)))]

    [(equal? (car args) "eval")
     (define file-path (if (> (length args) 1) (cadr args) #f))
     (unless (and file-path (file-exists? file-path))
       (eprintf "Error: specified file does not exist: ~a\n" file-path)
       (exit 2))
     (define as-json (member "--json" args))
     (define content (file->string file-path))
     (define res (evaluate-datalog content))
     (if as-json
         (displayln (evaluation-result->json-string res))
         (begin
           (printf "Status: ~a\n" (evaluation-result-status res))
           (printf "Message: ~a\n" (evaluation-result-message res))
           (printf "Facts derived: ~a\n" (length (evaluation-result-facts res)))
           (printf "Candidate binding examinations: ~a\n" (evaluation-result-binding-examinations res))))
     (exit (if (equal? (evaluation-result-status res) 'COMPLETE) 0 1))]

    [(equal? (car args) "replay")
     (define file-path (if (> (length args) 1) (cadr args) #f))
     (unless (and file-path (file-exists? file-path))
       (eprintf "Error: specified file does not exist: ~a\n" file-path)
       (exit 2))
     (define content (file->string file-path))
     (define prog (parse-program-string content))
     (define res (evaluate-program prog))
     (with-handlers ([replayer-failure?
                      (lambda (rf)
                        (eprintf "Proof replay failed: ~a (~a)\n"
                                 (replayer-failure-message rf)
                                 (replayer-failure-type rf))
                        (exit 1))])
       (replay-all-proofs prog res)
       (displayln "Proof replay passed: all derivations verified.")
       (exit 0))]

    [(equal? (car args) "oracle")
     (define file-path (if (> (length args) 1) (cadr args) #f))
     (unless (and file-path (file-exists? file-path))
       (eprintf "Error: specified file does not exist: ~a\n" file-path)
       (exit 2))
     (define content (file->string file-path))
     (define prog (parse-program-string content))
     (define res (evaluate-program prog))
     (define sqlite-facts (evaluate-sqlite-oracle prog))
     (define-values (ok? msg) (compare-with-oracle (evaluation-result-facts res) sqlite-facts))
     (if ok?
         (begin
           (displayln msg)
           (exit 0))
         (begin
           (eprintf "Oracle failure: ~a\n" msg)
           (exit 1)))]

    [else
     (eprintf "Unknown command: ~a\n" (car args))
     (print-help)
     (exit 2)]))

(module+ main
  (main (vector->list (current-command-line-arguments))))
