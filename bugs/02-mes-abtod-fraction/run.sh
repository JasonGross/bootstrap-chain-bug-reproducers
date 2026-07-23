#!/usr/bin/env bash
# mes-abtod-fraction: GNU Mes 0.27.1 lib/mes/abtod.c (the strtod backend)
# scales the fractional digit string by /10 once instead of /10^ndigits, and
# accumulates the integer part in 32 bits.
# GREEN == abtod("123456.75") == 123463.5 and abtod("4294967296.0") == 0,
# while host strtod (control) returns the correct values.
cd "$(dirname "$0")"
. ../common.sh

mkdir -p work
fetch_mes work
MES=work/mes-0.27.1

banner "THE ACCUSED SOURCE: mes-0.27.1/lib/mes/abtod.c (verbatim from the GNU mirror tarball)"
sha256sum "$MES/lib/mes/abtod.c" "$MES/lib/mes/abtol.c"
loud "abtod.c fractional-part computation:"
grep -n -B2 -A1 'd = i + f / dbase;' "$MES/lib/mes/abtod.c"
loud "f is the ENTIRE fractional digit string parsed as one integer;"
loud "dividing by dbase (10) once is only correct for single-digit fractions."
loud "abtol.c accumulator (long return, but 32-bit int accumulation):"
grep -n 'int i = 0;' "$MES/lib/mes/abtol.c"

banner "BUILD: compile the unmodified Mes sources with host gcc + a driver"
# -fwrapv: make the 32-bit signed overflow in abtol deterministic wraparound,
# which is how the bootstrap-chain compilers (mescc, tcc, gcc on arm/x86)
# behave in practice.
gcc -O2 -fwrapv -fno-builtin -I shim -c "$MES/lib/mes/abtod.c"    -o work/abtod.o
gcc -O2 -fwrapv -fno-builtin -I shim -c "$MES/lib/mes/abtol.c"    -o work/abtol.o
gcc -O2 -fwrapv -fno-builtin -I shim -c "$MES/lib/ctype/isnumber.c" -o work/isnumber.o
gcc -O2 driver.c work/abtod.o work/abtol.o work/isnumber.o -o work/demo

banner "RUN"
if ./work/demo; then
  banner "VERDICT"
  loud "BUG REPRODUCED: mes strtod/abtod returns 123463.5 for \"123456.75\""
  loud "(off by 7185.25) and 0 for \"4294967296.0\"; host strtod control correct."
  loud "Consequence in a bootstrap: any FP literal or runtime strtod that goes"
  loud "through mes libc is silently wrong unless it has <= 1 fractional digit"
  loud "and a < 2^31 integer part."
  echo "PASS: mes-abtod-fraction reproduced"
else
  die "predicted buggy/control values did not all match -- see driver output above"
fi
