#!/usr/bin/env bash
# tcc-riscv64-ldouble-cross (ALREADY REPORTED upstream as
# codeberg.org/ekaitz-zarraga/tcc issue #1; fixed in tinycc mob 923fba83
# "general: long double issues"): a cross tcc targeting riscv64 (long double
# == IEEE binary128) built on x86_64 (long double == x87 80-bit) materialized
# long double constants by copying the HOST's x87 image into the target slot.
# GREEN == the pre-fix mob snapshot emits the x87-padded bytes for 1e9L while
# the fix commit itself emits the correct binary128 (plus a riscv64-gcc
# oracle agreeing with the computed binary128).
cd "$(dirname "$0")"
. ../common.sh

TCC_URL=https://repo.or.cz/tinycc.git
# Official mirror, used only if repo.or.cz is down; the pinned commit hash is
# the integrity check either way.
TCC_MIRROR_URL=https://github.com/TinyCC/tinycc.git
FIX_COMMIT=923fba83f1e541750c4dd48a4ec02af831ee5af8   # mob, 2026-05-06

mkdir -p work
banner "FETCH: tinycc mob; pre-fix = ${FIX_COMMIT:0:12}~1, control = the fix commit itself"
if [ ! -d work/tinycc/.git ]; then
  if git clone -q "$TCC_URL" work/tinycc && git -C work/tinycc fetch -q origin mob; then
    :
  else
    loud "repo.or.cz unreachable; falling back to the GitHub mirror"
    rm -rf work/tinycc
    git clone -q --single-branch --branch mob "$TCC_MIRROR_URL" work/tinycc
  fi
fi
git -C work/tinycc cat-file -e "$FIX_COMMIT" || die "fix commit not found in mob"
git -C work/tinycc log -1 --format='fix commit: %H %ci %s' "$FIX_COMMIT"
git -C work/tinycc log -1 --format='pre-fix   : %H %ci %s' "$FIX_COMMIT~1"

build_riscv64_tcc () { # $1 = commit, $2 = output name
  git -C work/tinycc checkout -q "$1"
  ( cd work/tinycc && make distclean ) >/dev/null 2>&1 || true
  ( cd work/tinycc \
    && ./configure \
    && make riscv64-tcc -j"$(nproc)" ) > "work/build-$2.log" 2>&1 \
    || { tail -30 "work/build-$2.log"; die "build of $2 failed"; }
  cp work/tinycc/riscv64-tcc "work/$2"
}

banner "BUILD: both riscv64-targeting cross tccs natively on x86_64"
build_riscv64_tcc "$FIX_COMMIT~1" tcc-prefix
build_riscv64_tcc "$FIX_COMMIT"   tcc-fixed

banner "REPRODUCE: pre-fix cross tcc compiles 'long double x = 1000000000.0L;'"
cat ldc.c
cp ldc.c work/
( cd work && ./tcc-prefix -c ldc.c -o ldc-prefix.o )
objcopy -I elf64-little -O binary --only-section=.data work/ldc-prefix.o work/prefix.bin
python3 check-quad.py work/prefix.bin prefix

banner "CONTROL 1: the fix commit itself (mob ${FIX_COMMIT:0:12})"
( cd work && ./tcc-fixed -c ldc.c -o ldc-fixed.o )
objcopy -I elf64-little -O binary --only-section=.data work/ldc-fixed.o work/fixed.bin
python3 check-quad.py work/fixed.bin fixed

if command -v riscv64-linux-gnu-gcc >/dev/null; then
  banner "CONTROL 2: riscv64-linux-gnu-gcc oracle"
  riscv64-linux-gnu-gcc -c work/ldc.c -o work/ldc-gcc.o
  for sec in .data .sdata; do   # gcc may use small-data sections on riscv
    riscv64-linux-gnu-objcopy -O binary --only-section=$sec work/ldc-gcc.o work/gcc.bin
    [ "$(stat -c%s work/gcc.bin)" -ge 16 ] && break
  done
  python3 check-quad.py work/gcc.bin gcc
fi

banner "VERDICT"
loud "BUG REPRODUCED (and already fixed upstream): pre-923fba83 riscv64 cross"
loud "tcc writes the host x87 80-bit image into the target's 16-byte binary128"
loud "slot; the fix converts properly.  This bit the riscv64 bootstrap chain"
loud "through the chain-vintage ekaitz-zarraga/tcc fork (codeberg issue #1)."
echo "PASS: tcc-riscv64-ldouble-cross reproduced (ALREADY REPORTED upstream)"
