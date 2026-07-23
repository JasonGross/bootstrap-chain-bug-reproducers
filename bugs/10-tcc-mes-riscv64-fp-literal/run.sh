#!/usr/bin/env bash
# tcc-mes-riscv64-fp-literal: the mes-lineage riscv64 tcc parses FP literals
# through the broken mes-libc FP stack (tccpp.c parse_number ends in
# strtod/strtold from the libc the running tcc links), so every decimal FP
# constant is garbage lineage-wide; and MesCC, the compiler that builds the
# first tcc, has no FP support at all.
# GREEN == mes strtod (verbatim sources, host gcc) parses "0.9999" as EXACTLY
# 999.9 -- the ceil() constant observed in the nix-bootstrapping riscv64
# fixpoint forensics -- conflating it bit-for-bit with "999.9", AND MesCC
# demonstrably cannot materialize the IEEE constant at all; host strtod is
# the correct-behavior control.
cd "$(dirname "$0")"
. ../common.sh
BUGDIR=$PWD

command -v guile >/dev/null || die "need guile 3.x (apt: guile-3.0)"

FORK_URL=https://gitlab.com/janneke/tinycc.git
FORK_COMMIT=ee75a10cd71bebf23cb23598a49ee3c160ef0fe8   # branch mes-0.25.0
FORK_BRANCH=mes-0.25.0

mkdir -p work
fetch_mes work
fetch_nyacc work
MES=$PWD/work/mes-0.27.1
printf '#undef SYSTEM_LIBC\n#define MES_VERSION "0.27.1"\n' > "$MES/include/mes/config.h"

banner "FETCH: janneke tinycc fork @ $FORK_COMMIT ($FORK_BRANCH)"
if [ ! -d work/tinycc/.git ]; then
  git init -q work/tinycc
  if ! git -C work/tinycc fetch -q --depth 1 "$FORK_URL" "$FORK_COMMIT" 2>/dev/null; then
    loud "shallow by-sha fetch refused; falling back to branch clone"
    git -C work/tinycc fetch -q "$FORK_URL" "refs/heads/$FORK_BRANCH:refs/heads/$FORK_BRANCH"
  fi
  git -C work/tinycc checkout -q "$FORK_COMMIT"
fi
[ "$(git -C work/tinycc rev-parse HEAD)" = "$FORK_COMMIT" ] || die "wrong commit checked out"
git -C work/tinycc log -1 --format='pinned: %H %s'

banner "THE ACCUSED PATH 1/3: tcc's literal parser IS the libc its binary links"
loud "tccpp.c parse_number (janneke fork, the riscv64 tcc-mes lineage):"
grep -n 'strtof (token_buf\|strtod (token_buf\|strtold (token_buf\|strtof(token_buf\|strtod(token_buf\|strtold(token_buf' work/tinycc/tccpp.c \
  || grep -n 'strto[fdl]' work/tinycc/tccpp.c | head -6
loud "in the bootstrap that libc is mes libc, so literal VALUES = mes strtod output."

banner "THE ACCUSED PATH 2/3: mes strtod -> abtod misscales every fraction"
sha256sum "$MES/lib/stdlib/strtod.c" "$MES/lib/mes/abtod.c"
grep -n -A2 'strtod (char const \*string' "$MES/lib/stdlib/strtod.c" | head -8
grep -n -B2 -A1 'd = i + f / dbase;' "$MES/lib/mes/abtod.c"
loud "the in-chain victim constant, mes' own libc (lib/math/ceil.c):"
grep -n '0.9999' "$MES/lib/math/ceil.c"

banner "BUILD: compile the unmodified Mes strtod stack with host gcc + driver"
loud "(one transparent tweak: -Dstrtod=mes_strtod on strtod.c, so the verbatim"
loud " mes function can coexist with the host-libc strtod used as control)"
gcc -O2 -fno-builtin -I shim -Dstrtod=mes_strtod -c "$MES/lib/stdlib/strtod.c" -o work/strtod.o
gcc -O2 -fno-builtin -I shim -c "$MES/lib/mes/abtod.c"      -o work/abtod.o
gcc -O2 -fno-builtin -I shim -c "$MES/lib/mes/abtol.c"      -o work/abtol.o
gcc -O2 -fno-builtin -I shim -c "$MES/lib/ctype/isnumber.c" -o work/isnumber.o
gcc -O2 driver.c work/strtod.o work/abtod.o work/abtol.o work/isnumber.o -o work/demo

banner "RUN: \"0.9999\" through mes strtod (bug) and host strtod (control)"
if ! ./work/demo; then
  die "predicted buggy/control values did not all match -- see driver output above"
fi

banner "THE ACCUSED PATH 3/3: MesCC itself has no FP -- the constant cannot even be born"
export GUILE_LOAD_PATH="$MES/module:$PWD/work/nyacc-1.00.2/module"
export MES_PREFIX="$MES"
mescc () { guile --no-auto-compile -e main -s "$BUGDIR/mescc-guile.scm" "$@"; }
cp dbl-local.c dbl-global.c work/

loud "mescc --arch riscv64 -S dbl-local.c (double d = 0.9999; in a function):"
( cd work && mescc --arch riscv64 -S -o dbl-local.s dbl-local.c )
grep -n '0.9999' work/dbl-local.s || die "expected the literal in the emitted .s"
grep -q '!0.9999 addi' work/dbl-local.s \
  || die "expected the FP literal as an INTEGER addi immediate in the .s"
loud "=> the double literal is emitted as an INTEGER addi immediate (!0.9999);"
loud "   there is no IEEE-754 materialization anywhere in MesCC's riscv64 output."

loud "mescc --arch riscv64 -S dbl-global.c (double d = 0.9999; at file scope):"
set +e
( cd work && mescc --arch riscv64 -S -o dbl-global.s dbl-global.c ) > work/dbl-global.log 2>&1
rc=$?
set -e
tail -2 work/dbl-global.log
[ "$rc" != 0 ] || die "mescc unexpectedly compiled a global double initializer"
grep -q 'init->data: not supported' work/dbl-global.log \
  || die "expected 'init->data: not supported' from mescc"
loud "=> MesCC cannot emit a global double initializer AT ALL."

banner "VERDICT"
loud "BUG REPRODUCED (component level): in the mes-lineage riscv64 tcc, FP"
loud "literals are parsed by mes strtod -> abtod, which turns \"0.9999\" into"
loud "EXACTLY 999.9 (0x408F3F3333333333) -- bit-identical to its parse of"
loud "\"999.9\" -- instead of 0x3FEFFF2E48E8A71E; and the MesCC stage upstream"
loud "has no FP representation at all.  In the nix-bootstrapping riscv64"
loud "fixpoint forensics this is visible in-chain: the ENTIRE binary delta"
loud "between the MesCC-built tcc-mes and its self-rebuilt successor is the"
loud "8-byte constant for mes libc ceil()'s literal 0.9999 (garbage bits vs"
loud "999.9).  Same disease as bugs 1/2/5, exhibited on the riscv64 lineage's"
loud "own victim constant."
echo "PASS: tcc-mes-riscv64-fp-literal reproduced"
