#!/usr/bin/env bash
# mes-ldexp-stub: GNU Mes 0.27.1 lib/stub/ldexp.c is literally `return 0;`.
# GREEN == the bug reproduces (mes ldexp(1.0,10) == 0) AND the libm control
# gives the correct 1024.
cd "$(dirname "$0")"
. ../common.sh

mkdir -p work
fetch_mes work
MES=work/mes-0.27.1

banner "THE ACCUSED SOURCE: mes-0.27.1/lib/stub/ldexp.c (verbatim from the GNU mirror tarball)"
sha256sum "$MES/lib/stub/ldexp.c"
sed -n '20,40p' "$MES/lib/stub/ldexp.c"
grep -q 'return 0;' "$MES/lib/stub/ldexp.c" || die "expected 'return 0;' stub body not found"
loud "the function body ends in 'return 0;' -- every ldexp() result is 0.0"

banner "BUILD: compile the unmodified Mes source with host gcc + a tiny driver"
gcc -O2 -fno-builtin -I shim -c "$MES/lib/stub/ldexp.c" -o work/mes-ldexp.o
gcc -O2 -c shim-support.c -o work/shim-support.o
gcc -O2 -fno-builtin driver.c work/mes-ldexp.o work/shim-support.o -o work/demo-mes
gcc -O2 -fno-builtin driver.c -lm -o work/demo-libm

banner "RUN"
bug_out=$(./work/demo-mes)
ctl_out=$(./work/demo-libm)
echo "mes lib/stub/ldexp.c   : $bug_out"
echo "libm control           : $ctl_out"

banner "VERDICT"
case "$bug_out" in
  *"= 0 "*) loud "BUG REPRODUCED: Mes' ldexp(1.0, 10) returned 0.0 (a stub), not 1024.0";;
  *) die "bug did NOT reproduce: unexpected mes ldexp output: $bug_out";;
esac
case "$ctl_out" in
  *"= 1024 "*) loud "CONTROL OK: libm's ldexp(1.0, 10) == 1024.0";;
  *) die "control failed: unexpected libm output: $ctl_out";;
esac
loud "Consequence in a bootstrap: every mantissa-scaling path through mes libc"
loud "(ldexp/scalbn users, incl. tcc's own hex-float literal parser, which ends"
loud "in 'd = ldexp(d, exp)') collapses to 0.0."
echo "PASS: mes-ldexp-stub reproduced"
