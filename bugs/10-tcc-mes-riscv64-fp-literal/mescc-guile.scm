;; Minimal stand-in for GNU Mes' configured scripts/mescc.scm, so MesCC (the
;; unmodified Scheme compiler from the mes-0.27.1 tarball) can run under host
;; Guile 3.x.  It only performs the environment setup configure would bake in.
;; Run as:  guile --no-auto-compile -e main -s mescc-guile.scm <mescc args>
;; with GUILE_LOAD_PATH = <mes>/module:<nyacc>/module and MES_PREFIX = <mes>.
;; (NOTE: do NOT put <mes>/mes/module on GUILE_LOAD_PATH -- those are modules
;; for the mes interpreter itself, and its srfi-1 shadows Guile's.)
(setenv "%prefix" (or (getenv "MES_PREFIX") ""))
(setenv "%includedir" (string-append (getenv "MES_PREFIX") "/include"))
(setenv "%libdir" (string-append (getenv "MES_PREFIX") "/lib"))
(setenv "%version" "0.27.1")
(setenv "%arch" "riscv64")
(setenv "%kernel" "linux")
(setenv "%numbered_arch" "false")
(use-modules (mescc))
(define (main args) (mescc:main args))
