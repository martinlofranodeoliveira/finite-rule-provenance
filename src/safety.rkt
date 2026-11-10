#lang racket/base

(require racket/set
         "ast.rkt")

(provide validate-program-safety
         extract-predicates
         extract-constants)

;; Extracts all distinct predicates with their arities.
;; Returns a hash of predicate -> arity, or raises an error if arity is inconsistent.
(define (extract-predicates prog)
  (define pred-arities (make-hash))

  (define (record-pred! p arity ctx)
    (when (> arity MAX-ARITY)
      (error 'validate-program-safety
             "Predicate ~a in ~a exceeds maximum arity ~a (got ~a)"
             p ctx MAX-ARITY arity))
    (define existing (hash-ref pred-arities p #f))
    (if existing
        (unless (= existing arity)
          (error 'validate-program-safety
                 "Predicate ~a has inconsistent arities (~a and ~a) in ~a"
                 p existing arity ctx))
        (hash-set! pred-arities p arity)))

  ;; From EDB facts
  (for ([f (in-list (program-edb-facts prog))])
    (record-pred! (fact-predicate f) (vector-length (fact-args f)) "EDB facts"))

  ;; From rules
  (for ([r (in-list (program-rules prog))])
    (define h (rule-head r))
    (record-pred! (literal-predicate h) (length (literal-terms h)) (format "rule ~a head" (rule-id r)))
    (for ([lit (in-list (rule-body r))])
      (record-pred! (literal-predicate lit) (length (literal-terms lit)) (format "rule ~a body" (rule-id r)))))

  (when (> (hash-count pred-arities) MAX-PREDICATES)
    (error 'validate-program-safety
           "Program defines ~a predicates, exceeding maximum limit of ~a"
           (hash-count pred-arities) MAX-PREDICATES))

  pred-arities)

;; Extracts all distinct constants from facts and rules.
(define (extract-constants prog)
  (define consts (mutable-set))

  ;; From facts
  (for ([f (in-list (program-edb-facts prog))])
    (for ([arg (in-vector (fact-args f))])
      (set-add! consts arg)))

  ;; From rules
  (for ([r (in-list (program-rules prog))])
    (for ([t (in-list (literal-terms (rule-head r)))])
      (when (const-term? t) (set-add! consts (const-term-val t))))
    (for ([lit (in-list (rule-body r))])
      (for ([t (in-list (literal-terms lit))])
        (when (const-term? t) (set-add! consts (const-term-val t))))))

  (when (> (set-count consts) MAX-CONSTANTS)
    (error 'validate-program-safety
           "Program references ~a distinct constants, exceeding maximum limit of ~a"
           (set-count consts) MAX-CONSTANTS))

  consts)

;; Validates rule safety, arities, variable bounds, and fact counts.
;; Returns #t or raises error with 'INVALID_PROGRAM reason.
(define (validate-program-safety prog)
  ;; 1. Fact count bound
  (define facts (program-edb-facts prog))
  (when (> (length facts) MAX-INPUT-FACTS)
    (error 'validate-program-safety
           "Input facts count (~a) exceeds limit of ~a"
           (length facts) MAX-INPUT-FACTS))

  ;; 2. Rule count bound
  (define rules (program-rules prog))
  (when (> (length rules) MAX-RULES)
    (error 'validate-program-safety
           "Rule count (~a) exceeds limit of ~a"
           (length rules) MAX-RULES))

  ;; 3. Predicates & Constants bounds
  (extract-predicates prog)
  (extract-constants prog)

  ;; 4. Validate each rule
  (for ([r (in-list rules)])
    (define rid (rule-id r))
    (define head (rule-head r))
    (define body (rule-body r))

    (unless (literal-positive? head)
      (error 'validate-program-safety
             "Rule ~a: Head must be a positive literal" rid))

    (when (null? body)
      (error 'validate-program-safety
             "Rule ~a: Body must contain at least one literal" rid))

    (when (> (length body) MAX-LITERALS-PER-RULE)
      (error 'validate-program-safety
             "Rule ~a: Body has ~a literals, exceeding limit of ~a"
             rid (length body) MAX-LITERALS-PER-RULE))

    ;; Collect positive variables and all rule variables
    (define positive-vars (mutable-set))
    (define all-vars (mutable-set))

    (for ([lit (in-list body)])
      (define is-pos (literal-positive? lit))
      (for ([t (in-list (literal-terms lit))])
        (when (var-term? t)
          (define v (var-term-name t))
          (set-add! all-vars v)
          (when is-pos
            (set-add! positive-vars v)))))

    (for ([t (in-list (literal-terms head))])
      (when (var-term? t)
        (set-add! all-vars (var-term-name t))))

    (when (> (set-count all-vars) MAX-VARS-PER-RULE)
      (error 'validate-program-safety
             "Rule ~a: Contains ~a variables, exceeding limit of ~a"
             rid (set-count all-vars) MAX-VARS-PER-RULE))

    ;; Range restriction: Every head variable must appear in a positive body literal
    (for ([t (in-list (literal-terms head))])
      (when (var-term? t)
        (define v (var-term-name t))
        (unless (set-member? positive-vars v)
          (error 'validate-program-safety
                 "Rule ~a: Head variable ~a does not appear in any positive body literal (unsafe rule)"
                 rid v))))

    ;; Range restriction: Every negative body variable must appear in a positive body literal
    (for ([lit (in-list body)])
      (unless (literal-positive? lit)
        (for ([t (in-list (literal-terms lit))])
          (when (var-term? t)
            (define v (var-term-name t))
            (unless (set-member? positive-vars v)
              (error 'validate-program-safety
                     "Rule ~a: Negative literal variable ~a in ~a does not appear in any positive body literal (unsafe negation)"
                     rid v (literal-predicate lit))))))))

  #t)
