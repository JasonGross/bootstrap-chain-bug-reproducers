;; Decode an .xz file through the r6rs-compression XZ input port -- the same
;; entry point Bootar's `xz` script uses (scripts/xz.in calls
;; make-xz-input-port and drains it with get-bytevector-n!).
;;
;;   usage: guile -s decode.scm <in.xz> <out-file>
;;
;; Prints "decoded N bytes" on success; any decoder error propagates.
(use-modules (compression xz)
             (rnrs io ports)
             (rnrs bytevectors))

(define args (cdr (command-line)))
(define in (open-file-input-port (car args)))
(define out (open-file-output-port (cadr args) (file-options no-fail)))
(define p (make-xz-input-port in "xz" #t))
(define size (* 1024 1024))
(define bv (make-bytevector size))

(let lp ((total 0))
  (let ((n (get-bytevector-n! p bv 0 size)))
    (if (eof-object? n)
        (begin
          (close-port out)
          (format #t "decoded ~a bytes\n" total)
          (exit 0))
        (begin
          (put-bytevector out bv 0 n)
          (lp (+ total n))))))
