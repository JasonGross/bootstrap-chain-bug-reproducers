#!/usr/bin/env bash
# mes-dtoab-leading-zeros: GNU Mes 0.27.1's float->decimal routine (lib/mes/
# dtoab.c, which printf("%f") calls) prints the fractional digits as a plain
# integer, so every LEADING zero of the fraction is lost and the decimal point
# lands in the wrong place -- 3.0009 renders as "3.9", and 0.005/0.05/0.5 all
# render as "0.5".
# This is the OUTPUT-side counterpart of bug 2 (abtod, the input side).
# GREEN == the predicted wrong strings appear exactly, including the
# three-way conflation, with the host libc as the correct-behavior control.
cd "$(dirname "$0")"
. ../common.sh

mkdir -p work
fetch_mes work
MES=work/mes-0.27.1

banner "THE ACCUSED SOURCE: mes-0.27.1/lib/mes/dtoab.c (verbatim from the GNU mirror tarball)"
sha256sum "$MES/lib/mes/dtoab.c"
sed -n '/^dtoab/,/^}/p' "$MES/lib/mes/dtoab.c"
grep -q '(d - (double) i) \* (double) 100000000' "$MES/lib/mes/dtoab.c" \
  || die "dtoab's fraction scaling is not where we expect it"
loud "the fraction is scaled to an integer and printed with ntoab -- as an"
loud "INTEGER, with no zero padding -- so .0625 prints as \"625\", not \"0625\"."

banner "WHERE IT IS USED: printf(\"%f\") goes straight through dtoab"
grep -n -B2 -A2 'dtoab (d, 10, 1)' "$MES/lib/stdio/vfprintf.c" | sed 's/^/    /'

banner "BUILD: compile the unmodified Mes sources with host gcc + a driver"
gcc -O2 -fno-builtin -I shim -c "$MES/lib/mes/dtoab.c" -o work/dtoab.o
gcc -O2 -fno-builtin -I shim -c "$MES/lib/mes/ntoab.c" -o work/ntoab.o
gcc -O2 driver.c work/dtoab.o work/ntoab.o -o work/demo

banner "RUN"
if ./work/demo; then
  banner "VERDICT"
  loud "BUG REPRODUCED: mes libc renders 3.0009 as \"3.9\" (1000x), 1.0625 as"
  loud "\"1.625\" (10x), and 0.005 / 0.05 / 0.5 ALL as \"0.5\"."
  loud "Consequence in a bootstrap: any build-time GENERATOR that prints a"
  loud "float through the bootstrap libc writes wrong text into generated"
  loud "source.  In the arm bootstrap ladder the same class of defect"
  loud "(there via the boot musl, not mes) made GMP's gen-psqr emit a 2.4 GB"
  loud "mpn/perfsqr.h whose header comment read \"0+00%\" instead of \"82.81%\"."
  loud "Note that is the OUTPUT half of the FP problem; bug 5's tcc literal"
  loud "parsing is the INPUT half.  A bootstrap has neither in working order."
  echo "PASS: mes-dtoab-leading-zeros reproduced"
else
  die "predicted buggy/control values did not all match -- see driver output above"
fi
