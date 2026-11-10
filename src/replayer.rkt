#lang racket/base

(require racket/set
         "ast.rkt"
         "strata.rkt")

(provide replay-all-proofs
         verify-single-proof
         (struct-out replayer-failure))

(struct replayer-failure (type message details) #:transparent)

;; Replays every proof in the evaluation result independently.
;; Returns #t if all proofs are verified, or raises a replayer-failure.
(define (replay-all-proofs prog eval-res)
  (define rules-by-id (make-hash))
  (for ([r (in-list (program-rules prog))])
    (hash-set! rules-by-id (rule-id r) r))

  (define edb-set (mutable-set))
  (for ([f (in-list (program-edb-facts prog))])
    (set-add! edb-set (cons (fact-predicate f) (fact-args f))))

  (define proofs (evaluation-result-proofs eval-res))

  ;; Invert proofs to lookup by ordinal: ordinal -> proof-node
  (define proof-by-ordinal (make-hash))
  (for ([(key node) (in-hash proofs)])
    (hash-set! proof-by-ordinal (proof-node-ordinal node) node))

  ;; Compute stratification for stratum checks
  (define strata (compute-stratification prog))
  (define pred->stratum (make-hash))
  (for ([s-info (in-list strata)])
    (for ([p (in-list (stratum-info-predicates s-info))])
      (hash-set! pred->stratum p (stratum-info-index s-info))))

  ;; Verify each proof
  (for ([(key node) (in-hash proofs)])
    (verify-single-proof node prog rules-by-id edb-set proof-by-ordinal pred->stratum proofs))

  #t)

;; Verifies a single proof node against the program and known derivations
(define (verify-single-proof node prog rules-by-id edb-set proof-by-ordinal pred->stratum all-proofs)
  (define f (proof-node-fact node))
  (define p (fact-predicate f))
  (define args (fact-args f))
  (define ord (proof-node-ordinal node))
  (define rid (proof-node-rule-id node))
  (define premises (proof-node-premises node))
  (define neg-evidence (proof-node-negative-evidence node))

  (cond
    ;; Case 1: EDB Fact
    [(equal? rid 'edb)
     (unless (set-member? edb-set (cons p args))
       (raise (replayer-failure
               'edb-fact-not-in-input
               (format "Fact ~a~a claimed as EDB is not in input facts" p args)
               (list p args))))
     (unless (null? premises)
       (raise (replayer-failure
               'edb-has-premises
               (format "EDB fact ~a~a must not have derivation premises" p args)
               premises)))
     (unless (null? neg-evidence)
       (raise (replayer-failure
               'edb-has-negation-evidence
               (format "EDB fact ~a~a must not have negation evidence" p args)
               neg-evidence)))
     #t]

    ;; Case 2: IDB Fact derived by Rule
    [else
     (define r (hash-ref rules-by-id rid #f))
     (unless r
       (raise (replayer-failure
               'unknown-rule-id
               (format "Derivation of ~a~a references non-existent rule ~a" p args rid)
               rid)))

     (define head (rule-head r))
     (define body (rule-body r))

     ;; Separate positive and negative body literals
     (define pos-lits
       (for/list ([lit (in-list body)] #:when (literal-positive? lit)) lit))
     (define neg-lits
       (for/list ([lit (in-list body)] #:when (not (literal-positive? lit))) lit))

     ;; Check premise count matches positive body literal count
     (unless (= (length premises) (length pos-lits))
       (raise (replayer-failure
               'premise-count-mismatch
               (format "Rule ~a requires ~a positive premises, got ~a"
                       rid (length pos-lits) (length premises))
               (list (length pos-lits) (length premises)))))

     ;; Check all premises have strictly earlier derivation ordinals
     (for ([prem-ord (in-list premises)])
       (unless (< prem-ord ord)
         (raise (replayer-failure
                 'non-earlier-derivation-ordinal
                 (format "Premise ordinal ~a is not strictly earlier than derived fact ordinal ~a in ~a"
                         prem-ord ord rid)
                 (list prem-ord ord)))))

     ;; Check each premise corresponds to a valid earlier fact
     (define premise-facts
       (for/list ([prem-ord (in-list premises)])
         (define prem-node (hash-ref proof-by-ordinal prem-ord #f))
         (unless prem-node
           (raise (replayer-failure
                   'missing-premise-node
                   (format "Premise ordinal ~a does not exist in proof store" prem-ord)
                   prem-ord)))
         (proof-node-fact prem-node)))

     ;; Unify head and positive premises with rule literals
     (define env (hash))

     ;; Unify each positive premise with its literal
     (for ([lit (in-list pos-lits)]
           [pf (in-list premise-facts)])
       (unless (equal? (literal-predicate lit) (fact-predicate pf))
         (raise (replayer-failure
                 'predicate-mismatch
                 (format "Rule ~a expects premise predicate ~a, got ~a"
                         rid (literal-predicate lit) (fact-predicate pf))
                 (list (literal-predicate lit) (fact-predicate pf)))))

       (set! env (unify-terms (literal-terms lit) (fact-args pf) env rid)))

     ;; Unify head with derived fact args
     (unless (equal? (literal-predicate head) p)
       (raise (replayer-failure
               'head-predicate-mismatch
               (format "Rule ~a head predicate ~a does not match derived fact ~a"
                       rid (literal-predicate head) p)
               (list (literal-predicate head) p))))

     (set! env (unify-terms (literal-terms head) args env rid))

     ;; Verify negative literals and negative evidence
     (define head-stratum (hash-ref pred->stratum p))

     (for ([lit (in-list neg-lits)])
       (define neg-p (literal-predicate lit))
       (define neg-terms (literal-terms lit))

       ;; Negative literal must belong to strictly lower stratum
       (define neg-stratum (hash-ref pred->stratum neg-p))
       (unless (< neg-stratum head-stratum)
         (raise (replayer-failure
                 'stratification-violation
                 (format "Negative literal ~a (stratum ~a) is not strictly lower than head ~a (stratum ~a)"
                         neg-p neg-stratum p head-stratum)
                 (list neg-p neg-stratum p head-stratum))))

       ;; Evaluate ground tuple under unified env
       (define expected-tuple
         (list->vector
          (for/list ([t (in-list neg-terms)])
            (if (const-term? t)
                (const-term-val t)
                (hash-ref env (var-term-name t))))))

       ;; Check that this tuple is NOT derived anywhere in all-proofs
       (when (hash-has-key? all-proofs (cons neg-p expected-tuple))
         (raise (replayer-failure
                 'negation-violation
                 (format "Fact ~a~a asserted absent by rule ~a actually exists in proof store!"
                         neg-p expected-tuple rid)
                 (list neg-p expected-tuple rid))))

       ;; Verify negative evidence record
       (define matching-evidence
         (for/or ([ev (in-list neg-evidence)])
           (and (equal? (hash-ref ev 'predicate #f) neg-p)
                (equal? (hash-ref ev 'tuple #f) expected-tuple)
                ev)))

       (unless matching-evidence
         (raise (replayer-failure
                 'missing-negative-evidence
                 (format "Missing negative absence evidence for ~a~a in rule ~a"
                         neg-p expected-tuple rid)
                 (list neg-p expected-tuple rid)))))

     #t]))

;; Unifies literal terms with a concrete fact tuple vector under an existing variable env
(define (unify-terms terms tup-vec env rid)
  (define len (vector-length tup-vec))
  (unless (= (length terms) len)
    (raise (replayer-failure
            'arity-mismatch
            (format "Rule ~a term count (~a) does not match fact arity (~a)"
                    rid (length terms) len)
            (list (length terms) len))))

  (let loop ([i 0] [curr-env env])
    (if (= i len)
        curr-env
        (let ([t (list-ref terms i)]
              [val (vector-ref tup-vec i)])
          (if (const-term? t)
              (if (equal? (const-term-val t) val)
                  (loop (+ i 1) curr-env)
                  (raise (replayer-failure
                          'constant-mismatch
                          (format "Rule ~a constant ~a does not match tuple value ~a"
                                  rid (const-term-val t) val)
                          (list (const-term-val t) val))))
              ;; Variable term
              (let ([v (var-term-name t)])
                (if (hash-has-key? curr-env v)
                    (if (equal? (hash-ref curr-env v) val)
                        (loop (+ i 1) curr-env)
                        (raise (replayer-failure
                                'variable-binding-conflict
                                (format "Rule ~a variable ~a already bound to ~a, conflicting with ~a"
                                        rid v (hash-ref curr-env v) val)
                                (list v (hash-ref curr-env v) val))))
                    (loop (+ i 1) (hash-set curr-env v val)))))))))
