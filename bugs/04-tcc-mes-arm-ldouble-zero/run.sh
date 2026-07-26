#!/usr/bin/env bash
# tcc-mes-arm-ldouble-zero (nix-bootstrapping bug20): the janneke tinycc fork's
# `#if defined BOOTSTRAP && defined __arm__` VT_LDOUBLE branch of init_putv is
# an EMPTY block, so on ARM EABI (long double == double) EVERY long double
# constant materializes as 0.0.
# GREEN == a BOOTSTRAP+arm build of the fork's tcc emits all-zero bytes for
# `long double big = 1000000000.0L;` while arm-linux-gnueabihf-gcc (control)
# emits 0x41CDCD6500000000 -- AND the same tcc rebuilt with our patches
# 0011+0012 emits exactly the control's bytes.
#
# The fixed leg also verifies the *erratum* for report #3: the corrected 0012
# applies to the pinned fork with strict `git am`, which is the path a
# maintainer takes, while the version actually attached to the 2026-07-21 mail
# does not.
cd "$(dirname "$0")"
. ../common.sh
BUGDIR=$PWD

FORK_URL=https://gitlab.com/janneke/tinycc.git
FORK_COMMIT=ee75a10cd71bebf23cb23598a49ee3c160ef0fe8   # branch mes-0.25.0
FORK_BRANCH=mes-0.25.0
# The guard structure (including the empty VT_LDOUBLE store) was introduced by
# commit 50b5eaeda92d75984d56de4a12af8d4aa192a853
# ("bootstrappable: ARM: HAVE_FLOAT?", 2021-12-05).

command -v arm-linux-gnueabihf-gcc >/dev/null || die "need gcc-arm-linux-gnueabihf"
command -v qemu-arm-static >/dev/null || die "need qemu-user-static"

mkdir -p work
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

banner "THE ACCUSED CODE: init_putv, tccgen.c -- the empty VT_LDOUBLE store"
grep -n -B3 -A8 'XXX TODO: breaks on mescc/tcc-mes based build' work/tinycc/tccgen.c
loud "On ARM EABI sizeof(long double)==8==LDOUBLE_SIZE, so control enters this"
loud "EMPTY block and never reaches the working sizeof(double)==LDOUBLE_SIZE"
loud "fallback below it: the .data slot stays zero-filled."

banner "BUILD: cross-build the fork's tcc for arm with its arm bootstrap defines"
loud "(BOOTSTRAP=1 + TCC_TARGET_ARM/TCC_ARM_EABI/TCC_ARM_VFP + HAVE_FLOAT=1,"
loud " i.e. the defines the mes/tcc arm bootstrap uses for its boot rounds;"
loud " two DISJOINT valid-C shims are applied first -- see mescc-era-shims.py)"
python3 mescc-era-shims.py work/tinycc/arm-gen.c work/tinycc/tccgen.c
: > work/tinycc/config.h
arm-linux-gnueabihf-gcc -O1 -static -w -o work/tcc-arm-bootstrap \
  -D BOOTSTRAP=1 -D HAVE_FLOAT=1 -D HAVE_BITFIELD=1 -D HAVE_LONG_LONG=1 -D HAVE_SETJMP=1 \
  -D TCC_TARGET_ARM=1 -D TCC_ARM_EABI=1 -D TCC_ARM_VFP=1 -I work/tinycc \
  -D 'CONFIG_TCCDIR="/usr/lib/tcc"' -D 'TCC_VERSION="0.9.26"' -D ONE_SOURCE=1 \
  work/tinycc/tcc.c
file work/tcc-arm-bootstrap

banner "REPRODUCE: fork tcc (under qemu-arm) compiles ldconst.c"
cat ldconst.c
cp ldconst.c work/
( cd work && qemu-arm-static ./tcc-arm-bootstrap -c ldconst.c -o ldconst-tcc.o )
arm-linux-gnueabihf-objcopy -O binary --only-section=.data work/ldconst-tcc.o work/tcc-data.bin
loud "fork tcc .data:"
python3 check-data.py work/tcc-data.bin buggy

banner "CONTROL: arm-linux-gnueabihf-gcc compiles the same file"
arm-linux-gnueabihf-gcc -c work/ldconst.c -o work/ldconst-gcc.o
arm-linux-gnueabihf-objcopy -O binary --only-section=.data work/ldconst-gcc.o work/gcc-data.bin
loud "arm gcc .data:"
python3 check-data.py work/gcc-data.bin control

# ---------------------------------------------------------------------------
banner "FIX: the same tcc rebuilt with patches 0011 + 0012"
# ---------------------------------------------------------------------------
# A second, pristine checkout: the shims above have already edited the first
# work tree, and `git am` needs a clean one.
fresh_tree () {           # fresh_tree <dir> -- pristine copy of the pinned fork
  rm -rf "$1"
  cp -a work/tinycc "$1"
  git -C "$1" checkout -q -- .        # undo the shims applied to work/tinycc
  git -C "$1" config user.name  "reproducer"
  git -C "$1" config user.email "reproducer@invalid"
  [ -z "$(git -C "$1" status --porcelain)" ] || die "$1 is not pristine"
  [ "$(git -C "$1" rev-parse HEAD)" = "$FORK_COMMIT" ] || die "$1 is at the wrong commit"
}
fresh_tree work/tinycc-fixed

loud "strict 'git am' -- the maintainer path -- of 0011 then the CORRECTED 0012:"
git -C work/tinycc-fixed am "$BUGDIR/patches/0011-arm-init_putv-bit-copy-fp-constants-not-convert.patch"
git -C work/tinycc-fixed am "$BUGDIR/patches/0012-arm-init_putv-bit-copy-long-double-constants.patch"
git -C work/tinycc-fixed log --oneline -3

# The erratum's whole subject: the 0012 file ATTACHED to the sent mail has a
# hunk header declaring 12 new lines for a 14-line body, so the maintainer's
# `git am` of the series stops there.  Assert that, or the erratum would be a
# claim with nothing behind it.  (This doubles as the ablation: the check above
# demonstrably distinguishes a good patch from a corrupt one.)
loud "and the SUPERSEDED file, as actually attached to the 2026-07-21 mail:"
fresh_tree work/tinycc-super
git -C work/tinycc-super am "$BUGDIR/patches/0011-arm-init_putv-bit-copy-fp-constants-not-convert.patch" >/dev/null
set +e
git -C work/tinycc-super am "$BUGDIR/patches/0012-SUPERSEDED-as-sent.patch" > work/am-superseded.txt 2>&1
super_rc=$?
set -e
sed 's/^/    /' work/am-superseded.txt
git -C work/tinycc-super am --abort 2>/dev/null || true
[ "$super_rc" != 0 ] || die "the superseded 0012 applied cleanly -- the erratum has nothing to report"
grep -q "corrupt patch" work/am-superseded.txt \
  || die "expected 'corrupt patch' from git am on the superseded 0012"
# ...and, contrary to the erratum's current parenthetical, GNU patch rejects it
# too: the hunk header is malformed independently of the target file.
set +e
( cd work/tinycc-super && patch -p1 --batch < "$BUGDIR/patches/0012-SUPERSEDED-as-sent.patch" ) \
  > work/patch-superseded.txt 2>&1
patch_rc=$?
set -e
sed 's/^/    /' work/patch-superseded.txt
[ "$patch_rc" != 0 ] || die "GNU patch accepted the superseded 0012 -- re-check the erratum's wording"
loud "both 'git am' AND 'patch -p1' reject the superseded file"

loud "rebuilding the arm bootstrap tcc from the PATCHED tree"
python3 mescc-era-shims.py work/tinycc-fixed/arm-gen.c work/tinycc-fixed/tccgen.c
: > work/tinycc-fixed/config.h
arm-linux-gnueabihf-gcc -O1 -static -w -o work/tcc-arm-fixed \
  -D BOOTSTRAP=1 -D HAVE_FLOAT=1 -D HAVE_BITFIELD=1 -D HAVE_LONG_LONG=1 -D HAVE_SETJMP=1 \
  -D TCC_TARGET_ARM=1 -D TCC_ARM_EABI=1 -D TCC_ARM_VFP=1 -I work/tinycc-fixed \
  -D 'CONFIG_TCCDIR="/usr/lib/tcc"' -D 'TCC_VERSION="0.9.26"' -D ONE_SOURCE=1 \
  work/tinycc-fixed/tcc.c
( cd work && qemu-arm-static ./tcc-arm-fixed -c ldconst.c -o ldconst-fixed.o )
arm-linux-gnueabihf-objcopy -O binary --only-section=.data work/ldconst-fixed.o work/fixed-data.bin
loud "patched fork tcc .data:"
python3 check-data.py work/fixed-data.bin control
cmp work/fixed-data.bin work/gcc-data.bin \
  || die "the patched tcc's .data differs from arm-gcc's"
loud "FIX VERIFIED: byte-identical to the arm-gcc control"

banner "VERDICT"
loud "BUG REPRODUCED: with the fork's own arm bootstrap configuration, every"
loud "long double constant is materialized as 0.0 (empty init_putv VT_LDOUBLE"
loud "store), and double constants are integer-converted (2.5 -> 2).  In the"
loud "arm bootstrap this zeroes e.g. musl floatscan.c's 1000000000.0L."
loud "FIX VERIFIED: patches 0011+0012 apply to the pinned fork with strict"
loud "'git am' and make the same compiler emit the arm-gcc bytes exactly."
loud "ERRATUM VERIFIED: the 0012 file attached to the 2026-07-21 mail is"
loud "rejected by 'git am' AND by GNU patch, which is what the erratum is for."
echo "PASS: tcc-mes-arm-ldouble-zero reproduced, and the fix verified"
