#lang racket/base
(require json racket/list racket/port "ast.rkt")
(provide parse-program-json parse-program-string validate-program-shape
         evaluation-result->json-hash evaluation-result->json-string
         evaluation-result->json-frame)
(define (invalid) (error 'program-input "Invalid program"))
(define (atom? v) (or (symbol? v) (string? v) (exact-integer? v)))
(define (name? v) (and (symbol? v) (positive? (string-length (symbol->string v)))))
(define (validate-program-shape p)
  (unless (and (program? p) (list? (program-rules p)) (list? (program-edb-facts p))) (invalid))
  (define ids (make-hasheq))
  (define (term? t)
    (or (and (var-term? t) (name? (var-term-name t)))
        (and (const-term? t) (atom? (const-term-val t)))))
  (define (valid-literal? l)
    (and (literal? l) (name? (literal-predicate l))
         (boolean? (literal-positive? l)) (list? (literal-terms l))
         (andmap term? (literal-terms l))))
  (for ([f (in-list (program-edb-facts p))])
    (unless (and (fact? f) (name? (fact-predicate f)) (vector? (fact-args f))
                 (for/and ([a (in-vector (fact-args f))]) (atom? a))) (invalid)))
  (for ([r (in-list (program-rules p))])
    (unless (and (rule? r) (name? (rule-id r)) (not (eq? (rule-id r) 'edb))
                 (not (hash-has-key? ids (rule-id r))) (valid-literal? (rule-head r))
                 (list? (rule-body r)) (andmap valid-literal? (rule-body r))) (invalid))
    (hash-set! ids (rule-id r) #t))
  #t)
(define (object value allowed)
  (unless (and (hash? value) (for/and ([key (in-hash-keys value)]) (memq key allowed))) (invalid))
  value)
(define (json-name value)
  (unless (and (string? value) (positive? (string-length value))) (invalid))
  (string->symbol value))
(define (json-atom value)
  (cond [(string? value) (string->symbol value)] [(exact-integer? value) value] [else (invalid)]))
(define (parse-program-json js)
  (object js '(edb_facts rules))
  (define facts (hash-ref js 'edb_facts null))
  (define rules (hash-ref js 'rules null))
  (unless (and (list? facts) (list? rules)) (invalid))
  (define (parse-term t)
    (object t '(var const))
    (unless (= (hash-count t) 1) (invalid))
    (if (hash-has-key? t 'var) (var-term (json-name (hash-ref t 'var)))
        (const-term (json-atom (hash-ref t 'const)))))
  (define (parse-literal l)
    (object l '(predicate terms positive))
    (define terms (hash-ref l 'terms null))
    (define positive (hash-ref l 'positive #t))
    (unless (and (list? terms) (boolean? positive)) (invalid))
    (literal (json-name (hash-ref l 'predicate)) (map parse-term terms) positive))
  (define p
    (program
     (for/list ([r (in-list rules)])
       (object r '(id head body))
       (define body (hash-ref r 'body null))
       (unless (list? body) (invalid))
       (rule (json-name (hash-ref r 'id)) (parse-literal (hash-ref r 'head)) (map parse-literal body)))
     (for/list ([f (in-list facts)])
       (object f '(predicate args))
       (define args (hash-ref f 'args null))
       (unless (list? args) (invalid))
       (fact (json-name (hash-ref f 'predicate)) (list->vector (map json-atom args))))))
  (validate-program-shape p)
  p)
(define (parse-program-string str)
  (unless (and (string? str) (<= (bytes-length (string->bytes/utf-8 str)) MAX-INPUT-BYTES)) (invalid))
  (parse-program-json (string->jsexpr str)))
;; Converts evaluation-result into a JSON-compatible jsexpr hash
(define (raw-json-hash res)
  (define spellings (make-hasheq))
  (define (spelling value) (hash-ref! spellings value (lambda () (symbol->string value))))
  (define facts (evaluation-result-facts res))
  (define proofs (evaluation-result-proofs res))

  ;; Serialize facts list
  (define serialized-facts
    (for/list ([f (in-list facts)])
      (define p (fact-predicate f))
      (define args (vector->list (fact-args f)))
      (define node (hash-ref proofs (cons p (fact-args f)) #f))
      (define ord (if node (proof-node-ordinal node) -1))
      (hash 'predicate (spelling p)
            'args (for/list ([a (in-list args)])
                    (if (symbol? a) (spelling a) a))
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
          (hash 'predicate (spelling np)
                'tuple (for/list ([a (in-list nt)])
                         (if (symbol? a) (spelling a) a))
                'stratum nstr)))

      (hash 'ordinal (proof-node-ordinal node)
            'fact (hash 'predicate (spelling p)
                        'args (for/list ([a (in-list args)])
                                (if (symbol? a) (spelling a) a)))
            'rule_id (spelling rid)
            'premises premises
            'negative_evidence serialized-neg-ev)))

  (hash 'status (spelling (evaluation-result-status res))
        'message (evaluation-result-message res)
        'facts_count (length facts)
        'binding_examinations (evaluation-result-binding-examinations res)
        'facts serialized-facts
        'proofs serialized-proofs
        'provenance (hash 'engine "Racket 8.7"
                          'algorithm "Stratified Indexed Semi-Naive Datalog"
                          'strata_count (length (evaluation-result-strata res)))))


;; The private byte port checks before every append, including the final newline.
;; The object representation is bounded by relation/proof cardinalities; this is
;; not a bound on Racket's parser, string conversion or allocator RSS.
(struct output-limit () #:transparent)
(define (encode-frame res maximum)
  (define destination (open-output-bytes))
  (define used 0)
  (define bounded
    (make-output-port
     'bounded-result always-evt
     (lambda (buffer start end _nonblocking? _breakable?)
       (define count (- end start))
       (when (> (+ used count) maximum) (raise (output-limit)))
       (write-bytes buffer destination start end)
       (set! used (+ used count))
       count)
     void))
  (write-json (raw-json-hash res) bounded)
  (write-byte 10 bounded)
  (flush-output bounded)
  (get-output-bytes destination))
(define (evaluation-result->json-frame res #:max-bytes [maximum MAX-OUTPUT-BYTES])
  (unless (and (exact-integer? maximum) (<= 512 maximum MAX-OUTPUT-BYTES))
    (raise-argument-error 'evaluation-result->json-frame "integer byte limit in 512..8388608" maximum))
  (with-handlers ([output-limit?
                  (lambda (_)
                    (define fallback
                      (evaluation-result 'UNKNOWN_BUDGET "Output budget exceeded" null null (hash) 0 0))
                    (values fallback (encode-frame fallback maximum)))])
    (values res (encode-frame res maximum))))
(define (evaluation-result->json-string res #:max-bytes [maximum MAX-OUTPUT-BYTES])
  (define-values (_admitted frame) (evaluation-result->json-frame res #:max-bytes maximum))
  ;; Historical API returns the JSON value without the CLI framing newline.
  (bytes->string/utf-8 (subbytes frame 0 (sub1 (bytes-length frame)))))
(define (evaluation-result->json-hash res)
  (string->jsexpr (evaluation-result->json-string res)))
