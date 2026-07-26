#!/usr/bin/env bash
# tinyemu-builtin-clz: TinyEMU's softfp.c calls __builtin_clz()/__builtin_clzll()
# with no portable fallback, so a compiler without those GCC extensions cannot
# build it -- and the diagnostic it gets ("undefined symbol '__builtin_clz'")
# does not say so.  This is the one construct standing between TinyEMU's riscv64
# configuration and a build by a bootstrap-chain compiler, which matters because
# TinyEMU's trust-minimality argument ("~12k readable SLOC") is about source
# size, not provenance, for as long as the binary comes from an unaudited GCC.
#
# GREEN == all four of these hold, on the verbatim pinned TinyEMU release:
#   BUG        tcc compiles softfp.c to an object carrying UNDEFINED
#              __builtin_clz / __builtin_clzll symbols, and linking it fails.
#   CONTROL    gcc compiles and links the SAME file, and the resulting binary
#              produces correct IEEE-754 results.
#   FIX        with the 6-line portable fallback, tcc's object has no such
#              undefined symbols, links, and produces results BYTE-IDENTICAL to
#              the gcc control.
#   NO-REGRESSION
#              gcc's generated .text for softfp.c is byte-identical before and
#              after the patch -- the fallback is a strict no-op under GCC.
cd "$(dirname "$0")"
. ../common.sh
BUGDIR=$PWD

for t in gcc nm objdump git make curl python3 patch; do
  command -v "$t" >/dev/null || die "need $t"
done

TE_URL=https://bellard.org/tinyemu/tinyemu-2019-12-21.tar.gz
TE_SHA=be8351f2121819b3172fcedce5cb1826fa12c87da1b7ed98f269d3e802a05555
TCC_URL=https://repo.or.cz/tinycc.git
# Official mirror, used only if repo.or.cz is down; the commit pin below is the
# integrity check either way.
TCC_MIRROR_URL=https://github.com/TinyCC/tinycc.git
TCC_TAG=release_0_9_27
TCC_COMMIT=d348a9a51d32cece842b7885d27a411436d7887b

mkdir -p work
cd work

# ---------------------------------------------------------------------------
banner "1/6 -- PREMISE: the current TinyEMU release still has the bare builtins"
# ---------------------------------------------------------------------------
# TinyEMU ships as a tarball from one host: no VCS, no tracker, no mirror.  The
# "is this still true upstream?" check is therefore "is the release at that URL
# still the one we pinned, and does its softfp.c still carry the construct?".
# Unreachable host -> warn and carry on (a host being down says nothing about
# the bug); reachable but fixed -> fail loudly.
if curl -fsSL --max-time 60 --retry 2 -o live-tinyemu.tar.gz "$TE_URL"; then
  live_sha=$(sha256sum live-tinyemu.tar.gz | cut -d' ' -f1)
  if [ "$live_sha" = "$TE_SHA" ]; then
    loud "bellard.org still serves the pinned release ($TE_SHA)"
  else
    loud "!! bellard.org now serves a DIFFERENT tarball: $live_sha"
    loud "!! (TinyEMU has released a new version -- checking whether it still"
    loud "!!  has the construct; the reproduction below still uses the pin)"
    rm -rf live-src && mkdir -p live-src
    tar -C live-src -xf live-tinyemu.tar.gz --strip-components=1
    grep -q "__builtin_clz" live-src/softfp.c || die \
      "the new TinyEMU release no longer uses __builtin_clz in softfp.c -- \
upstream may have fixed this; a human must re-read the report"
    loud "the new release still uses __builtin_clz in softfp.c"
  fi
else
  loud "UPSTREAM RE-CHECK SKIPPED: could not reach $TE_URL"
  loud "  (host unreachable != bug fixed -- not failing the run over it)"
fi

fetch "$TE_URL" "$TE_SHA" tinyemu.tar.gz
rm -rf temu-stock && mkdir -p temu-stock
tar -C temu-stock -xf tinyemu.tar.gz --strip-components=1
loud "TinyEMU $(cat temu-stock/VERSION 2>/dev/null || echo 2019-12-21), softfp.c:"
sed -n '/^static inline int clz32/,/^}/p;/^static inline int clz64/,/^}/p' \
    temu-stock/softfp.c | sed 's/^/    /'
grep -q 'r = __builtin_clz(a);'   temu-stock/softfp.c || die "clz32's builtin call is not where this reproducer expects it"
grep -q 'r = __builtin_clzll(a);' temu-stock/softfp.c || die "clz64's builtin call is not where this reproducer expects it"
if grep -q '__has_builtin' temu-stock/softfp.c; then
  die "softfp.c already feature-tests its builtins -- the premise is stale"
fi
loud "the calls are unconditional: no #if, no __has_builtin, no fallback"

# ---------------------------------------------------------------------------
banner "2/6 -- a compiler that does not have them: mainline tcc $TCC_TAG"
# ---------------------------------------------------------------------------
if [ ! -d tinycc/.git ]; then
  if ! git clone -q --depth 1 --branch "$TCC_TAG" "$TCC_URL" tinycc; then
    loud "repo.or.cz unreachable; falling back to the GitHub mirror"
    rm -rf tinycc
    git clone -q --depth 1 --branch "$TCC_TAG" "$TCC_MIRROR_URL" tinycc
  fi
fi
[ "$(git -C tinycc rev-parse HEAD)" = "$TCC_COMMIT" ] || die "wrong tcc commit checked out"
git -C tinycc log -1 --format='pinned: %H %s'

echo "  tcc's entire builtin set (tcctok.h) -- note what is not in it:"
grep -n '__builtin' tinycc/tcctok.h | sed 's/^/    /'
if grep -q '__builtin_clz' tinycc/tcctok.h; then
  die "this tcc DOES know a clz builtin -- pick another non-GCC compiler"
fi
loud "no clz family: __builtin_clz / __builtin_clzll are not implemented"

if [ ! -x tinycc/tcc ]; then
  ( cd tinycc && ./configure && make tcc -j"$(nproc)" ) > tcc-build.log 2>&1 \
    || { tail -40 tcc-build.log; die "tcc build failed"; }
fi
# -B points tcc at its in-tree include/ and lib/ (it is not installed).
TCC="$PWD/tinycc/tcc -B$PWD/tinycc"
"$PWD/tinycc/tcc" -v

# ---------------------------------------------------------------------------
banner "3/6 -- BUG: tcc on the verbatim softfp.c"
# ---------------------------------------------------------------------------
# tcc accepts the call (as an implicit declaration) and emits a reference to a
# function that does not exist anywhere -- so the failure only surfaces at link
# time, as an "undefined symbol" naming a compiler builtin.
set +e
$TCC -I temu-stock -c temu-stock/softfp.c -o softfp-tcc-stock.o > tcc-compile.txt 2>&1
tcc_cc_rc=$?
set -e
sed 's/^/    /' tcc-compile.txt
[ "$tcc_cc_rc" = 0 ] || die "tcc failed to even compile softfp.c; expected it to compile with a warning"
grep -q "implicit declaration of function '__builtin_clz'" tcc-compile.txt \
  || die "expected tcc to treat __builtin_clz as an implicit declaration"

echo "  undefined symbols in the object tcc produced:"
nm softfp-tcc-stock.o > nm-stock.txt
grep -E ' U __builtin_clz' nm-stock.txt | sed 's/^/    /'
grep -q ' U __builtin_clz$'   nm-stock.txt || die "expected an undefined __builtin_clz in tcc's object"
grep -q ' U __builtin_clzll$' nm-stock.txt || die "expected an undefined __builtin_clzll in tcc's object"

gcc -O2 -g0 -I "$BUGDIR" -I temu-stock -c "$BUGDIR/softfp-driver.c" -o driver.o
set +e
gcc driver.o softfp-tcc-stock.o -o link-stock > link-stock.txt 2>&1
link_rc=$?
set -e
grep -v 'GNU-stack\|behaviour is deprecated' link-stock.txt | sed 's/^/    /' || true
[ "$link_rc" != 0 ] || die "linking tcc's object SUCCEEDED; the bug did not reproduce"
grep -q "undefined reference to \`__builtin_clz'" link-stock.txt \
  || die "expected the link to fail on __builtin_clz"
loud "BUG: softfp.c compiled by tcc cannot be linked -- __builtin_clz is undefined"

# ---------------------------------------------------------------------------
banner "4/6 -- CONTROL: gcc on the same file"
# ---------------------------------------------------------------------------
gcc -O2 -g0 -I temu-stock -c temu-stock/softfp.c -o softfp-gcc-stock.o
nm softfp-gcc-stock.o > nm-gcc.txt
if grep -q ' U __builtin_clz' nm-gcc.txt; then
  die "gcc also left __builtin_clz undefined -- something is wrong with the harness"
fi
gcc driver.o softfp-gcc-stock.o -o link-gcc
./link-gcc > values-gcc.txt
sed 's/^/    /' values-gcc.txt
grep -q 'cvt_u32_sf32(00000001) = 3f800000' values-gcc.txt \
  || die "control produced the wrong IEEE-754 result for 1.0f"
grep -q 'cvt_u64_sf64(0000000000000001) = 3ff0000000000000' values-gcc.txt \
  || die "control produced the wrong IEEE-754 result for 1.0"
loud "CONTROL OK: gcc implements the builtins, links, and computes correctly"

# ---------------------------------------------------------------------------
banner "5/6 -- FIX: the 6-line portable fallback"
# ---------------------------------------------------------------------------
rm -rf temu-fixed && cp -r temu-stock temu-fixed
( cd temu-fixed && patch -p1 --batch < "$BUGDIR/softfp-portable-clz.patch" )
# `patch` reports success for a fully-fuzzed or empty application, so assert the
# result rather than the exit code.
grep -q 'r = TEMU_CLZ32(a);' temu-fixed/softfp.c || die "the patch did not reach clz32"
grep -q 'r = TEMU_CLZ64(a);' temu-fixed/softfp.c || die "the patch did not reach clz64"
diff -u temu-stock/softfp.c temu-fixed/softfp.c | sed 's/^/    /' || true

set +e
$TCC -I temu-fixed -c temu-fixed/softfp.c -o softfp-tcc-fixed.o > tcc-compile-fixed.txt 2>&1
tcc_fix_rc=$?
set -e
sed 's/^/    /' tcc-compile-fixed.txt
[ "$tcc_fix_rc" = 0 ] || die "tcc could not compile the patched softfp.c"
if grep -q '__builtin_clz' tcc-compile-fixed.txt; then
  die "tcc still complains about __builtin_clz on the patched file"
fi
nm softfp-tcc-fixed.o > nm-fixed.txt
if grep -q ' U __builtin_clz' nm-fixed.txt; then
  die "tcc's patched object still references __builtin_clz"
fi
gcc driver.o softfp-tcc-fixed.o -o link-fixed 2> link-fixed.txt
./link-fixed > values-tcc.txt
sed 's/^/    /' values-tcc.txt
diff values-gcc.txt values-tcc.txt \
  || die "the fallback does not agree with __builtin_clz -- values differ"
loud "FIX OK: tcc links, and all $(wc -l < values-tcc.txt) conversions are byte-identical to the gcc control"

# ---------------------------------------------------------------------------
banner "6/6 -- NO REGRESSION: gcc's own code generation is untouched"
# ---------------------------------------------------------------------------
gcc -O2 -g0 -I temu-fixed -c temu-fixed/softfp.c -o softfp-gcc-fixed.o
objdump -d --no-show-raw-insn softfp-gcc-stock.o | sed '1,3d' > dis-stock.txt
objdump -d --no-show-raw-insn softfp-gcc-fixed.o | sed '1,3d' > dis-fixed.txt
cmp dis-stock.txt dis-fixed.txt \
  || die "the patch changed gcc's generated code; the fallback is meant to be a no-op under GCC"
loud "gcc's .text for softfp.c is BYTE-IDENTICAL before and after the patch"
gcc driver.o softfp-gcc-fixed.o -o link-gcc-fixed 2>/dev/null
./link-gcc-fixed > values-gcc-fixed.txt
diff values-gcc.txt values-gcc-fixed.txt || die "the patch changed gcc's results"
loud "and its results are unchanged"

banner "VERDICT"
cat <<'EOF'

  softfp.c, verbatim from the pinned TinyEMU release:

    tcc  -c  ->  compiles, object carries  U __builtin_clz / U __builtin_clzll
             ->  link fails: "undefined reference to `__builtin_clz'"
    gcc  -c  ->  compiles, links, correct IEEE-754 results       (control)

  softfp.c + the 6-line portable fallback:

    tcc  -c  ->  no undefined builtins, links, results byte-identical to gcc
    gcc  -c  ->  .text byte-identical to the unpatched build     (no regression)

  So the obstacle is exactly this one construct, and the fix costs GCC users
  nothing.  Related, from the same exercise and worth a maintainer's eye but
  not reproduced here: CONFIG_INT128=y is the Makefile default and needs
  __int128 (cutils.h already guards the typedefs on __SIZEOF_INT128__, so only
  the default is at issue), and temu.c includes <linux/if_tun.h> unconditionally
  on non-Windows even when the build has no networking.

EOF
loud "REPRODUCED: TinyEMU's softfp.c cannot be built by a compiler without the"
loud "GCC clz builtins, and a 6-line guarded fallback fixes it at zero cost."
