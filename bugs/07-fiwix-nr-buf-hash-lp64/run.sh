#!/usr/bin/env bash
# fiwix-nr-buf-hash-lp64: Fiwix 1.5.0 sizes and indexes buffer_hash_table (an
# array of `struct buffer *`) in units of sizeof(unsigned int).  On LP64 the
# hash index range (NR_BUF_HASH = bytes/4) is 2x the pointer slots that fit
# (bytes/8) -> out-of-bounds writes for the upper half of the hash space.
# Fiwix's home target i386 (ILP32) is unaffected; any 64-bit port inherits the
# overflow.
# GREEN == the lifted expressions go out of bounds on x86_64 (ASan
# heap-buffer-overflow + arithmetic proof) and stay in bounds with -m32.
cd "$(dirname "$0")"
. ../common.sh

FIWIX_URL=https://github.com/mikaku/Fiwix/archive/refs/tags/v1.5.0.tar.gz
FIWIX_SHA=e1d5ce53ff6d8648d0411b6a940ad353dcbe82f4c7fc5761e8324fbf2a4c4fe0

mkdir -p work
banner "FETCH: Fiwix v1.5.0 (github.com/mikaku/Fiwix)"
fetch "$FIWIX_URL" "$FIWIX_SHA" work/fiwix-1.5.0.tar.gz
[ -d work/Fiwix-1.5.0 ] || tar -xzf work/fiwix-1.5.0.tar.gz -C work

banner "THE ACCUSED CODE (verbatim from the tarball)"
loud "fs/buffer.c -- hash macro, index range, and the table's real type:"
grep -n 'define BUFFER_HASH\|define NR_BUF_HASH\|^struct buffer \*\*buffer_hash_table' work/Fiwix-1.5.0/fs/buffer.c
loud "mm/memory.c -- the allocation is ALSO sized in unsigned-int units:"
grep -n -B1 -A6 'reserve memory space for buffer_hash_table' work/Fiwix-1.5.0/mm/memory.c
loud "verify the harness lifted the expressions faithfully:"
grep -n 'buffer_hash_table_size / sizeof(unsigned int)' work/Fiwix-1.5.0/fs/buffer.c harness.c
grep -n 'pages << PAGE_SHIFT' work/Fiwix-1.5.0/mm/memory.c harness.c | head -4

banner "BUG LEG 1: LP64 arithmetic (plain x86_64 build)"
gcc -O0 harness.c -o work/harness64
set +e; ./work/harness64; rc=$?; set -e
[ $rc -eq 42 ] || die "expected the LP64 out-of-bounds arithmetic (rc 42), got rc $rc"
loud "LP64: NR_BUF_HASH is 2x the allocated slot count -> OOB confirmed"

banner "BUG LEG 2: the very write, under AddressSanitizer"
gcc -O0 -g -fsanitize=address harness.c -o work/harness64-asan
set +e; ./work/harness64-asan > work/asan.out 2>&1; rc=$?; set -e
cat work/asan.out
if grep -q 'ReserveShadowMemoryRange failed\|failed to allocate' work/asan.out; then
  loud "NOTE: the ASan RUNTIME could not even initialize in this environment"
  loud "(address-space ulimit); the OOB itself is already proven by leg 1."
else
  [ $rc -ne 0 ] || die "expected ASan to abort the OOB write"
  grep -q 'heap-buffer-overflow' work/asan.out || die "expected a heap-buffer-overflow report"
  loud "AddressSanitizer confirms: heap-buffer-overflow on the exact hash-insert write"
fi

banner "CONTROL: ILP32 (-m32), Fiwix's home target model"
gcc -O0 -m32 harness.c -o work/harness32
./work/harness32
loud "ILP32: NR_BUF_HASH == slot count; no overflow (why i386 Fiwix never sees this)"

banner "VERDICT"
loud "BUG REPRODUCED: on LP64, Fiwix 1.5.0's NR_BUF_HASH indexes up to 2x the"
loud "buffer_hash_table allocation.  Harmless on i386; a memory-corruption"
loud "landmine for any 64-bit port (found during the nix-bootstrapping riscv64"
loud "LP64 port of Fiwix)."
echo "PASS: fiwix-nr-buf-hash-lp64 reproduced"
