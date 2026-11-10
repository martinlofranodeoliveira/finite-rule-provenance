#lang racket/base

(require db
         racket/set
         racket/list
         "ast.rkt"
         "strata.rkt"
         "safety.rkt")

(provide evaluate-sqlite-oracle
         compare-with-oracle)

;; Evaluates small Datalog programs (<= 8 constants) using SQLite relational joins
;; and set difference. User predicate and variable names NEVER become SQL identifiers.
(define (evaluate-sqlite-oracle prog)
  (define consts (extract-constants prog))
  (when (> (set-count consts) 8)
    (error 'evaluate-sqlite-oracle
           "SQLite oracle only supports fixtures with at most 8 constants (got ~a)"
           (set-count consts)))

  (define pred-arities (extract-predicates prog))
  (define strata (compute-stratification prog))

  ;; Constant conversion map: const -> string and string -> const
  (define consts-list (for/list ([c (in-set consts)]) c))
  (define const->str (make-hash))
  (define str->const (make-hash))
  (for ([c (in-list consts-list)])
    (define s (format "~a" c))
    (hash-set! const->str c s)
    (hash-set! str->const s c))

  ;; Map predicates to synthetic table identifiers: "rel_0", "rel_1", ...
  (define pred->table (make-hash))
  (define table->pred (make-hash))
  (for ([p (in-list (hash-keys pred-arities))] [idx (in-naturals)])
    (define tbl (format "rel_~a" idx))
    (hash-set! pred->table p tbl)
    (hash-set! table->pred tbl p))

  ;; Connect to in-memory SQLite database
  (define db (sqlite3-connect #:database 'memory))

  ;; Create synthetic tables
  (for ([(p tbl) (in-hash pred->table)])
    (define arity (hash-ref pred-arities p))
    (define col-defs
      (cond
        [(= arity 0) "dummy INTEGER PRIMARY KEY DEFAULT 1"]
        [else
         (define cols
           (for/list ([i (in-range arity)])
             (format "col_~a TEXT NOT NULL" i)))
         (define pk-cols
           (for/list ([i (in-range arity)])
             (format "col_~a" i)))
         (format "~a, PRIMARY KEY (~a)"
                 (string-join cols ", ")
                 (string-join pk-cols ", "))]))
    (query-exec db (format "CREATE TABLE ~a (~a)" tbl col-defs)))

  ;; Insert EDB facts using safe parameterized queries
  (for ([f (in-list (program-edb-facts prog))])
    (define tbl (hash-ref pred->table (fact-predicate f)))
    (define args (fact-args f))
    (define arity (vector-length args))
    (if (= arity 0)
        (query-exec db (format "INSERT OR IGNORE INTO ~a DEFAULT VALUES" tbl))
        (let ()
          (define placeholders (string-join (make-list arity "?") ", "))
          (define sql (format "INSERT OR IGNORE INTO ~a VALUES (~a)" tbl placeholders))
          (define str-args
            (for/list ([a (in-vector args)])
              (hash-ref const->str a (format "~a" a))))
          (apply query-exec db sql str-args))))

  ;; Evaluate stratum by stratum
  (for ([s-info (in-list strata)])
    (define s-rules (stratum-info-rules s-info))
    (when (not (null? s-rules))
      ;; Fixed point loop for current stratum
      (let loop ()
        (define total-inserted 0)
        (for ([r (in-list s-rules)])
          (define inserted (execute-sql-rule db r pred->table pred-arities const->str))
          (set! total-inserted (+ total-inserted inserted)))
        (when (> total-inserted 0)
          (loop)))))

  ;; Collect all derived and EDB facts from SQLite tables
  (define result-facts (mutable-set))
  (for ([(tbl p) (in-hash table->pred)])
    (define arity (hash-ref pred-arities p))
    (if (= arity 0)
        (let ([rows (query-rows db (format "SELECT count(*) FROM ~a" tbl))])
          (when (> (vector-ref (car rows) 0) 0)
            (set-add! result-facts (fact p #()))))
        (let ()
          (define col-names
            (string-join
             (for/list ([i (in-range arity)]) (format "col_~a" i))
             ", "))
          (define rows (query-rows db (format "SELECT ~a FROM ~a" col-names tbl)))
          (for ([row (in-list rows)])
            (define recovered-args
              (list->vector
               (for/list ([v (in-vector row)])
                 (hash-ref str->const v (string->symbol (format "~a" v))))))
            (set-add! result-facts (fact p recovered-args))))))

  (disconnect db)
  (for/set ([f (in-set result-facts)]) f))

;; Executes a single Datalog rule as a parameterized SQL query
;; Returns number of new rows inserted
(define (execute-sql-rule db r pred->table pred-arities const->str)
  (define head (rule-head r))
  (define body (rule-body r))
  (define head-p (literal-predicate head))
  (define head-tbl (hash-ref pred->table head-p))
  (define head-terms (literal-terms head))
  (define head-arity (length head-terms))

  ;; Collect positive and negative body literals
  (define pos-lits (for/list ([lit (in-list body)] #:when (literal-positive? lit)) lit))
  (define neg-lits (for/list ([lit (in-list body)] #:when (not (literal-positive? lit))) lit))

  ;; Synthetic alias map for each positive literal: lit_0, lit_1, ...
  ;; Map variable -> first occurrence (alias, col_idx)
  (define var->source (make-hash))
  (define join-clauses '())
  (define from-parts '())
  (define const-wheres '())

  (for ([lit (in-list pos-lits)] [lit-idx (in-naturals)])
    (define alias (format "t_~a" lit-idx))
    (define tbl (hash-ref pred->table (literal-predicate lit)))
    (set! from-parts (cons (format "~a AS ~a" tbl alias) from-parts))

    (for ([t (in-list (literal-terms lit))] [col-idx (in-naturals)])
      (define col-ref (format "~a.col_~a" alias col-idx))
      (if (const-term? t)
          (set! const-wheres (cons (format "~a = '~a'" col-ref (hash-ref const->str (const-term-val t) (const-term-val t))) const-wheres))
          (let ([v (var-term-name t)])
            (if (hash-has-key? var->source v)
                (set! join-clauses (cons (format "~a = ~a" col-ref (hash-ref var->source v)) join-clauses))
                (hash-set! var->source v col-ref))))))

  ;; Build SELECT expressions for head
  (define select-exprs
    (if (= head-arity 0)
        "1"
        (string-join
         (for/list ([t (in-list head-terms)])
           (if (const-term? t)
               (format "'~a'" (hash-ref const->str (const-term-val t) (const-term-val t)))
               (hash-ref var->source (var-term-name t))))
         ", ")))

  ;; Positive query FROM and WHERE
  (define from-str (string-join (reverse from-parts) ", "))
  (define all-wheres (append (reverse const-wheres) (reverse join-clauses)))

  ;; Negative literals become "NOT EXISTS (SELECT 1 FROM rel_neg WHERE ...)"
  (for ([lit (in-list neg-lits)] [neg-idx (in-naturals)])
    (define neg-tbl (hash-ref pred->table (literal-predicate lit)))
    (define neg-alias (format "neg_~a" neg-idx))
    (define neg-conds '())
    (for ([t (in-list (literal-terms lit))] [col-idx (in-naturals)])
      (define col-ref (format "~a.col_~a" neg-alias col-idx))
      (if (const-term? t)
          (set! neg-conds (cons (format "~a = '~a'" col-ref (hash-ref const->str (const-term-val t) (const-term-val t))) neg-conds))
          (let ([v (var-term-name t)])
            (set! neg-conds (cons (format "~a = ~a" col-ref (hash-ref var->source v)) neg-conds)))))
    (define neg-where-str
      (if (null? neg-conds)
          "1=1"
          (string-join (reverse neg-conds) " AND ")))
    (set! all-wheres
          (cons (format "NOT EXISTS (SELECT 1 FROM ~a AS ~a WHERE ~a)"
                        neg-tbl neg-alias neg-where-str)
                all-wheres)))

  (define where-str
    (if (null? all-wheres)
        ""
        (format " WHERE ~a" (string-join all-wheres " AND "))))

  ;; Target columns
  (define target-cols
    (if (= head-arity 0)
        ""
        (format " (~a)"
                (string-join
                 (for/list ([i (in-range head-arity)]) (format "col_~a" i))
                 ", "))))

  (define sql
    (format "INSERT OR IGNORE INTO ~a~a SELECT DISTINCT ~a FROM ~a~a"
            head-tbl target-cols select-exprs from-str where-str))

  ;; Count rows before and after to get actual insertion count
  (define count-sql (format "SELECT count(*) FROM ~a" head-tbl))
  (define before-count (vector-ref (car (query-rows db count-sql)) 0))
  (query-exec db sql)
  (define after-count (vector-ref (car (query-rows db count-sql)) 0))

  (- after-count before-count))

;; Helper to string-join
(define (string-join lst sep)
  (if (null? lst)
      ""
      (let loop ([curr (car lst)] [rest (cdr lst)])
        (if (null? rest)
            (format "~a" curr)
            (loop (format "~a~a~a" curr sep (car rest)) (cdr rest))))))

;; Compares facts from our semi-naive evaluator with SQLite oracle
;; Returns (values #t message) or (values #f error-message)
(define (compare-with-oracle datalog-facts sqlite-facts)
  (define datalog-set (for/set ([f (in-list datalog-facts)]) f))
  (define sqlite-set (for/set ([f (in-set sqlite-facts)]) f))
  (define missing-in-datalog (set-subtract sqlite-set datalog-set))
  (define missing-in-sqlite (set-subtract datalog-set sqlite-set))

  (if (and (set-empty? missing-in-datalog) (set-empty? missing-in-sqlite))
      (values #t (format "Oracle comparison passed: exactly ~a facts match" (set-count sqlite-set)))
      (values #f (format "Oracle discrepancy! Missing in Datalog: ~a; Extra in Datalog: ~a"
                         (set->list missing-in-datalog)
                         (set->list missing-in-sqlite)))))
