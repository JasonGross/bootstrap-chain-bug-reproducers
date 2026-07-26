#!/usr/bin/env bash
# tcc-riscv64-absolute-relocs: tinycc's riscv64 linker implements the
# PC-relative HI20/LO12 relocations but NOT their absolute siblings
#   R_RISCV_HI20 (26 = 0x1a), R_RISCV_LO12_I (27 = 0x1b), R_RISCV_LO12_S (28 = 0x1c).
# GCC emits those routinely for riscv64 (they are what a plain non-PIC
# lui+addi / lui+sw pair uses), so ANY attempt to link a GCC-built riscv64
# static libc with tcc walks into them.
#
# GREEN == all four legs behave as reported, on ONE musl built here from
# pinned source by GCC, with ONE four-line trigger:
#
#   A   tinycc mob @ pin, unpatched -> link FAILS, "Unknown relocation type
#                                      for got: 26/27/28", no binary at all
#   A'  tinycc mob @ pin + patch    -> link clean, program prints correctly
#   B   chain-vintage fork,unpatched-> link SUCCEEDS (rc=0) with only "FIXME:
#                                      handle reloc type 1a/1b/1c" notes, and
#                                      the binary it produces prints NOTHING
#   B'  chain-vintage fork + patch  -> link clean, program prints correctly
#
# A/A' is the upstream report.  B/B' is the silent-failure mode, which is
# fork-only -- mob already turns the unhandled relocation into a hard error.
# B' is what proves B's silence is caused by these three relocations and not
# by the harness: same compiler, same link line, same libc, +20 lines.
cd "$(dirname "$0")"
. ../common.sh
BUGDIR=$PWD

command -v qemu-riscv64-static >/dev/null || die "need qemu-user-static"
command -v python3             >/dev/null || die "need python3"
RVGCC=""
for c in riscv64-linux-gnu-gcc riscv64-linux-gnu-gcc-14 riscv64-linux-gnu-gcc-13 \
         riscv64-linux-gnu-gcc-12; do
  if command -v "$c" >/dev/null; then RVGCC=$c; break; fi
done
[ -n "$RVGCC" ] || die "need gcc-riscv64-linux-gnu"
RVAR=riscv64-linux-gnu-ar
RVREADELF=riscv64-linux-gnu-readelf

MUSL_VER=1.2.5
MUSL_SHA=a9a118bbe84d8764da0ea0d28b3ab3fae8477fc7e4085d90102b8596fc7c75e4
MUSL_URLS="https://musl.libc.org/releases/musl-$MUSL_VER.tar.gz
https://sources.buildroot.net/musl/musl-$MUSL_VER.tar.gz"

# tinycc mob.  repo.or.cz has gone down on us mid-session; the GitHub mirror
# is the fallback and the commit hash is the integrity check either way.
TCC_URLS="https://repo.or.cz/tinycc.git https://github.com/TinyCC/tinycc.git"
MOB_PIN=85ba3ae8f1e22044255d54c28be04e5fc3e88ae0     # mob, 2026-07-24

# The chain vintage: janneke's mes-lineage fork, tcc-0.9.26-1157-gdd46e018,
# the riscv64 tcc the Guix/Mes riscv64 bootstrap actually runs.
CHAIN_TARBALL_URL=https://lilypond.org/janneke/tcc/tcc-0.9.26-1157-gdd46e018.tar.gz
CHAIN_TARBALL_SHA=3748c0aacd1e7b3805de09f28a4ef396392b2c838f78c59d23bfd9d68312232e
CHAIN_GIT_URL=https://gitlab.com/janneke/tinycc            # fallback
CHAIN_COMMIT=dd46e018f64cbd67d907ce6ea91923e627206363
CHAIN_DIR=tcc-0.9.26-1157-gdd46e018

EXPECTED="HELLO from a tcc-linked musl binary"
TRIGGER_SHA=b99be9cc89d4d5de1a26f9ad0f97d9932f6c157592c2e6bc3f94bc22b93294a2
STUBS_SHA=f41e0828b92a4619c808e5b547ff1034b84f3a94ca522095413f34836e150205

mkdir -p work
W=$BUGDIR/work

# fetch_any <sha256> <dest> <url> [url...]
fetch_any () {
  local sha="$1" out="$2"; shift 2
  if [ -f "$out" ] && echo "$sha  $out" | sha256sum -c --quiet - 2>/dev/null; then
    loud "already fetched: $out"; return 0
  fi
  local u
  for u in "$@"; do
    loud "fetching $u"
    if curl -fsSL --retry 3 --retry-delay 5 --max-time 900 -o "$out" "$u"; then
      if echo "$sha  $out" | sha256sum -c --quiet -; then return 0; fi
      die "sha256 mismatch for $out from $u (pinned $sha)"
    fi
    loud "  ...unreachable, trying the next mirror"
  done
  die "every mirror for $out failed"
}

# ---------------------------------------------------------------------------
banner "0/6 -- THE TRIGGER (byte-exact, and deliberately confound-free)"
# An earlier demo of this defect used a program that ALSO carried a tcc
# codegen bug (struct return), so it proved nothing.  This one is four lines
# of printf.  Guard both properties so the file cannot silently drift.
cat hello_reloc.c
echo "$TRIGGER_SHA  hello_reloc.c" | sha256sum -c - \
  || die "hello_reloc.c is not the byte-exact trigger"
echo "$STUBS_SHA  tf-stubs.c" | sha256sum -c - || die "tf-stubs.c changed"
CODE=$(grep -vE '^[[:space:]]*(/\*|\*)' hello_reloc.c)
if printf '%s\n' "$CODE" | grep -qw 'struct'; then
  die "the trigger grew a struct -- it must stay free of the struct-return
codegen confound that made an earlier demonstration of this bug worthless"
fi
loud "trigger: 4 lines, printf only, no struct return, no #include"
echo
loud "tf-stubs.c supplies musl's quad-float printf helpers (__addtf3 etc)."
loud "riscv64 long double is IEEE binary128 and musl's vfprintf references the"
loud "libgcc soft-float helpers.  We cannot feed tcc gcc's libgcc.a here -- it"
loud "is itself full of the relocations under test -- so the helpers are"
loud "stubbed to abort().  They are unreachable for a %s-only printf; the"
loud "stubs exist so an UNDEFINED-SYMBOL link error can never be mistaken for"
loud "the relocation failure being demonstrated."

# ---------------------------------------------------------------------------
banner "1/6 -- PREMISE RE-CHECK: does upstream mob still lack these three?"
if [ ! -d "$W/tinycc/.git" ]; then
  ok=""
  for u in $TCC_URLS; do
    loud "cloning $u (branch mob)"
    rm -rf "$W/tinycc"
    if git clone -q --single-branch --branch mob "$u" "$W/tinycc" 2>/dev/null
    then ok=1; break; fi
    loud "  ...unreachable, trying the next mirror"
  done
  [ -n "$ok" ] || die "could not fetch tinycc from any mirror"
fi
git -C "$W/tinycc" fetch -q origin mob 2>/dev/null || true
TIP=$(git -C "$W/tinycc" rev-parse origin/mob)
loud "mob tip today : $(git -C "$W/tinycc" log -1 --format='%H %ci %s' "$TIP")"
git -C "$W/tinycc" cat-file -e "$MOB_PIN" || die "pinned mob commit not found"
loud "pinned commit : $(git -C "$W/tinycc" log -1 --format='%H %ci %s' "$MOB_PIN")"

git -C "$W/tinycc" show "$TIP:riscv64-link.c" > "$W/mob-tip-riscv64-link.c"
for t in R_RISCV_HI20 R_RISCV_LO12_I R_RISCV_LO12_S; do
  if grep -q "case $t:" "$W/mob-tip-riscv64-link.c"; then
    die "mob tip now has 'case $t:' -- UPSTREAM HAS FIXED THIS. The report's
premise no longer holds; re-read the report before sending anything."
  fi
done
loud "mob tip riscv64-link.c: no case for HI20 / LO12_I / LO12_S -- gap is LIVE"
loud "the fall-through they land in is still there:"
grep -n -A2 '^    default:' "$W/mob-tip-riscv64-link.c" | sed 's/^/       /' || true
loud "and the three ARE named in tcc's own elf.h, so this is not a naming gap:"
git -C "$W/tinycc" show "$TIP:elf.h" > "$W/mob-tip-elf.h"
grep -E '^#define R_RISCV_(HI20|LO12_I|LO12_S)' "$W/mob-tip-elf.h" \
  | sed 's/^/       /' || true

# ---------------------------------------------------------------------------
banner "2/6 -- BUILD A GCC-BUILT riscv64 musl $MUSL_VER FROM PINNED SOURCE"
"$RVGCC" --version 2>&1 | head -1 || true
fetch_any "$MUSL_SHA" "$W/musl-$MUSL_VER.tar.gz" $MUSL_URLS
[ -d "$W/musl-$MUSL_VER" ] || tar -xzf "$W/musl-$MUSL_VER.tar.gz" -C "$W"
SR=$W/sysroot
if [ ! -f "$SR/lib/libc.a" ]; then
  rm -rf "$W/mbuild"; mkdir -p "$W/mbuild"
  # -fno-pic is load-bearing.  Debian/Ubuntu GCC defaults to PIE, and musl's
  # configure then sets AOBJS = $(LOBJS): libc.a would be built from the PIC
  # objects, which use GOT_HI20/PCREL and carry NONE of the absolute
  # relocations this reproducer is about.  Asserted here and again in step 3.
  ( cd "$W/mbuild" && "$W/musl-$MUSL_VER/configure" \
        --target=riscv64-linux-gnu --prefix="$SR" \
        CROSS_COMPILE=riscv64-linux-gnu- CC="$RVGCC" \
        CFLAGS="-fno-pic -fno-pie" ) > "$W/musl-configure.log" 2>&1 \
    || { tail -20 "$W/musl-configure.log"; die "musl configure failed"; }
  if grep -q '^AOBJS = \$(LOBJS)' "$W/mbuild/config.mak"; then
    die "musl configure decided the compiler is PIC by default; libc.a would
carry no absolute relocations and this reproducer would be vacuous"
  fi
  ( cd "$W/mbuild" && make -j"$(nproc)" && make install ) \
      > "$W/musl-build.log" 2>&1 \
    || { tail -30 "$W/musl-build.log"; die "musl build failed"; }
fi
loud "sysroot: $SR"
ls -l "$SR/lib/crt1.o" "$SR/lib/libc.a" "$SR/lib/libc.so" | sed 's/^/    /'

# musl's libc.so IS the musl dynamic loader.  tcc bakes the glibc-flavoured
# PT_INTERP name into a non-static riscv64 executable, so point that path at
# it for qemu-user.  (Non-static because the chain-vintage fork's -static
# path NULL-derefs in tidy_section_headers -- an unrelated fork bug, see
# README.  Everything below is linked -nostdlib against libc.a BY PATH, so
# all of libc is statically linked in regardless of the PT_INTERP.)
QROOT=$W/qroot; mkdir -p "$QROOT/lib"
cp -f "$SR/lib/libc.so" "$QROOT/lib/ld-linux-riscv64-lp64d.so.1"

# ---------------------------------------------------------------------------
banner "3/6 -- CENSUS: how much of that libc GCC put these relocations in"
rm -rf "$W/census"; mkdir -p "$W/census"
( cd "$W/census" && "$RVAR" x "$SR/lib/libc.a" )
NOBJ=$(find "$W/census" -type f | wc -l)
( cd "$W/census" && "$RVREADELF" -r ./* 2>/dev/null ) > "$W/census.rel" || true
declare -A CNT
for t in R_RISCV_HI20 R_RISCV_LO12_I R_RISCV_LO12_S; do
  CNT[$t]=$(grep -cw "$t" "$W/census.rel" || true)
  printf "    %-18s %6d\n" "$t" "${CNT[$t]}"
  [ "${CNT[$t]}" -gt 0 ] \
    || die "$t does not occur in this libc.a at all -- the musl build went PIC
(or the toolchain changed); the reproducer would be vacuous"
done
AFF=0
for o in "$W/census"/*; do
  hit=$("$RVREADELF" -r "$o" 2>/dev/null \
          | grep -cEw 'R_RISCV_HI20|R_RISCV_LO12_I|R_RISCV_LO12_S' || true)
  [ "$hit" -gt 0 ] && AFF=$((AFF+1)) || true
done
loud "$AFF of $NOBJ objects in libc.a carry at least one of the three"
loud "(this is an ordinary static libc -- no exotic flags, no hand-written asm)"

# ---------------------------------------------------------------------------
banner "4/6 -- BUILD FOUR riscv64-TARGETING tccs (2 compilers x patched/not)"
build_cross () {   # $1 = source dir, $2 = label
  ( cd "$1" && { [ -f config.mak ] || ./configure; } \
             && make riscv64-tcc -j"$(nproc)" ) > "$W/build-$2.log" 2>&1 \
    || { tail -25 "$W/build-$2.log"; die "build of $2 failed"; }
  [ -x "$1/riscv64-tcc" ] || die "$2 produced no riscv64-tcc"
  loud "built $2: $1/riscv64-tcc"
}

# --- mob @ pin, and the same tree with the patch --------------------------
rm -rf "$W/mob" "$W/mob-patched"
mkdir -p "$W/mob"
git -C "$W/tinycc" archive "$MOB_PIN" | tar -x -C "$W/mob"
cp -a "$W/mob" "$W/mob-patched"
python3 "$BUGDIR/apply-abs-relocs.py" "$W/mob-patched/riscv64-link.c" \
  || die "patch did not apply to mob"
banner "    THE PATCH (this is the whole fix)"
diff -u "$W/mob/riscv64-link.c" "$W/mob-patched/riscv64-link.c" || true
build_cross "$W/mob"         mob
build_cross "$W/mob-patched" mob-patched

# --- chain vintage, and the same tree with the patch ----------------------
if [ ! -d "$W/$CHAIN_DIR" ]; then
  got=""
  if curl -fsSL --retry 3 --max-time 900 -o "$W/chain.tar.gz" \
        "$CHAIN_TARBALL_URL" \
     && echo "$CHAIN_TARBALL_SHA  $W/chain.tar.gz" | sha256sum -c --quiet -
  then
    tar -xzf "$W/chain.tar.gz" -C "$W"; got=tarball
  else
    loud "lilypond.org unreachable or changed; falling back to the git repo"
    rm -rf "$W/chain-git"
    git clone -q "$CHAIN_GIT_URL" "$W/chain-git" \
      || die "no source for the chain-vintage tcc"
    git -C "$W/chain-git" cat-file -e "$CHAIN_COMMIT" \
      || die "$CHAIN_COMMIT absent from $CHAIN_GIT_URL"
    git -C "$W/chain-git" checkout -q "$CHAIN_COMMIT"
    mv "$W/chain-git" "$W/$CHAIN_DIR"; got=git
  fi
  loud "chain-vintage source obtained via: $got"
fi
[ -f "$W/$CHAIN_DIR/riscv64-link.c" ] || die "chain source has no riscv64-link.c"
loud "chain vintage: tcc-0.9.26-1157-gdd46e018 (VERSION $(cat "$W/$CHAIN_DIR/VERSION"))"
if [ ! -f "$W/$CHAIN_DIR/config.mak" ]; then
  ( cd "$W/$CHAIN_DIR" && ./configure ) > "$W/chain-configure.log" 2>&1 \
    || { tail -20 "$W/chain-configure.log"; die "chain configure failed"; }
  # This fork gates its 64-bit ELF typedefs on HAVE_LONG_LONG (a mes-libc
  # accommodation); the bootstrap defines it, the stock configure does not,
  # and without it the riscv64 cross target will not compile at all.
  if grep -q HAVE_LONG_LONG "$W/$CHAIN_DIR/config.mak"; then
    die "config.mak already mentions HAVE_LONG_LONG -- re-read this step"
  fi
  echo 'CFLAGS+=-DHAVE_LONG_LONG=1' >> "$W/$CHAIN_DIR/config.mak"
  grep -q '^CFLAGS+=-DHAVE_LONG_LONG=1' "$W/$CHAIN_DIR/config.mak" \
    || die "appending HAVE_LONG_LONG to config.mak did not take"
fi
rm -rf "$W/chain-patched"; cp -a "$W/$CHAIN_DIR" "$W/chain-patched"
rm -f "$W/chain-patched"/*.o "$W/chain-patched/riscv64-tcc"
python3 "$BUGDIR/apply-abs-relocs.py" "$W/chain-patched/riscv64-link.c" \
  || die "patch did not apply to the chain vintage"
build_cross "$W/$CHAIN_DIR"    chain
build_cross "$W/chain-patched" chain-patched

# ---------------------------------------------------------------------------
banner "5/6 -- LINK AND RUN: one trigger, one libc, four compilers"
cp -f hello_reloc.c tf-stubs.c "$W/"

do_link () {   # $1 = tcc, $2 = tag
  local tcc="$1" tag="$2"
  rm -f "$W/$tag.bin"
  set +e
  ( cd "$W" && "$tcc" -B "$SR/lib" -I "$SR/include" -nostdlib \
        -o "$tag.bin" "$SR/lib/crt1.o" "$SR/lib/crti.o" \
        hello_reloc.c tf-stubs.c "$SR/lib/crtn.o" "$SR/lib/libc.a" ) \
      > "$W/$tag.link.out" 2> "$W/$tag.link.err"
  echo $? > "$W/$tag.rc"
  set -e
}
do_run () {    # $1 = tag
  local tag="$1"
  set +e
  qemu-riscv64-static -L "$QROOT" "$W/$tag.bin" \
      > "$W/$tag.run.out" 2> "$W/$tag.run.err"
  echo $? > "$W/$tag.runrc"
  set -e
}
report_link () {
  local tag="$1"
  echo "    link exit status : $(cat "$W/$tag.rc")"
  echo "    stderr lines     : $(wc -l < "$W/$tag.link.err")"
  echo "    binary produced  : $([ -f "$W/$tag.bin" ] && echo yes || echo NO)"
  if [ -s "$W/$tag.link.err" ]; then
    echo "    first 4 diagnostics:"
    head -4 "$W/$tag.link.err" | sed 's/^/      /'
    echo "    diagnostic tally by relocation:"
    grep -oE 'got: [0-9]+|reloc type [0-9a-f]+' "$W/$tag.link.err" \
      | sort | uniq -c | sed 's/^/      /' || true
  fi
}

# ---- A: mob, unpatched ---------------------------------------------------
banner "    LEG A -- tinycc mob @ ${MOB_PIN:0:12}, UNPATCHED  (the upstream bug)"
do_link "$W/mob/riscv64-tcc" A
report_link A
[ "$(cat "$W/A.rc")" -ne 0 ] \
  || die "LEG A: mob linked successfully -- expected a hard error"
[ ! -f "$W/A.bin" ] || die "LEG A: mob produced a binary -- expected none"
for n in 26:R_RISCV_HI20 27:R_RISCV_LO12_I 28:R_RISCV_LO12_S; do
  grep -q "Unknown relocation type for got: ${n%%:*}" "$W/A.link.err" \
    || die "LEG A: no 'Unknown relocation type for got: ${n%%:*}' (${n##*:})"
done
loud "LEG A REPRODUCED: mob cannot link a GCC-built riscv64 musl at all, and"
loud "it names exactly the three missing relocations -- 26, 27 and 28."

# ---- A': mob + patch (the control) ---------------------------------------
banner "    LEG A' -- the SAME mob tree + the 20-line patch  (CONTROL)"
do_link "$W/mob-patched/riscv64-tcc" Ap
report_link Ap
[ "$(cat "$W/Ap.rc")" -eq 0 ] || die "LEG A': patched mob failed to link"
if [ -s "$W/Ap.link.err" ]; then
  cat "$W/Ap.link.err"; die "LEG A': patched mob emitted diagnostics"
fi
[ -f "$W/Ap.bin" ] || die "LEG A': no binary"
do_run Ap
echo "    run exit status  : $(cat "$W/Ap.runrc")"
echo "    stdout           : [$(cat "$W/Ap.run.out")]"
[ "$(cat "$W/Ap.run.out")" = "$EXPECTED" ] \
  || die "LEG A': printed [$(cat "$W/Ap.run.out")], expected [$EXPECTED]"
[ "$(cat "$W/Ap.runrc")" -eq 0 ] || die "LEG A': program exit status not 0"
loud "LEG A' CONTROL PASSED: +20 lines and the identical link is clean and the"
loud "program prints correctly.  Nothing else changed."

# ---- B: chain vintage, unpatched (the SILENT failure) --------------------
banner "    LEG B -- chain-vintage fork, UNPATCHED  (the SILENT failure)"
do_link "$W/$CHAIN_DIR/riscv64-tcc" B
report_link B
[ "$(cat "$W/B.rc")" -eq 0 ] \
  || die "LEG B: link exit status $(cat "$W/B.rc"); the point of this leg is
that the link exits 0"
[ -f "$W/B.bin" ] || die "LEG B: no binary; the point of this leg is that a
plausible executable IS produced"
for t in 1a 1b 1c; do
  grep -q "FIXME: handle reloc type $t " "$W/B.link.err" \
    || die "LEG B: no 'FIXME: handle reloc type $t' (0x$t)"
done
loud "$(grep -c 'FIXME: handle reloc type' "$W/B.link.err") unhandled-relocation \
notices, exit status 0, $(stat -c%s "$W/B.bin")-byte executable produced."
do_run B
echo "    run exit status  : $(cat "$W/B.runrc")"
echo "    stdout           : [$(cat "$W/B.run.out")]"
echo "    stderr           : [$(head -c 200 "$W/B.run.err")]"
if [ -s "$W/B.run.out" ]; then
  die "LEG B: the binary printed something -- the silent-failure claim does
not hold on this build"
fi
loud "LEG B REPRODUCED: the link said OK, the binary exists, it prints NOTHING."

# ---- B': chain vintage + patch (the control for B) -----------------------
banner "    LEG B' -- the SAME fork tree + the 20-line patch  (CONTROL)"
do_link "$W/chain-patched/riscv64-tcc" Bp
report_link Bp
[ "$(cat "$W/Bp.rc")" -eq 0 ] || die "LEG B': patched fork failed to link"
if [ -s "$W/Bp.link.err" ]; then
  cat "$W/Bp.link.err"; die "LEG B': patched fork emitted diagnostics"
fi
do_run Bp
echo "    run exit status  : $(cat "$W/Bp.runrc")"
echo "    stdout           : [$(cat "$W/Bp.run.out")]"
[ "$(cat "$W/Bp.run.out")" = "$EXPECTED" ] \
  || die "LEG B': printed [$(cat "$W/Bp.run.out")], expected [$EXPECTED]"
[ "$(cat "$W/Bp.runrc")" -eq 0 ] || die "LEG B': program exit status not 0"
loud "LEG B' CONTROL PASSED: the same link line, same libc, same trigger --"
loud "with the three relocations handled it prints correctly.  So LEG B's"
loud "silence is caused by these relocations, not by the harness."

# ---------------------------------------------------------------------------
banner "6/6 -- VERDICT"
printf '    %-4s %-32s %-12s %-8s %s\n' LEG COMPILER LINK BINARY 'PROGRAM OUTPUT'
printf '    %-4s %-32s %-12s %-8s %s\n' A  "mob ${MOB_PIN:0:12} unpatched" \
       "rc=$(cat "$W/A.rc") FAIL" no "--"
printf '    %-4s %-32s %-12s %-8s %s\n' "A'" "mob ${MOB_PIN:0:12} + patch" \
       "rc=0 clean" yes "[$(cat "$W/Ap.run.out")]"
printf '    %-4s %-32s %-12s %-8s %s\n' B  "tcc-0.9.26-1157 unpatched" \
       "rc=0 +FIXME" yes "[]  (nothing)"
printf '    %-4s %-32s %-12s %-8s %s\n' "B'" "tcc-0.9.26-1157 + patch" \
       "rc=0 clean" yes "[$(cat "$W/Bp.run.out")]"
echo
loud "libc.a census: HI20=${CNT[R_RISCV_HI20]} LO12_I=${CNT[R_RISCV_LO12_I]} \
LO12_S=${CNT[R_RISCV_LO12_S]} across $AFF/$NOBJ objects"
loud "mob tip $(echo "$TIP" | cut -c1-12) still has no case for any of the three."
echo "PASS: tcc-riscv64-absolute-relocs reproduced (A, B) with both controls (A', B')"
