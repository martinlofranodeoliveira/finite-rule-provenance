#lang racket/base
(require file/unzip racket/file racket/list racket/path file/sha1)
(define archive (string->path (vector-ref (current-command-line-arguments) 0)))
(define source (string->path (vector-ref (current-command-line-arguments) 1)))
(define inspection (string->path "/work/artifacts/inspection"))
(make-directory* inspection)
(parameterize ([current-directory inspection]) (unzip archive))
(define (files root)
  (define (walk directory)
    (append*
     (for/list ([path (in-list (directory-list directory #:build? #t))])
       (define name (path->string (file-name-from-path path)))
       (cond [(link-exists? path) (error 'package "Unexpected symbolic link")]
             [(member name '(".git" ".github" ".gitignore" "dist" "compiled")) null]
             [(directory-exists? path) (walk path)]
             [else (list (find-relative-path root path))]))))
  (sort (walk root) string<? #:key path->string))
(define intended (files source))
(unless (equal? intended (files inspection)) (error 'package "Archive inventory differs from intended package source"))
(for ([relative (in-list intended)])
  (define a (build-path source relative)) (define b (build-path inspection relative))
  (unless (bytes=? (file->bytes a) (file->bytes b)) (error 'package "Packaged source content differs"))
  (define digest (call-with-input-file b sha256-bytes))
  (printf "~a  ~a\n" (bytes->hex-string digest) relative))
(displayln "PASS: exact archive source content; only .git metadata/workflow, dist and compiled output excluded")
