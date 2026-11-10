#lang racket/base

(require racket/set
         racket/list
         "ast.rkt"
         "safety.rkt"
         "strata.rkt")

(provide evaluate-program
         (struct-out budget-exceeded-exception))

(struct budget-exceeded-exception (metric limit value) #:transparent)

;; Raised when an execution budget limit is exceeded
(define (raise-budget-exceeded! metric limit value)
  (raise (budget-exceeded-exception metric limit value)))

;; Vector equality helper
(define (tuple-equal? t1 t2)
  (equal? t1 t2))

;; Evaluates a stratifiable Datalog program with indexed semi-naive evaluation
;; and deterministic derivation provenance.
(define (evaluate-program prog)
  ;; 1. Validate safety & Stratification
  (validate-program-safety prog)
  (define strata (compute-stratification prog))

  ;; State structures
  ;; Relations: pred (symbol) -> hash-set of tuple (vector)
  (define relations (make-hash))
  ;; Derivations: (cons pred tuple) -> proof-node
  (define proofs (make-hash))
  ;; Closed strata: stratum index -> hash-set of facts
  (define stratum-snapshots (make-hash))

  (define pred-arities (extract-predicates prog))
  (for ([p (in-list (hash-keys pred-arities))])
    (hash-set! relations p (mutable-set)))

  ;; Predicate -> stratum index map
  (define pred->stratum (make-hash))
  (for ([s-info (in-list strata)])
    (for ([p (in-list (stratum-info-predicates s-info))])
      (hash-set! pred->stratum p (stratum-info-index s-info))))

  ;; Budget counters
  (define total-facts 0)
  (define total-proof-edges 0)
  (define binding-examinations 0)
  (define current-ordinal 0)

  (define-syntax-rule (inc-examinations!)
    (begin
      (set! binding-examinations (+ binding-examinations 1))
      (when (> binding-examinations MAX-BINDING-EXAMINATIONS)
        (raise-budget-exceeded! 'binding-examinations MAX-BINDING-EXAMINATIONS binding-examinations))))

  ;; Helper to record an EDB fact
  (define (record-edb-fact! f)
    (define p (fact-predicate f))
    (define args (fact-args f))
    (define rel (hash-ref relations p))
    (unless (set-member? rel args)
      (set-add! rel args)
      (set! total-facts (+ total-facts 1))
      (when (> total-facts MAX-MATERIALIZED-FACTS)
        (raise-budget-exceeded! 'materialized-facts MAX-MATERIALIZED-FACTS total-facts))
      (define node (proof-node f current-ordinal 'edb '() '()))
      (hash-set! proofs (cons p args) node)
      (set! current-ordinal (+ current-ordinal 1))))

  ;; Ingest EDB facts
  (for ([f (in-list (program-edb-facts prog))])
    (record-edb-fact! f))

  ;; Evaluate each stratum in order
  (for ([s-info (in-list strata)])
    (define s-idx (stratum-info-index s-info))
    (define s-rules (stratum-info-rules s-info))
    (define s-idb-preds (list->set (stratum-info-idb-predicates s-info)))

    ;; Separate rules into:
    ;; - Base rules (no body literals in s-idb-preds)
    ;; - Recursive rules (at least one body literal in s-idb-preds)
    (define base-rules '())
    (define rec-rules '())

    (for ([r (in-list s-rules)])
      (define is-rec
        (for/or ([lit (in-list (rule-body r))])
          (and (literal-positive? lit)
               (set-member? s-idb-preds (literal-predicate lit)))))
      (if is-rec
          (set! rec-rules (cons r rec-rules))
          (set! base-rules (cons r base-rules))))

    ;; Delta relations for semi-naive evaluation: pred -> mutable-set of tuple
    (define delta (make-hash))
    (for ([p (in-set s-idb-preds)])
      (hash-set! delta p (mutable-set)))

    ;; Helper: derives a fact from a successful rule match
    ;; Returns #t if fact was newly added, #f if duplicate
    (define (derive-fact! rid head-lit env pos-premises neg-evidence)
      (define head-p (literal-predicate head-lit))
      (define head-terms (literal-terms head-lit))
      (define head-args
        (list->vector
         (for/list ([t (in-list head-terms)])
           (if (const-term? t)
               (const-term-val t)
               (hash-ref env (var-term-name t))))))

      (define rel (hash-ref relations head-p))
      (if (set-member? rel head-args)
          #f ;; Already derived
          (let ()
            (set-add! rel head-args)
            (set! total-facts (+ total-facts 1))
            (when (> total-facts MAX-MATERIALIZED-FACTS)
              (raise-budget-exceeded! 'materialized-facts MAX-MATERIALIZED-FACTS total-facts))

            ;; Track proof edges
            (set! total-proof-edges (+ total-proof-edges (length pos-premises)))
            (when (> total-proof-edges MAX-PROVENANCE-EDGES)
              (raise-budget-exceeded! 'provenance-edges MAX-PROVENANCE-EDGES total-proof-edges))

            (define f (fact head-p head-args))
            (define node (proof-node f current-ordinal rid pos-premises neg-evidence))
            (hash-set! proofs (cons head-p head-args) node)
            (set! current-ordinal (+ current-ordinal 1))

            ;; If head predicate is in current stratum IDB, add to delta
            (when (set-member? s-idb-preds head-p)
              (set-add! (hash-ref delta head-p) head-args))
            #t)))

    ;; Generic literal matcher supporting regular and delta sources
    ;; body: list of literal
    ;; pos-sources: list of (pred -> set of tuple) matching the positive body literals
    (define (evaluate-rule-match r pos-sources)
      (define rid (rule-id r))
      (define head (rule-head r))
      (define body (rule-body r))

      ;; Separate body into positive and negative literals
      (define pos-lits '())
      (define neg-lits '())
      (for ([lit (in-list body)])
        (if (literal-positive? lit)
            (set! pos-lits (cons lit pos-lits))
            (set! neg-lits (cons lit neg-lits))))
      (set! pos-lits (reverse pos-lits))
      (set! neg-lits (reverse neg-lits))

      ;; Match positive literals recursively
      (define (match-pos lits sources env premises)
        (if (null? lits)
            ;; Positive literals matched; now verify negative literals
            (match-neg neg-lits env premises '())
            (let ([lit (car lits)]
                  [rest-lits (cdr lits)]
                  [src (car sources)]
                  [rest-sources (cdr sources)])
              (define p (literal-predicate lit))
              (define terms (literal-terms lit))
              (define tuples (hash-ref src p (set)))

              (for ([tup (in-set tuples)])
                (inc-examinations!)
                ;; Attempt to unify tuple with terms under current env
                (define new-env (unify-tuple-with-terms terms tup env))
                (when new-env
                  ;; Find derivation ordinal for this premise
                  (define premise-node (hash-ref proofs (cons p tup) #f))
                  (define premise-ord
                    (if premise-node
                        (proof-node-ordinal premise-node)
                        0))
                  (match-pos rest-lits rest-sources new-env (cons premise-ord premises)))))))

      ;; Match negative literals
      (define (match-neg lits env premises neg-evidence)
        (if (null? lits)
            ;; All literals satisfied! Derive head fact.
            (derive-fact! rid head env (reverse premises) (reverse neg-evidence))
            (let ([lit (car lits)]
                  [rest-lits (cdr lits)])
              (define p (literal-predicate lit))
              (define terms (literal-terms lit))
              ;; Evaluate ground tuple for negative literal
              (define ground-tuple
                (list->vector
                 (for/list ([t (in-list terms)])
                   (if (const-term? t)
                       (const-term-val t)
                       (hash-ref env (var-term-name t))))))

              (inc-examinations!)
              (define lower-rel (hash-ref relations p))
              (if (set-member? lower-rel ground-tuple)
                  ;; Fact exists -> negation fails!
                  #f
                  ;; Fact does not exist -> negation holds! Record absence evidence
                  (let ([evidence (hash 'predicate p
                                        'tuple ground-tuple
                                        'stratum (hash-ref pred->stratum p))])
                    (match-neg rest-lits env premises (cons evidence neg-evidence)))))))

      (match-pos pos-lits pos-sources (hash) '()))

    ;; Helper: unifies tuple with literal terms under env
    (define (unify-tuple-with-terms terms tup env)
      (define len (vector-length tup))
      (let loop ([i 0] [curr-env env])
        (if (= i len)
            curr-env
            (let ([term (list-ref terms i)]
                  [val (vector-ref tup i)])
              (if (const-term? term)
                  (if (equal? (const-term-val term) val)
                      (loop (+ i 1) curr-env)
                      #f)
                  ;; Variable term
                  (let ([var-name (var-term-name term)])
                    (cond
                      [(hash-has-key? curr-env var-name)
                       (if (equal? (hash-ref curr-env var-name) val)
                           (loop (+ i 1) curr-env)
                           #f)]
                      [else
                       (loop (+ i 1) (hash-set curr-env var-name val))])))))))

    ;; Step 1: Evaluate base rules
    (for ([r (in-list base-rules)])
      (define pos-count
        (count (lambda (l) (literal-positive? l)) (rule-body r)))
      (define full-sources (make-list pos-count relations))
      (evaluate-rule-match r full-sources))

    ;; Step 2: Semi-naive fixed-point loop for recursive rules
    (define (run-semi-naive-step)
      ;; Has delta produced any new facts?
      (define delta-has-facts
        (for/or ([p (in-set s-idb-preds)])
          (not (set-empty? (hash-ref delta p)))))

      (when (and delta-has-facts (not (null? rec-rules)))
        ;; Copy current delta as delta-in, and reset delta for next iteration
        (define delta-in (make-hash))
        (for ([p (in-set s-idb-preds)])
          (hash-set! delta-in p (set-copy (hash-ref delta p)))
          (set-clear! (hash-ref delta p)))

        ;; For each recursive rule, generate joins where at least one recursive positive literal
        ;; is sourced from delta-in!
        (for ([r (in-list rec-rules)])
          (define pos-lits
            (for/list ([lit (in-list (rule-body r))]
                       #:when (literal-positive? lit))
              lit))
          (define num-pos (length pos-lits))

          ;; For each position j that is a recursive literal in s-idb-preds:
          ;; literal 0..j-1 use relations (previous)
          ;; literal j uses delta-in
          ;; literal j+1..num-pos-1 use relations
          (for ([j (in-range num-pos)])
            (define lit-j (list-ref pos-lits j))
            (define p-j (literal-predicate lit-j))
            (when (set-member? s-idb-preds p-j)
              (define sources
                (for/list ([k (in-range num-pos)])
                  (if (= k j) delta-in relations)))
              (evaluate-rule-match r sources))))

        ;; Recurse to next semi-naive step
        (run-semi-naive-step)))

    (run-semi-naive-step)

    ;; Stratum fixed point reached! Snapshot closed stratum facts
    (define stratum-facts (mutable-set))
    (for ([p (in-list (stratum-info-predicates s-info))])
      (for ([tup (in-set (hash-ref relations p))])
        (set-add! stratum-facts (fact p tup))))
    (hash-set! stratum-snapshots s-idx stratum-facts))

  ;; Assemble final result
  (define all-facts '())
  (for ([(p tuples) (in-hash relations)])
    (for ([tup (in-set tuples)])
      (set! all-facts (cons (fact p tup) all-facts))))

  (evaluation-result
   'COMPLETE
   "Stratified evaluation reached fixed point across all strata"
   strata
   (reverse all-facts)
   proofs
   current-ordinal
   binding-examinations))
