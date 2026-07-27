#!/usr/bin/env bash
# mes-abtod-negative-exponent: GNU Mes 0.27.1 lib/mes/abtod.c applies a
# negative decimal exponent one decade short (post-increment fires on the
# loop-exiting test, leaving e == 1 for the multiply loop): "5e-1" -> 5.0.
# Composed with reproducer #2's defects (fraction /10 once; 32-bit wrap),
# musl-1.1.24's own log10.c constants parse to exact garbage
# (log10_2hi -> 137191264.6), which is the mechanism behind flex 2.5.39's
# "fatal internal error, allocation of macro definition failed" in the
# riscv64 full-source bootstrap (flex sizes an allocation with
# (int)(1 + log10(i)) = 137191265).
#
# GREEN == every buggy value reproduces bit-exactly AND host strtod controls
# are correct.  `run.sh ablate` additionally proves the harness would notice
# the bug's absence: it reroutes the "mes" legs through host strtod and
# requires exactly the six buggy-value predictions to fail.
cd "$(dirname "$0")"
. ../common.sh

MUSL_URL=https://musl.libc.org/releases/musl-1.1.24.tar.gz
MUSL_SHA=1370c9a812b2cf2a7d92802510cca0058cc37e66a7bedd70051f0a34015022a3

mkdir -p work
fetch_mes work
MES=work/mes-0.27.1

banner "THE ACCUSED SOURCE: mes-0.27.1/lib/mes/abtod.c (verbatim from the GNU mirror tarball)"
sha256sum "$MES/lib/mes/abtod.c" "$MES/lib/mes/abtol.c"
loud "the exponent application:"
grep -n -A5 'if (e < 0)' "$MES/lib/mes/abtod.c"
loud "while (e++) evaluates the test THEN increments even when the test is 0"
loud "and exits: after the divide loop e == 1, and 'while (e--)' multiplies"
loud "once.  A negative exponent -n is applied as 10^(1-n); e-01 is a no-op."

banner "THE STIMULUS IS REAL: musl-1.1.24 src/math/log10.c contains the tested literals"
fetch "$MUSL_URL" "$MUSL_SHA" work/musl-1.1.24.tar.gz
[ -d work/musl-1.1.24 ] || tar -xzf work/musl-1.1.24.tar.gz -C work
grep -n 'log10_2hi = 3.01029995663611771306e-01' work/musl-1.1.24/src/math/log10.c
grep -n 'ivln10hi  = 4.34294481878168880939e-01' work/musl-1.1.24/src/math/log10.c
loud "any compiler whose FP-literal parsing goes through mes abtod (TinyCC's"
loud "parse_number calls the runtime strtod of the libc the tcc binary links)"
loud "bakes the garbage values below into every user of this libm."

banner "BUILD: compile the unmodified Mes sources with host gcc + a driver"
# -fwrapv: make the 32-bit signed overflow in abtol deterministic wraparound,
# which is how the bootstrap-chain compilers behave in practice.
gcc -O2 -fwrapv -fno-builtin -I shim -c "$MES/lib/mes/abtod.c"      -o work/abtod.o
gcc -O2 -fwrapv -fno-builtin -I shim -c "$MES/lib/mes/abtol.c"      -o work/abtol.o
gcc -O2 -fwrapv -fno-builtin -I shim -c "$MES/lib/ctype/isnumber.c" -o work/isnumber.o
gcc -O2 driver.c work/abtod.o work/abtol.o work/isnumber.o -o work/demo

if [ "${1:-}" = ablate ]; then
  banner "ABLATION: mes legs rerouted to host strtod; the buggy predictions must FAIL"
  if ABLATE=1 ./work/demo; then
    echo "PASS: ablation shows the assertions notice the bug's absence"
    exit 0
  fi
  die "ablation did not fail in the predicted way -- harness cannot be trusted"
fi

banner "RUN"
if ./work/demo; then
  banner "VERDICT"
  loud "BUG REPRODUCED: mes abtod applies negative exponents one decade short"
  loud "(\"5e-1\" -> 5.0), and musl's own log10.c constants parse to the exact"
  loud "garbage that made the riscv64 bootstrap's flex die on gengtype-lex.l"
  loud "((int)(1+log10_2hi_garbage) = 137191265-byte allocation)."
  echo "PASS: mes-abtod-negative-exponent reproduced"
else
  die "predicted buggy/control values did not all match -- see driver output above"
fi
