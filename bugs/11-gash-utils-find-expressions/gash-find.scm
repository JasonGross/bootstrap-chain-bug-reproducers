;; Stand-in for gash-utils' installed `find` script (scripts/template.in),
;; which is exactly:
;;
;;     (define (main args)
;;       (apply (@@ (gash commands @UTILITY@) main) args))
;;
;; invoked by guile with `-e main -L <moddir> -s <script>`.  Running the
;; module directly from the unpacked tarballs (both ship generated
;; config.scm) avoids a full autotools build without changing any behavior
;; under test.  argv[0] is forced to "find" so diagnostics read exactly as
;; they do from the installed command.
(use-modules (gash commands find))

(define (main args)
  (apply (@@ (gash commands find) main) "find" (cdr args)))
