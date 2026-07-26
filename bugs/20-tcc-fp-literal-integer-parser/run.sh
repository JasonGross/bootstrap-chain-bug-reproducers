#!/usr/bin/env bash
# tcc-fp-literal-integer-parser (board row 4): the patch-verifying leg for
# tinycc patch 0013 (the integer-only IEEE-754 literal parser).
#
# bugs/05-tcc-fp-parse-libc-poison shows the MECHANISM -- the janneke tinycc
# fork parses every floating literal through the C library its own binary links
# (tccpp.c: the hex path ends in ldexp, the decimal path in strtof/strtod/
# strtold), so a broken-FP libc downstream of the compiler poisons every FP
# constant it emits.  This leg shows patch 0013 CURES it: with the literal-to-
# bits step rewritten in pure integer arithmetic, the same broken-libc build
# emits correct constants.
#
# It builds the fork's arm cross-compiler four ways -- {without 0013 = "buggy",
# with 0013 = "fixed"} x {normal host FP = "clean", a broken ldexp/strtod
# interposed = "poison"} -- and compiles a battery of float/double literals with
# each, comparing the emitted .data to the correctly-rounded IEEE-754 bytes
# (computed independently by CPython in ieee.py).  GREEN requires the full 2x2:
#
#   buggy  + clean   -> correct   (the parser is fine WITH a working libc:
#                                   the defect is the libc dependency itself)
#   buggy  + poison  -> ALL ZERO  (THE BUG: broken ldexp/strtod poison every
#                                   literal the unpatched parser produces)
#   fixed  + clean   -> correct   (0013 is a no-op when the libc is fine)
#   fixed  + poison  -> correct   (THE FIX: 0013 does not touch the libc, so a
#                                   broken one cannot reach the constants)
#
# The tcc built here is a gcc-built host->arm CROSS compiler (it RUNS on the
# host and EMITS arm), so "poison" is interposed on the tcc binary via
# -Wl,--wrap (the bootstrap tcc is -static; LD_PRELOAD, bug 05's method, does
# not apply to a static binary).  A MesCC-built tcc links a real broken mes-libc;
# --wrap of a return-0 ldexp / return-0 strto* reproduces that condition exactly.
#
# SCOPE: float (binary32) and double (binary64) only -- the report's exact,
# fixpoint-validated claim.  long double is deliberately NOT tested here: this
# host->arm cross tcc inherits the HOST's 80-bit long double for its own
# tokc.ld, which is not arm's 64-bit long double, so the ld path is not
# faithfully modelled by a cross build (0013's arm ld gating is validated in the
# from-seed self-host, not here).  Do not extend the battery to `L` literals.
cd "$(dirname "$0")"
. ../common.sh
BUGDIR=$PWD

FORK_URL=https://gitlab.com/janneke/tinycc.git
FORK_COMMIT=ee75a10cd71bebf23cb23598a49ee3c160ef0fe8   # branch mes-0.25.0
FORK_BRANCH=mes-0.25.0

for t in gcc arm-linux-gnueabihf-objcopy python3 git; do
  command -v "$t" >/dev/null || die "need $t (see the workflow for apt names)"
done

# The gcc build flags for the fork as a host->arm cross compiler (the same
# target defines the mes/tcc arm bootstrap uses; -DBOOTSTRAP=1 selects the
# fork's bootstrap init_putv arms that patches 0011/0012 fix).
TFLAGS=(-w -DBOOTSTRAP=1 -DTCC_TARGET_ARM=1 -DTCC_ARM_EABI=1 -DTCC_ARM_VFP=1
        -DHAVE_LONG_LONG=1 -DHAVE_FLOAT=1 -DHAVE_BITFIELD=1 -DHAVE_SETJMP=1
        -DONE_SOURCE=1 -DTCC_VERSION='"0.9.26"'
        -DCONFIG_TCCDIR='"/usr/lib/tcc"' -DCONFIG_TCC_CRTPREFIX='"/nonexistent"'
        -DCONFIG_TCC_SYSINCLUDEPATHS='"/nonexistent"'
        -DCONFIG_TCC_LIBPATHS='"/nonexistent"' -DCONFIG_TCC_ELFINTERP='"/mes/loader"')
WRAP=(-Wl,--wrap=ldexp -Wl,--wrap=strtod -Wl,--wrap=strtof -Wl,--wrap=strtold)
OBJCOPY=arm-linux-gnueabihf-objcopy

mkdir -p work
cd work

banner "1/5 -- FETCH: janneke tinycc fork @ $FORK_COMMIT ($FORK_BRANCH)"
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

banner "2/5 -- PREMISE: the fork's literal parser routes through the C library"
# The stimulus this reproducer needs is that tccpp.c actually converts literals
# with ldexp/strtod -- otherwise a broken libc would poison nothing and the
# 'buggy + poison' leg would pass vacuously.  Assert the accused calls are there.
grep -qE 'ldexp\(d, exp_val' pristine/tccpp.c || die \
  "tccpp.c no longer calls ldexp on the hex-float path -- premise stale, re-read the report"
grep -qE 'strtod\(token_buf' pristine/tccpp.c || die \
  "tccpp.c no longer calls strtod on the decimal path -- premise stale, re-read the report"
loud "tccpp.c parses hex floats with ldexp and decimals with strtod/strtof/strtold:"
grep -nE 'ldexp\(d,|strtof\(token_buf|strtod\(token_buf|strtold\(token_buf' pristine/tccpp.c | sed 's/^/    /'

banner "3/5 -- BUILD four cross-tcc variants: {buffy=0011+0012, fixed=+0013} x {clean, poison}"
# build_variant <label> <fixed:0|1> <poison:0|1>
build_variant () {
  local label="$1" fixed="$2" poison="$3" src="src-$1"
  rm -rf "$src"; cp -a pristine "$src"
  git -C "$src" am -q "$BUGDIR/patches/0011-arm-init_putv-bit-copy-fp-constants-not-convert.patch"
  git -C "$src" am -q "$BUGDIR/patches/0012-arm-init_putv-bit-copy-long-double-constants.patch"
  if [ "$fixed" = 1 ]; then
    git -C "$src" am -q "$BUGDIR/patches/0013-tcc-parse-fp-literals-with-integer-arithmetic.patch"
  fi
  # make the fork's BOOTSTRAP+arm source compile under host gcc (disjoint from
  # any FP logic -- see mescc-era-shims.py; it fails loudly if it matches nothing)
  python3 "$BUGDIR/mescc-era-shims.py" "$src/arm-gen.c" "$src/tccgen.c" >/dev/null
  : > "$src/config.h"
  local extra=()
  [ "$poison" = 1 ] && extra=("${WRAP[@]}" "$BUGDIR/poison-fp.c")
  gcc -O0 "${TFLAGS[@]}" "${extra[@]}" -o "tcc-$label" "$src/tcc.c" 2> "build-$label.log" \
    || { tail -20 "build-$label.log"; die "build of tcc-$label failed"; }
  [ -x "tcc-$label" ] || die "no tcc-$label produced"
}
build_variant buggy-clean  0 0
build_variant buggy-poison 0 1
build_variant fixed-clean  1 0
build_variant fixed-poison 1 1
loud "0013 present in the fixed trees:"
grep -c 'tokc.tab' src-fixed-poison/tccpp.c | sed 's/^/    tokc.tab writes in tccpp.c: /'
grep -q 'tokc.tab' src-buggy-poison/tccpp.c \
  && die "the buggy tree already has 0013's integer path -- patch selection is wrong"
loud "and absent in the buggy trees (parse still via ldexp/strtod)"

banner "4/5 -- COMPILE the float/double battery with each variant and compare .data"
# Under ABLATE=1 the 'fixed + poison' column is pointed at the BUGGY+poison
# compiler; the named 'THE FIX' assertion below must then fire (it emits zeros).
FIXPOISON=./tcc-fixed-poison
if [ "${ABLATE:-0}" = 1 ]; then
  loud "ABLATE=1: 'fixed+poison' is pointed at the BUGGY compiler; the FIX"
  loud "          assertion MUST fail (a 0013-less parser emits 0.0 under poison)."
  FIXPOISON=./tcc-buggy-poison
fi

# name:kind:C-literal -- a spread of exact/inexact, hex/decimal, float/double,
# including the historical killers (2^53, log10_2 = gcc real.c's M_LOG10_2) and
# a large hex float near the overflow edge.
battery=(
  "f_2p5:float:2.5f"
  "f_tenth:float:0.1f"
  "d_2p5:double:2.5"
  "d_hex8:double:0x1p3"
  "d_1e6:double:1e6"
  "d_2pow53:double:9007199254740992.0"
  "d_log10_2:double:0.30102999566398119521"
  "d_pi:double:3.14159265358979323846"
  "d_hex1023:double:0x1p1023"
)
emit_data () { # <tcc> <c-file> -> hex of the leading <size> bytes of .data
  local tcc="$1" cfile="$2" size="$3"
  "$tcc" -c -o probe.o "$cfile" 2>/dev/null || die "$tcc failed to compile $cfile"
  "$OBJCOPY" -O binary --only-section=.data probe.o probe.bin 2>/dev/null
  [ -s probe.bin ] || die "$tcc emitted an empty .data for $cfile"
  od -An -v -tx1 probe.bin | tr -d ' \n' | cut -c1-$((size * 2))
}
printf "    %-11s %-4s %-18s | %-16s %-16s %-16s %-16s\n" LITERAL KIND EXPECTED buggy+clean fixed+clean fixed+poison buggy+poison
fail=0
for entry in "${battery[@]}"; do
  IFS=: read -r name kind lit <<<"$entry"
  [ "$kind" = float ] && size=4 || size=8
  exp=$(python3 "$BUGDIR/ieee.py" "$kind" "$lit")
  echo "$kind v = $lit;" > "$name.c"
  bc=$(emit_data ./tcc-buggy-clean  "$name.c" "$size")
  fc=$(emit_data ./tcc-fixed-clean  "$name.c" "$size")
  fp=$(emit_data "$FIXPOISON"       "$name.c" "$size")
  bp=$(emit_data ./tcc-buggy-poison "$name.c" "$size")
  zero=$(printf '00%.0s' $(seq 1 "$size"))
  printf "    %-11s %-4s %-18s | %-16s %-16s %-16s %-16s\n" "$lit" "$kind" "$exp" "$bc" "$fc" "$fp" "$bp"
  # buggy+clean and fixed+clean must both equal the conforming reference
  [ "$bc" = "$exp" ] || { loud "!! buggy+clean wrong for $lit: $bc != $exp"; fail=1; }
  [ "$fc" = "$exp" ] || { loud "!! fixed+clean wrong for $lit (0013 regressed a normal build): $fc != $exp"; fail=1; }
  # THE BUG: the unpatched parser under a broken libc emits an all-zero constant
  [ "$bp" = "$zero" ] || { loud "!! expected buggy+poison to be all-zero for $lit, got $bp"; fail=1; }
  # THE FIX (the ablation target): 0013 keeps it correct under the same poison
  [ "$fp" = "$exp" ] || die "THE FIX FAILED for $lit: fixed+poison emitted $fp, expected the \
correctly-rounded $exp (if ABLATE=1 this is the reproducer correctly going red)"
done
[ "$fail" = 0 ] || die "one or more battery expectations failed (see !! lines above)"

banner "5/5 -- VERDICT"
cat <<'EOF'

  The fork's literal parser converts through the linked libc (ldexp/strtod).
  With a broken-FP libc interposed (a return-0 ldexp, exactly mes-libc's stub):

    unpatched (0011+0012)        -> every float/double literal becomes 0.0
    + patch 0013 (integer parse) -> every literal is correct, byte-for-byte

  and 0013 changes nothing when the libc is healthy (fixed+clean == buggy+clean
  == the CPython-computed IEEE-754 reference).  So patch 0013 severs the
  compiler's dependence on a correct downstream FP libc -- the durable cure for
  the bug17/bug20-class self-poisoning of the arm bootstrap.
EOF
loud "PASS: patch 0013 verified -- integer-only FP-literal parsing survives a broken libc"
