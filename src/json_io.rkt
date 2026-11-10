#lang racket/base

(require json
         "ast.rkt")

(provide parse-program-json
         parse-program-string
         evaluation-result->json-hash
         evaluation-result->json-string)

;; Parses a JSON jsexpr into an AST program
(define (parse-program-json js)
  (define edb-raw (hash-ref js 'edb_facts '()))
  (define rules-raw (hash-ref js 'rules '()))

  ;; Parse EDB facts
  (define edb-facts
    (for/list ([f-raw (in-list edb-raw)])
      (define p (string->symbol (hash-ref f-raw 'predicate)))
      (define args
        (list->vector
         (for/list ([arg (in-list (hash-ref f-raw 'args '()))])
           (cond
             [(string? arg) (string->symbol arg)]
             [(symbol? arg) arg]
             [(integer? arg) arg]
             [else (string->symbol (format "~a" arg))]))))
      (fact p args)))

  ;; Helper to parse a term
  (define (parse-term t-raw)
    (cond
      [(hash-has-key? t-raw 'var)
       (var-term (string->symbol (format "~a" (hash-ref t-raw 'var))))]
      [(hash-has-key? t-raw 'const)
       (define val (hash-ref t-raw 'const))
       (const-term (if (string? val) (string->symbol val) val))]
      [else
       (error 'parse-program-json "Malformed term: ~a" t-raw)]))

  ;; Helper to parse a literal
  (define (parse-literal lit-raw)
    (define p (string->symbol (hash-ref lit-raw 'predicate)))
    (define terms
      (for/list ([t-raw (in-list (hash-ref lit-raw 'terms '()))])
        (parse-term t-raw)))
    (define is-pos (hash-ref lit-raw 'positive #t))
    (literal p terms is-pos))

  ;; Parse Rules
  (define rules
    (for/list ([r-raw (in-list rules-raw)])
      (define rid (string->symbol (format "~a" (hash-ref r-raw 'id))))
      (define head (parse-literal (hash-ref r-raw 'head)))
      (define body
        (for/list ([lit-raw (in-list (hash-ref r-raw 'body '()))])
          (parse-literal lit-raw)))
      (rule rid head body)))

  (program rules edb-facts))

;; Parses a raw JSON string into a program
(define (parse-program-string str)
  (when (> (string-length str) MAX-INPUT-BYTES)
    (error 'parse-program-string "Input JSON exceeds maximum limit of ~a bytes" MAX-INPUT-BYTES))
  (define js (string->jsexpr str))
  (parse-program-json js))

;; Converts evaluation-result into a JSON-compatible jsexpr hash
(define (evaluation-result->json-hash res)
  (define facts (evaluation-result-facts res))
  (define proofs (evaluation-result-proofs res))

  ;; Serialize facts list
  (define serialized-facts
    (for/list ([f (in-list facts)])
      (define p (fact-predicate f))
      (define args (vector->list (fact-args f)))
      (define node (hash-ref proofs (cons p (fact-args f)) #f))
      (define ord (if node (proof-node-ordinal node) -1))
      (hash 'predicate (symbol->string p)
            'args (for/list ([a (in-list args)])
                    (if (symbol? a) (symbol->string a) a))
            'ordinal ord)))

  ;; Serialize proofs list
  ;; Sort proofs by derivation ordinal ascending
  (define proof-list (hash-values proofs))
  (define sorted-proofs
    (sort proof-list (lambda (a b) (< (proof-node-ordinal a) (proof-node-ordinal b)))))

  (define serialized-proofs
    (for/list ([node (in-list sorted-proofs)])
      (define f (proof-node-fact node))
      (define p (fact-predicate f))
      (define args (vector->list (fact-args f)))
      (define rid (proof-node-rule-id node))
      (define premises (proof-node-premises node))
      (define neg-ev (proof-node-negative-evidence node))

      (define serialized-neg-ev
        (for/list ([ev (in-list neg-ev)])
          (define np (hash-ref ev 'predicate))
          (define nt (vector->list (hash-ref ev 'tuple)))
          (define nstr (hash-ref ev 'stratum))
          (hash 'predicate (symbol->string np)
                'tuple (for/list ([a (in-list nt)])
                         (if (symbol? a) (symbol->string a) a))
                'stratum nstr)))

      (hash 'ordinal (proof-node-ordinal node)
            'fact (hash 'predicate (symbol->string p)
                        'args (for/list ([a (in-list args)])
                                (if (symbol? a) (symbol->string a) a)))
            'rule_id (symbol->string rid)
            'premises premises
            'negative_evidence serialized-neg-ev)))

  (hash 'status (symbol->string (evaluation-result-status res))
        'message (evaluation-result-message res)
        'facts_count (length facts)
        'binding_examinations (evaluation-result-binding-examinations res)
        'facts serialized-facts
        'proofs serialized-proofs
        'provenance (hash 'engine "Racket 8.7"
                          'algorithm "Stratified Indexed Semi-Naive Datalog"
                          'strata_count (length (evaluation-result-strata res)))))

;; Serializes evaluation-result to a formatted JSON string
(define (evaluation-result->json-string res)
  (jsexpr->string (evaluation-result->json-hash res)))
