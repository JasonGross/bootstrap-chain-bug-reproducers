#!/usr/bin/env bash
# mes-arm-getdents64: GNU Mes 0.27.1 include/linux/arm/syscall.h defines
# SYS_getdents64 as 0xdc (220) -- the x86 number.  On arm EABI, 220 is
# madvise; getdents64 is 217 (0xd9).
# GREEN == (A) the header value mismatches the kernel's own arm syscall table,
# (B) behaviorally, syscall(220) on a directory fd does not read dirents while
# syscall(217) does (static arm binary under qemu-user), and (C) the fix patch
# 0004 -- vendored beside this script, sha256-pinned to the exact attached
# bytes -- applies to a pristine git-tracked mes-0.27.1 with strict `git am`
# AND GNU `patch`, changing exactly one line (0xdc->0xd9), while two synthetic
# corruptions (a bad hunk count and a bad context line) are REJECTED by both
# tools.  PART C is the check whose absence let a malformed companion patch
# (the sibling reproducer 04's long-double 0012) reach a mailing list: it makes
# green mean "applied", not "ran".
cd "$(dirname "$0")"
. ../common.sh
BUGDIR=$PWD                 # absolute -- PART C feeds the appliers absolute paths

mkdir -p work
fetch_mes work
MES=work/mes-0.27.1
HDR=$MES/include/linux/arm/syscall.h

banner "PART A -- the header vs. the kernel's arm syscall table"
loud "mes-0.27.1/include/linux/arm/syscall.h:"
grep -n 'SYS_getdents' "$HDR"
mes_val=$(( $(grep -E '#define[[:space:]]+SYS_getdents64' "$HDR" | awk '{print $3}') ))
loud "mes SYS_getdents64 = $mes_val"

loud "the header's OWN cited authority (see its Commentary block):"
grep -n 'syscall.tbl' "$HDR" | head -2
TBL_URL=https://raw.githubusercontent.com/torvalds/linux/v4.19/arch/arm/tools/syscall.tbl
curl -fsSL --retry 5 -o work/syscall.tbl "$TBL_URL"
loud "linux v4.19 arch/arm/tools/syscall.tbl:"
grep -E '^(217|220)[[:space:]]' work/syscall.tbl
true_getdents64=$(awk '$3 == "getdents64" && $2 == "common" {print $1}' work/syscall.tbl)
arm_madvise=$(awk '$3 == "madvise" && $2 == "common" {print $1}' work/syscall.tbl)

[ "$true_getdents64" = 217 ] || die "sanity: kernel table getdents64 != 217?"
[ "$arm_madvise" = 220 ] || die "sanity: kernel table madvise != 220?"
[ "$mes_val" = 220 ] || die "mes header no longer says 220 -- bug gone?"
loud "MISMATCH CONFIRMED: mes says getdents64=$mes_val; the arm kernel says"
loud "getdents64=$true_getdents64 and $arm_madvise=madvise.  (220 is getdents64 on x86/i386 --"
loud "the arm header inherited the x86 number.)"

if [ -f /usr/arm-linux-gnueabihf/include/asm/unistd-common.h ]; then
  loud "corroboration from the arm glibc kernel headers on this machine:"
  grep -E '__NR_(getdents64|madvise) ' /usr/arm-linux-gnueabihf/include/asm/unistd-common.h || true
fi

banner "PART B -- behavioral: run both numbers on a directory fd (arm, qemu-user)"
command -v arm-linux-gnueabihf-gcc >/dev/null || die "need gcc-arm-linux-gnueabihf"
command -v qemu-arm-static >/dev/null || die "need qemu-user-static"
arm-linux-gnueabihf-gcc -O2 -static -include "$HDR" getdents-demo.c -o work/getdents-demo
cd work && qemu-arm-static ./getdents-demo
cd ..

# ---------------------------------------------------------------------------
banner "PART C -- the fix patch applies the maintainer's way (git am + GNU patch)"
# ---------------------------------------------------------------------------
# PART A/B prove the bug.  This leg proves the *attached fix* is the one that
# repairs it, run the way the recipient runs it.  It is the leg reproducer 03
# was missing: patch 0004 (the getdents64 fix, vendored beside this script) had
# only ever been applied by hand in a scratch directory.  The sibling reproducer
# `04-tcc-mes-arm-ldouble-zero` carries an erratum for exactly this failure
# class -- a malformed companion patch that went out with nothing having ever
# run it through `git am`.  A green here means the patch APPLIED, not merely
# that a script ran.
command -v git   >/dev/null || die "need git"
command -v patch >/dev/null || die "need GNU patch"

PATCH=$BUGDIR/patches/0004-mes-arm-getdents64-syscall-number.patch
PATCH_SHA=38d4697d5b7d8096129953f0731882073d239b5d713e5e256fc855377c7482b9
loud "the vendored patch is the exact attached bytes (sha256 pinned):"
echo "$PATCH_SHA  $PATCH" | sha256sum -c - \
  || die "vendored 0004 drifted from the pinned attachment"

# mes ships as a release tarball, so `git am` (which needs history) applies onto
# a git repo built *around* the pinned bytes -- not a re-export that could differ
# from what a maintainer starts with.  Each apply gets its OWN freshly-extracted
# tree: no copying of a live `.git` (a `cp -a` races an auto-gc repack), and
# gc.auto=0 so no background repack can race the apply either.  This leg is about
# correctness, not speed.
fresh_mes () {             # fresh_mes <dir> : pristine git-tracked mes-0.27.1 at <dir>/mes-0.27.1
  local d="$1" t
  rm -rf "$d"; mkdir -p "$d"
  tar -xzf "$BUGDIR/work/mes-0.27.1.tar.gz" -C "$d"
  t="$d/mes-0.27.1"
  git -C "$t" -c init.defaultBranch=main init -q
  git -C "$t" config gc.auto 0           # no background repack to race the apply
  git -C "$t" config user.name  reproducer
  git -C "$t" config user.email reproducer@invalid
  git -C "$t" add -A
  git -C "$t" commit -q -m "pristine mes-0.27.1 (pinned release tarball)"
  [ -z "$(git -C "$t" status --porcelain)" ] || die "$d is not pristine"
  grep -q 'SYS_getdents64 0xdc' "$t/include/linux/arm/syscall.h" \
    || die "pre-image is not 0xdc in $d -- the apply legs would be vacuous"
}
NUMSTAT=$(printf '1\t1\tinclude/linux/arm/syscall.h')   # 1 file, 1 ins, 1 del

banner "PART C.1 -- strict git am of the exact bytes (the maintainer path)"
fresh_mes work/am-good
git -C work/am-good/mes-0.27.1 am "$PATCH"
git -C work/am-good/mes-0.27.1 log --oneline -1
stat=$(git -C work/am-good/mes-0.27.1 diff --numstat HEAD~1 HEAD)
loud "git am numstat: $stat"
[ "$stat" = "$NUMSTAT" ] || die "git am: expected 1 file / 1 insertion / 1 deletion, got: $stat"
grep -q 'SYS_getdents64 0xd9' work/am-good/mes-0.27.1/include/linux/arm/syscall.h \
  || die "header did not flip to 0xd9 after git am"
if grep -q 'SYS_getdents64 0xdc' work/am-good/mes-0.27.1/include/linux/arm/syscall.h; then
  die "getdents64 is still 0xdc after git am"
fi
loud "git am: applied; getdents64 0xdc -> 0xd9; exactly one insertion and one deletion"

banner "PART C.2 -- and GNU patch -p1 (a second, independent applier)"
fresh_mes work/patch-good
( cd work/patch-good/mes-0.27.1 && patch -p1 --batch < "$PATCH" )
pstat=$(git -C work/patch-good/mes-0.27.1 diff --numstat)
loud "GNU patch numstat: $pstat"
[ "$pstat" = "$NUMSTAT" ] || die "GNU patch: expected 1 file / 1 insertion / 1 deletion, got: $pstat"
grep -q 'SYS_getdents64 0xd9' work/patch-good/mes-0.27.1/include/linux/arm/syscall.h \
  || die "header did not flip to 0xd9 after GNU patch"
loud "GNU patch: same one-line change, same result as git am"

banner "PART C.3 -- ablation: corrupt the patch two ways; both appliers must REJECT"
loud "(synthetic corruptions of the vendored patch -- there is no real malformed"
loud " 0004; this proves the leg would NOTICE if the bytes were wrong, the check"
loud " whose absence let a malformed companion patch reach a mailing list.  The"
loud " trees are pristine and the patch paths absolute, so a rejection is a"
loud " CONTENT rejection, never a file-not-found that would pass for free.)"

# neg1: a hunk header that under-counts its body -- the malformed 0012 patch's class.
sed 's/@@ -106,7 +106,7 @@/@@ -106,7 +106,5 @@/' "$PATCH" > work/neg1-badcount.patch
cmp -s "$PATCH" work/neg1-badcount.patch && die "neg1 mutation was a no-op"
NEG1=$BUGDIR/work/neg1-badcount.patch
# neg2: valid counts, but the removed line targets a value absent from the file,
# so the hunk cannot match -- a content mismatch, not a malformed header.
sed 's/^-#define SYS_getdents64 0xdc$/-#define SYS_getdents64 0xAB/' "$PATCH" > work/neg2-badcontext.patch
cmp -s "$PATCH" work/neg2-badcontext.patch && die "neg2 mutation was a no-op"
NEG2=$BUGDIR/work/neg2-badcontext.patch

reject_git_am () {         # reject_git_am <dir> <patch> <needle>
  local dir="$1" pat="$2" needle="$3" out rc
  fresh_mes "$dir"
  set +e
  out=$(git -C "$dir/mes-0.27.1" am "$pat" 2>&1); rc=$?
  set -e
  git -C "$dir/mes-0.27.1" am --abort 2>/dev/null || true
  echo "$out" | sed 's/^/    /'
  [ "$rc" != 0 ] || die "git am ACCEPTED a corrupt patch ($pat)"
  echo "$out" | grep -qF "$needle" || die "git am rejected $pat, but not with '$needle'"
}
reject_patch () {          # reject_patch <dir> <patch> <needle>
  local dir="$1" pat="$2" needle="$3" out rc
  fresh_mes "$dir"
  set +e
  out=$( cd "$dir/mes-0.27.1" && patch -p1 --batch < "$pat" 2>&1 ); rc=$?
  set -e
  echo "$out" | sed 's/^/    /'
  [ "$rc" != 0 ] || die "GNU patch ACCEPTED a corrupt patch ($pat)"
  echo "$out" | grep -qF "$needle" || die "GNU patch rejected $pat, but not with '$needle'"
}

loud "neg1 (bad hunk count) -- git am must say 'corrupt patch':"
reject_git_am work/neg1-am    "$NEG1" "corrupt patch"
loud "neg1 (bad hunk count) -- GNU patch must say 'malformed patch':"
reject_patch  work/neg1-patch "$NEG1" "malformed patch"
loud "neg2 (bad context)    -- git am must say 'does not apply':"
reject_git_am work/neg2-am    "$NEG2" "does not apply"
loud "neg2 (bad context)    -- GNU patch must say 'FAILED':"
reject_patch  work/neg2-patch "$NEG2" "FAILED"
loud "both appliers reject both corruptions, each with its own diagnostic"

banner "VERDICT"
loud "BUG REPRODUCED: mes' arm SYS_getdents64 (0xdc=220) is the x86 number and"
loud "lands on arm madvise; the correct arm number is 217 (0xd9).  Any mes-libc"
loud "readdir on arm EABI fails.  This first bit the arm bootstrap when a"
loud "mes-linked tool listed a directory."
loud "FIX VERIFIED: patch 0004 applies to the pinned mes-0.27.1 with strict"
loud "'git am' AND GNU 'patch', flips 0xdc->0xd9 in exactly one line, and both"
loud "appliers reject a bad-count and a bad-context corruption of it."
echo "PASS: mes-arm-getdents64 reproduced; fix patch 0004 applies via git am + GNU patch"
