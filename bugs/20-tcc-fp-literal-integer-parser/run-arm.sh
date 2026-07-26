#!/usr/bin/env bash
# tcc-fp-literal-integer-parser -- FAITHFUL-ARM leg (companion to run.sh).
#
# run.sh builds the fork as a host->arm CROSS tcc (RUNS as x86, EMITS arm) and so
# can only exercise float + double: that tcc inherits the HOST's 80-bit `long
# double` for its own tokc.ld, which is not arm's 64-bit long double, so the L
# path is not faithfully modelled there.  THIS leg closes that gap.  It builds the
# fork as an ARM-NATIVE tcc (arm-linux-gnueabihf-gcc -> arm ELF, run under
# qemu-arm-static), on which `long double == double == 8 bytes` (asserted below),
# and runs the FULL 2x2 {0011+0012, +0013} x {clean, poison} over a battery that
# INCLUDES long-double `L` literals.
#
# The cell that matters: patch 0013 exists to make FP literals exact WHEN THE LIBC
# IS BROKEN (it parses with integer arithmetic instead of ldexp/strtod/strtold).
# So the claim "F/L exact on an 8-byte-long-double target" is only supported by the
# poisoned column.  This leg shows, on a faithful arm target:
#   fixed  + poison  ->  every literal incl L byte-exact   (0013 routes around libc)
#   buggy  + poison  ->  every literal incl L all-zero     (the defect it fixes)
#   *      + clean   ->  every literal exact                (0013 is a no-op when libc is fine)
#
# GREEN == all of that holds.  Correct-behaviour controls: the healthy column and
# the buggy+poison all-zero control.  Ablation (ABLATE=1) points the fixed+poison
# checks at the buggy compiler; the named "0013 delivers exact under poison"
# assertion must then fire.
cd "$(dirname "$0")"
. ../common.sh
BUGDIR=$PWD

FORK_URL=https://gitlab.com/janneke/tinycc.git
FORK_COMMIT=ee75a10cd71bebf23cb23598a49ee3c160ef0fe8   # branch mes-0.25.0
FORK_BRANCH=mes-0.25.0

for t in arm-linux-gnueabihf-gcc arm-linux-gnueabihf-objcopy qemu-arm-static python3 git; do
  command -v "$t" >/dev/null || die "need $t (see the workflow for apt names)"
done
CC=arm-linux-gnueabihf-gcc
OBJCOPY=arm-linux-gnueabihf-objcopy
QEMU=qemu-arm-static

# Same target defines as run.sh's host->arm cross build (this is what the mes/tcc
# arm bootstrap uses); only the COMPILER differs (arm-native here) and we add
# -static so the arm ELF runs under qemu with no arm sysroot.  No -D__MES_INTPTR_T:
# that is a musl-header workaround; arm-linux-gnueabihf is glibc, like run.sh's host.
TFLAGS=(-w -DBOOTSTRAP=1 -DTCC_TARGET_ARM=1 -DTCC_ARM_EABI=1 -DTCC_ARM_VFP=1
        -DHAVE_LONG_LONG=1 -DHAVE_FLOAT=1 -DHAVE_BITFIELD=1 -DHAVE_SETJMP=1
        -DONE_SOURCE=1 -DTCC_VERSION='"0.9.26"'
        -DCONFIG_TCCDIR='"/usr/lib/tcc"' -DCONFIG_TCC_CRTPREFIX='"/nonexistent"'
        -DCONFIG_TCC_SYSINCLUDEPATHS='"/nonexistent"'
        -DCONFIG_TCC_LIBPATHS='"/nonexistent"' -DCONFIG_TCC_ELFINTERP='"/mes/loader"')
WRAP=(-Wl,--wrap=ldexp -Wl,--wrap=strtod -Wl,--wrap=strtof -Wl,--wrap=strtold)

mkdir -p work-arm
cd work-arm

banner "1/6 -- FAITHFULNESS: the arm target has an 8-byte long double"
# The whole point of this leg is a target where long double == double == 8 bytes.
# Assert it against the reference compiler; if it were 16 bytes the L comparison
# below (which reads 8 bytes) could pass on a truncation and prove nothing.
cat > ldsize.c <<'EOF'
int _ld_is_8[sizeof(long double) == 8 ? 1 : -1];
int _d_is_8 [sizeof(double)      == 8 ? 1 : -1];
EOF
$CC -c -o ldsize.o ldsize.c 2>ldsize.log \
  || { cat ldsize.log; die "arm target long double is NOT 8 bytes -- vehicle not faithful"; }
loud "arm-linux-gnueabihf: sizeof(long double) == sizeof(double) == 8 (static-asserted)"

banner "2/6 -- FETCH: janneke tinycc fork @ $FORK_COMMIT ($FORK_BRANCH)"
if [ ! -d pristine/.git ]; then
  git init -q pristine
  if ! git -C pristine fetch -q --depth 1 "$FORK_URL" "$FORK_COMMIT" 2>/dev/null; then
    loud "shallow by-sha fetch refused; falling back to branch clone"
    git -C pristine fetch -q "$FORK_URL" "refs/heads/$FORK_BRANCH:refs/heads/$FORK_BRANCH"
  fi
  git -C pristine checkout -q "$FORK_COMMIT"
  git -C pristine config user.name reproducer
  git -C pristine config user.email reproducer@invalid
fi
[ "$(git -C pristine rev-parse HEAD)" = "$FORK_COMMIT" ] || die "wrong commit checked out"
git -C pristine log -1 --format='pinned: %H %s'

banner "3/6 -- PREMISE: the fork's literal parser routes through the C library"
# Otherwise a broken libc would poison nothing and the buggy+poison leg (incl L)
# would pass vacuously.  Assert the accused calls are present.
grep -qE 'ldexp\(d, exp_val' pristine/tccpp.c || die \
  "tccpp.c no longer calls ldexp on the hex-float path -- premise stale, re-read the report"
grep -qE 'strtod\(token_buf' pristine/tccpp.c || die \
  "tccpp.c no longer calls strtod on the decimal path -- premise stale, re-read the report"
grep -qE 'strtold\(token_buf' pristine/tccpp.c || die \
  "tccpp.c no longer calls strtold on the long-double decimal path -- premise stale"
loud "tccpp.c parses hex floats with ldexp and decimals with strtod/strtof/strtold:"
grep -nE 'ldexp\(d,|strtof\(token_buf|strtod\(token_buf|strtold\(token_buf' pristine/tccpp.c | sed 's/^/    /'

banner "4/6 -- BUILD four arm-native tcc variants: {buggy=0011+0012, fixed=+0013} x {clean, poison}"
build_variant () { # <label> <fixed:0|1> <poison:0|1>
  local label="$1" fixed="$2" poison="$3" src="src-$1"
  rm -rf "$src"; cp -a pristine "$src"
  git -C "$src" am -q "$BUGDIR/patches/0011-arm-init_putv-bit-copy-fp-constants-not-convert.patch"
  git -C "$src" am -q "$BUGDIR/patches/0012-arm-init_putv-bit-copy-long-double-constants.patch"
  if [ "$fixed" = 1 ]; then
    git -C "$src" am -q "$BUGDIR/patches/0013-tcc-parse-fp-literals-with-integer-arithmetic.patch"
  fi
  python3 "$BUGDIR/mescc-era-shims.py" "$src/arm-gen.c" "$src/tccgen.c" >/dev/null
  : > "$src/config.h"
  local extra=()
  [ "$poison" = 1 ] && extra=("${WRAP[@]}" "$BUGDIR/poison-fp.c")
  "$CC" -static -O0 "${TFLAGS[@]}" "${extra[@]}" -o "tcc-$label" "$src/tcc.c" 2> "build-$label.log" \
    || { tail -25 "build-$label.log"; die "arm build of tcc-$label failed"; }
  file "tcc-$label" | grep -q 'ELF 32-bit LSB.*ARM' || die "tcc-$label is not an arm ELF"
}
build_variant buggy-clean  0 0
build_variant buggy-poison 0 1
build_variant fixed-clean  1 0
build_variant fixed-poison 1 1
loud "0013 present in the fixed trees:"
grep -c 'tokc.tab' src-fixed-poison/tccpp.c | sed 's/^/    tokc.tab writes in tccpp.c: /'
grep -q 'tokc.tab' src-buggy-poison/tccpp.c \
  && die "the buggy tree already has 0013's integer path -- patch selection is wrong"
loud "and absent in the buggy trees (parse still via ldexp/strtod/strtold)"

banner "5/6 -- COMPILE the battery (incl long-double L) with each variant, compare .data"
# Under ABLATE=1 the 'fixed + poison' column is pointed at the BUGGY+poison
# compiler; the named "0013 delivers exact under poison" assertion must fire.
FIXPOISON=./tcc-fixed-poison
if [ "${ABLATE:-0}" = 1 ]; then
  loud "ABLATE=1: 'fixed+poison' is pointed at the BUGGY compiler; the FIX"
  loud "          assertion MUST fail (a 0013-less parser emits 0.0 under poison)."
  FIXPOISON=./tcc-buggy-poison
fi

# name : ctype : size : literal.  L literals declared `long double` (arm: 8 bytes);
# oracle packs <d because arm long double == IEEE double.  ieee.py strips the L.
battery=(
  "f_2p5:float:4:2.5f"
  "f_tenth:float:4:0.1f"
  "d_2p5:double:8:2.5"
  "d_1e6:double:8:1e6"
  "d_pi:double:8:3.14159265358979323846"
  "ld_1e9:long double:8:1e9L"
  "ld_1p0:long double:8:1.0L"
  "ld_2p5:long double:8:2.5L"
  "ld_tenth:long double:8:0.1L"
  "ld_log10_2:long double:8:0.30102999566398119521L"
  "ld_pi:long double:8:3.14159265358979323846L"
)
emit () { # <tcc> <cfile> <size> -> leading <size> bytes hex; asserts exact width for L
  local tcc="$1" cf="$2" sz="$3"
  "$QEMU" "$tcc" -c -o probe.o "$cf" 2>/dev/null || die "$tcc failed to compile $cf (under qemu)"
  "$OBJCOPY" -O binary --only-section=.data probe.o probe.bin 2>/dev/null
  [ -s probe.bin ] || die "$tcc emitted an empty .data for $cf"
  local n; n=$(wc -c < probe.bin)
  [ "$n" -ge "$sz" ] || die "$tcc emitted a .data of $n bytes for $cf, expected >= $sz"
  od -An -v -tx1 probe.bin | tr -d ' \n' | cut -c1-$((sz * 2))
}
printf "    %-26s %-18s | %-16s %-16s %-16s %-16s\n" "LITERAL(ctype)" EXPECTED buggy+clean fixed+clean fixed+poison buggy+poison
fail=0; lcrit=0; lok=0
for entry in "${battery[@]}"; do
  IFS=: read -r name ctype sz lit <<<"$entry"
  okind=float; [ "$ctype" = float ] || okind=double
  exp=$(python3 "$BUGDIR/ieee.py" "$okind" "$lit")
  printf '%s v = %s;\n' "$ctype" "$lit" > "$name.c"
  bc=$(emit ./tcc-buggy-clean  "$name.c" "$sz")
  fc=$(emit ./tcc-fixed-clean  "$name.c" "$sz")
  fp=$(emit "$FIXPOISON"       "$name.c" "$sz")
  bp=$(emit ./tcc-buggy-poison "$name.c" "$sz")
  zero=$(printf '00%.0s' $(seq 1 "$sz"))
  printf "    %-26s %-18s | %-16s %-16s %-16s %-16s\n" "$lit" "$exp" "$bc" "$fc" "$fp" "$bp"
  [ "$bc" = "$exp" ] || { loud "!! buggy+clean wrong for $lit: $bc != $exp"; fail=1; }
  [ "$fc" = "$exp" ] || { loud "!! fixed+clean wrong for $lit (0013 regressed a normal build): $fc != $exp"; fail=1; }
  [ "$bp" = "$zero" ] || { loud "!! expected buggy+poison all-zero for $lit, got $bp"; fail=1; }
  [ "$fp" = "$exp" ] || { loud "!! THE FIX FAILED: fixed+poison not exact for $lit: $fp != $exp"; fail=1; }
  case "$ctype" in "long double")
    lcrit=$((lcrit+1)); [ "$fp" = "$exp" ] && lok=$((lok+1)) ;;
  esac
done
[ "$fail" = 0 ] || die "one or more battery expectations failed (see !! lines above)"

banner "6/6 -- VERDICT"
[ "$lcrit" -ge 1 ] || die "no long-double literals exercised -- this leg's whole purpose is L (harness suspect)"
loud "long-double literals under a POISONED libc: fixed+poison $lok/$lcrit byte-exact; buggy+poison all-zero"
loud "float + double: exact in every column that should be, all-zero under buggy+poison"
loud "PASS: on a faithful 8-byte-long-double arm target, patch 0013 makes every FP"
loud "      literal INCLUDING long double exact even when ldexp/strtod/strtof/strtold"
loud "      are all broken; the unpatched parser zeroes them.  0013 is a no-op on a"
loud "      healthy libc.  This is the L evidence run.sh's host->arm cross cannot give."
