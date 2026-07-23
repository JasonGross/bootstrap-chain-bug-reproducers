#!/usr/bin/env bash
# gash-exit-success-gate: gash 0.2.0's gash/compat.scm defines
# EXIT_SUCCESS/EXIT_FAILURE only under (if-guile-version-below (2 0 10) ...),
# assuming guile >= 2.0.10 binds them natively -- but guile only started
# binding them in 2.0.13.  Under guile 2.0.11 (which is exactly Guix's armhf
# %bootstrap-guile seed), gash-utils' rm/expr/test/grep crash with
# "Unbound variable: EXIT_SUCCESS".  config.status runs `rm -f`
# load-bearingly while generating Makefiles, so this kills any autoconf
# configure run over the boot gash tools.
# GREEN == rm crashes with the Unbound-variable error under guile 2.0.11 with
# stock gash, and works with the one-line gate widened to (2 2 0).
cd "$(dirname "$0")"
. ../common.sh

GUILE_URL=https://ftp.gnu.org/gnu/guile/guile-2.0.11.tar.xz
GUILE_SHA=aed0a4a6db4e310cbdfeb3613fa6f86fddc91ef624c1e3f8937a6304c69103e2
GASH_URL=https://download.savannah.gnu.org/releases/gash/gash-0.2.0.tar.gz
GASH_SHA=ee4158040800fd3cf5e02c32ee9a659a067c592f999b5c01e943da04cbf7a08e
GASHU_URL=https://download.savannah.gnu.org/releases/gash/gash-utils-0.2.0.tar.gz
GASHU_SHA=e6aae5a6f40fdf8c5f8730f66c3f8c3047bde00f8cd97595f5aad2444959d4a3

PREFIX="${GUILE_PREFIX:-$HOME/guile-2.0.11-prefix}"
GUILE="$PREFIX/bin/guile"

mkdir -p work

banner "STEP 1: guile 2.0.11 (the exact interpreter version of Guix's armhf %bootstrap-guile seed)"
if "$GUILE" --version 2>/dev/null | grep -q '2\.0\.11'; then
  loud "using cached guile 2.0.11 at $PREFIX"
else
  loud "building guile 2.0.11 from source (cached across CI runs)"
  fetch "$GUILE_URL" "$GUILE_SHA" work/guile-2.0.11.tar.xz
  rm -rf work/guile-2.0.11
  tar -xJf work/guile-2.0.11.tar.xz -C work
  ( cd work/guile-2.0.11 \
    && ./configure --prefix="$PREFIX" --disable-static MAKEINFO=true > configure.log 2>&1 \
    && make -j"$(nproc)" > make.log 2>&1 \
    && make install > install.log 2>&1 ) \
    || { tail -50 work/guile-2.0.11/configure.log work/guile-2.0.11/make.log 2>/dev/null; die "guile build failed"; }
fi
"$GUILE" --version | head -1

banner "STEP 2: guile 2.0.11 does NOT bind EXIT_SUCCESS (it first shipped in 2.0.13)"
"$GUILE" -c '(format #t "guile ~a: (defined? (quote EXIT_SUCCESS)) => ~a\n" (version) (defined? (quote EXIT_SUCCESS)))'
"$GUILE" -c '(exit (if (defined? (quote EXIT_SUCCESS)) 1 0))' \
  || die "sanity: this guile binds EXIT_SUCCESS natively; the gate hole would be masked"

banner "STEP 3: the accused gate in gash-0.2.0 gash/compat.scm"
fetch "$GASH_URL" "$GASH_SHA" work/gash-0.2.0.tar.gz
fetch "$GASHU_URL" "$GASHU_SHA" work/gash-utils-0.2.0.tar.gz
rm -rf work/gash-0.2.0 work/gash-utils-0.2.0 work/gash-fixed
tar -xzf work/gash-0.2.0.tar.gz -C work
tar -xzf work/gash-utils-0.2.0.tar.gz -C work
loud "gash-0.2.0/gash/compat.scm lines 55-62:"
sed -n '55,62p' work/gash-0.2.0/gash/compat.scm
loud "2.0.11 is NOT below 2.0.10, so the shim is skipped; but 2.0.11 doesn't"
loud "bind EXIT_SUCCESS natively either (only >= 2.0.13 does) -> hole."
loud "gash-utils-0.2.0's rm uses it (gash/commands/rm.scm):"
grep -n 'EXIT_SUCCESS' work/gash-utils-0.2.0/gash/commands/rm.scm

banner "STEP 4: BUG -- gash-utils rm -f under guile 2.0.11 with stock gash"
touch work/victim.txt
set +e
"$GUILE" --no-auto-compile -L work/gash-utils-0.2.0 -L work/gash-0.2.0 \
  -c '(apply (@@ (gash commands rm) main) (list "rm" "-f" "work/victim.txt"))' \
  > work/bug.out 2>&1
rc=$?
set -e
cat work/bug.out
loud "exit status: $rc"
[ $rc -ne 0 ] || die "bug did NOT reproduce: rm succeeded under stock gash"
grep -q 'Unbound variable: EXIT_SUCCESS' work/bug.out \
  || die "rm failed but not with the expected Unbound-variable crash"
[ -f work/victim.txt ] || die "unexpected: file was deleted despite the crash"
loud "BUG REPRODUCED: rm -f crashed with 'Unbound variable: EXIT_SUCCESS'"
loud "(and did not delete the file).  In a Guix armhf full-source bootstrap,"
loud "this is fatal: autoconf config.status runs 'rm -f' while generating"
loud "every Makefile."

banner "STEP 5: CONTROL -- same guile, gate widened (2 0 10) -> (2 2 0)"
cp -r work/gash-0.2.0 work/gash-fixed
sed -i 's/(if-guile-version-below (2 0 10)/(if-guile-version-below (2 2 0)/' work/gash-fixed/gash/compat.scm
loud "one-line fix applied:"
diff <(sed -n '55p' work/gash-0.2.0/gash/compat.scm) <(sed -n '55p' work/gash-fixed/gash/compat.scm) || true
"$GUILE" --no-auto-compile -L work/gash-utils-0.2.0 -L work/gash-fixed \
  -c '(apply (@@ (gash commands rm) main) (list "rm" "-f" "work/victim.txt"))'
rc=$?
loud "exit status: $rc"
[ ! -f work/victim.txt ] || die "control failed: file not deleted"
loud "CONTROL OK: with the widened gate, rm -f works and deletes the file."

banner "VERDICT"
loud "BUG REPRODUCED + one-line fix demonstrated.  Affected versions: any guile"
loud "in [2.0.10, 2.0.13) -- exactly the range the gate assumes is safe."
loud "Guix's armhf %bootstrap-guile static seed is guile 2.0.11, so the gash /"
loud "gash-utils boot packages plausibly break Guix's armhf full-source"
loud "bootstrap at the first autoconf'd package."
echo "PASS: gash-exit-success-gate reproduced"
