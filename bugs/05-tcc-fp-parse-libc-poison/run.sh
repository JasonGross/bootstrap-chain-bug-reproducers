#!/usr/bin/env bash
# tcc-fp-parse-libc-poison (the mechanism behind nix-bootstrapping bug17):
# tcc parses floating literals THROUGH THE C LIBRARY ITS OWN BINARY LINKS --
# the hex-float path ends in `d = ldexp(d, exp)` (Bellard, 2001; still present)
# and the decimal path calls strtod/strtold.  In a bootstrap, the libc is
# DOWNSTREAM of the compiler, so a broken-FP libc propagates into every FP
# constant the compiler emits.
# GREEN == the same tcc binary compiling the same file emits 8.0 with its
# normal libm and 0.0 under an LD_PRELOAD shim whose ldexp is `return 0;`
# (which is literally what GNU Mes' lib/stub/ldexp.c is).
cd "$(dirname "$0")"
. ../common.sh

TCC_URL=https://repo.or.cz/tinycc.git
# Official mirror, used only if repo.or.cz is down; the commit-hash pin below
# is the integrity check either way.
TCC_MIRROR_URL=https://github.com/TinyCC/tinycc.git
TCC_TAG=release_0_9_27
TCC_COMMIT=d348a9a51d32cece842b7885d27a411436d7887b

mkdir -p work
banner "FETCH: mainline tinycc @ $TCC_TAG ($TCC_COMMIT)"
if [ ! -d work/tinycc/.git ]; then
  if ! git clone -q --depth 1 --branch "$TCC_TAG" "$TCC_URL" work/tinycc; then
    loud "repo.or.cz unreachable; falling back to the GitHub mirror"
    rm -rf work/tinycc
    git clone -q --depth 1 --branch "$TCC_TAG" "$TCC_MIRROR_URL" work/tinycc
  fi
fi
[ "$(git -C work/tinycc rev-parse HEAD)" = "$TCC_COMMIT" ] || die "wrong commit checked out"
git -C work/tinycc log -1 --format='pinned: %H %s'

banner "THE MECHANISM: tccpp.c's hex-float parse ends in a call into libc"
grep -n 'ldexp' work/tinycc/tccpp.c
loud "(the decimal path right below it calls strtof/strtod/strtold the same way)"

banner "BUILD: native x86_64 tcc with gcc"
( cd work/tinycc && ./configure && make tcc -j"$(nproc)" ) > work/build.log 2>&1 \
  || { tail -40 work/build.log; die "tcc build failed"; }
./work/tinycc/tcc -v
ldd work/tinycc/tcc | grep libm || die "expected tcc to link libm dynamically"

banner "CONTROL: tcc + its normal libm compiles 'double x = 0x1p3;'"
cat hexf.c
cp hexf.c work/
( cd work && ./tinycc/tcc -c hexf.c -o hexf-clean.o )
objcopy -O binary --only-section=.data work/hexf-clean.o work/clean.bin
clean_hex=$( od -An -v -tx1 work/clean.bin | tr -d ' \n')
loud "emitted .data bytes (LE): $clean_hex"
[ "$clean_hex" = "0000000000002040" ] || die "control: expected IEEE-754 8.0 (0x4020000000000000)"
loud "CONTROL OK: 0x1p3 -> 8.0"

banner "POISONED: the SAME tcc binary under LD_PRELOAD of a return-0 ldexp"
cat ldexp0.c
gcc -shared -fPIC -o work/libldexp0.so ldexp0.c
( cd work && LD_PRELOAD="$PWD/libldexp0.so" ./tinycc/tcc -c hexf.c -o hexf-poisoned.o )
objcopy -O binary --only-section=.data work/hexf-poisoned.o work/poisoned.bin
poisoned_hex=$( od -An -v -tx1 work/poisoned.bin | tr -d ' \n')
loud "emitted .data bytes (LE): $poisoned_hex"
[ "$poisoned_hex" = "0000000000000000" ] || die "bug did NOT reproduce: expected all-zero constant"

banner "VERDICT"
loud "BUG REPRODUCED: with a broken-FP libc, tcc silently bakes 0.0 for the"
loud "hex-float literal.  This is exactly how the arm bootstrap self-poisoned:"
loud "MesCC-built tcc links mes libc (ldexp stub = return 0) -> parses every"
loud "0x1pN in musl's floatscan/scalbn as 0.0 -> tcc-musl's runtime strtod is"
loud "broken -> the next compiler generation mis-parses ITS OWN source"
loud "constants (gcc real.c M_LOG10_2 -> cc1 ICE).  A compiler's literal parser"
loud "that depends on a correct downstream libc cannot break this cycle;"
loud "an integer-only IEEE-754 constructor can."
echo "PASS: tcc-fp-parse-libc-poison reproduced"
