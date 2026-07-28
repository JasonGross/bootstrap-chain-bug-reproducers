#!/usr/bin/env bash
# tcc-arm-double-arg-caller (bug 21 in this repository's README): the patch-verifying leg for tinycc
# patch 0014 (bug19 -- the softfp double-argument caller regression).
#
# bug19 is NOT an upstream tcc bug: it is a regression introduced by OUR OWN
# patches 4 and 5 (the copy_params stack-cleanup / pop-mask rewrites).  Patch 5
# discards assign_regs' `*todo` bitmap and rebuilds the pop {todo} core-register
# mask inline -- but only in the VT_STRUCT arm of CORE_STRUCT_CLASS.  A softfp
# `double`/`float` in core registers is ALSO CORE_STRUCT_CLASS but takes the
# is_float vpush path, so its words are never recorded: `todo` stays 0, no
# `pop {r0,r1,r2,r3}` is emitted, the doubles sit on the stack and r0-r3 are
# never loaded.  A call passing 2+ doubles reads its arguments from uninitialised
# registers.  Patch 0014 rebuilds the mask for that case too.
#
# This leg builds the fork's arm cross-compiler three ways -- STOCK (pristine,
# the correct control: upstream carries *todo through untouched), BUGGY
# (+0004+0005, the regression), FIXED (+0004+0005+0014) -- and shows:
#
#   BYTE LEVEL   STOCK emits `pop {r0,r1,r2,r3}` for the softfp double calls;
#                BUGGY drops it; FIXED restores it AND its object is
#                byte-identical to STOCK's (0014 is a faithful restoration of
#                stock codegen, not a new codegen path).
#   RUNTIME A/B  a gcc-built softfp receiver (independent ABI reference) dumps
#                the doubles it actually received: with BUGGY they arrive wrong
#                (pick1(1.5,2.25) -> 2.25), with FIXED and with an arm-gcc-built
#                caller they arrive exactly right (13 IEEE-754 words).
#
# The tcc is a gcc-built host->arm CROSS compiler (RUNS on the host, EMITS arm),
# so the byte-level leg needs no qemu.  The runtime leg links the tcc-emitted
# caller object against a gcc-built arm receiver and runs it under qemu-arm.
cd "$(dirname "$0")"
. ../common.sh
BUGDIR=$PWD

FORK_URL=https://gitlab.com/janneke/tinycc.git
FORK_COMMIT=ee75a10cd71bebf23cb23598a49ee3c160ef0fe8   # branch mes-0.25.0
FORK_BRANCH=mes-0.25.0

for t in gcc arm-linux-gnueabihf-gcc arm-linux-gnueabihf-objdump qemu-arm-static python3 git; do
  command -v "$t" >/dev/null || die "need $t (see the workflow for apt names)"
done

# The fork as a gcc-built host->arm cross compiler.  No -DBOOTSTRAP: bug19 is in
# copy_params, which patch 5 rewrites unconditionally, so it reproduces in a
# plain (non-bootstrap) build -- which also needs no source shims.
TFLAGS=(-w -DTCC_TARGET_ARM=1 -DTCC_ARM_EABI=1 -DTCC_ARM_VFP=1 -DHAVE_LONG_LONG=1
        -DHAVE_FLOAT=1 -DONE_SOURCE=1 -DTCC_VERSION='"0.9.26"'
        -DCONFIG_TCCDIR='"/nonexistent"' -DCONFIG_TCC_CRTPREFIX='"/nonexistent"'
        -DCONFIG_TCC_SYSINCLUDEPATHS='"/nonexistent"'
        -DCONFIG_TCC_LIBPATHS='"/nonexistent"' -DCONFIG_TCC_ELFINTERP='"/mes/loader"')
OBJDUMP=arm-linux-gnueabihf-objdump

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

banner "2/5 -- BUILD three cross-tcc variants: STOCK, BUGGY (+0004+0005), FIXED (+0014)"
build_variant () { # <label> <patch...>
  local label="$1"; shift; local src="src-$label"
  rm -rf "$src"; cp -a pristine "$src"
  for p in "$@"; do git -C "$src" am -q "$p"; done
  : > "$src/config.h"
  gcc -O0 "${TFLAGS[@]}" -o "tcc-$label" "$src/tcc.c" 2> "build-$label.log" \
    || { tail -20 "build-$label.log"; die "build of tcc-$label failed"; }
  [ -x "tcc-$label" ] || die "no tcc-$label produced"
}
build_variant stock
build_variant buggy "$BUGDIR/patches/0004-arm-derive-gfunc_call-stack-cleanup-from-copy_params.patch" \
                    "$BUGDIR/patches/0005-arm-derive-copy_params-pop-mask-and-spill-from-type_size.patch"
build_variant fixed "$BUGDIR/patches/0004-arm-derive-gfunc_call-stack-cleanup-from-copy_params.patch" \
                    "$BUGDIR/patches/0005-arm-derive-copy_params-pop-mask-and-spill-from-type_size.patch" \
                    "$BUGDIR/patches/0014-arm-restore-pop-todo-for-softfp-float-double-in-core.patch"
# Assert the stimulus is really in the buggy/fixed trees (guard against a silent
# no-op patch selection): patch 5's discard-and-rebuild, and 0014's new branch.
grep -q 'CORE_STRUCT_CLASS' src-fixed/arm-gen.c || die "arm-gen.c has no CORE_STRUCT_CLASS (fork changed?)"
diff <(grep -c 'else if (i == CORE_STRUCT_CLASS)' src-buggy/arm-gen.c) \
     <(grep -c 'else if (i == CORE_STRUCT_CLASS)' src-fixed/arm-gen.c) >/dev/null \
  && die "0014's CORE_STRUCT_CLASS branch count is identical in buggy and fixed -- patch not applied"
loud "buggy has patch 5's discard-and-rebuild; fixed adds 0014's CORE_STRUCT_CLASS pop rebuild"

banner "3/5 -- BYTE LEVEL: the softfp caller's pop {r0,r1,r2,r3}"
# caller.c passes 2/3/4 doubles (and a mixed int/double call) into extern
# receivers; the doubles are built from integer bit-puns so this measures ONLY
# the caller's argument marshalling, never FP-literal parsing.
for v in stock buggy fixed; do
  ./tcc-$v -c -o caller-$v.o "$BUGDIR/caller.c" 2>/dev/null || die "tcc-$v failed to compile caller.c"
done
pops () { $OBJDUMP -d "$1" | grep -c 'pop[[:space:]]*{r0, r1, r2, r3}' || true; }
ps=$(pops caller-stock.o); pb=$(pops caller-buggy.o); pf=$(pops caller-fixed.o)
loud "pop {r0,r1,r2,r3} occurrences -- STOCK=$ps  BUGGY=$pb  FIXED=$pf"
# ABLATE=1 points the FIXED-side checks at the BUGGY object; the named
# 'pop restored' / 'byte-identical to stock' assertions must then fire.
FIXOBJ=caller-fixed.o; FIXPOPS=$pf
if [ "${ABLATE:-0}" = 1 ]; then
  loud "ABLATE=1: FIXED checks pointed at the BUGGY object; they MUST fail."
  FIXOBJ=caller-buggy.o; FIXPOPS=$pb
fi
[ "$ps" -ge 1 ] || die "STOCK has no pop {r0-r3} at all -- the disasm probe is not finding the marshalling (harness suspect)"
[ "$pb" -lt "$ps" ] || die "BUGGY did not drop any pop {r0-r3} -- bug19 not reproduced (patch 5 missing?)"
[ "$FIXPOPS" = "$ps" ] || die "FIXED restored $FIXPOPS pop {r0-r3}, expected STOCK's $ps \
(if ABLATE=1 this is the reproducer correctly going red: the buggy object is short a pop)"
cmp caller-buggy.o caller-stock.o >/dev/null && die "BUGGY object equals STOCK -- the regression left no trace"
cmp "$FIXOBJ" caller-stock.o >/dev/null \
  || die "FIXED object is NOT byte-identical to STOCK (0014 should be a faithful restoration) \
(if ABLATE=1 this is the reproducer correctly going red)"
loud "BYTE LEVEL: STOCK has the pop, BUGGY drops it, FIXED restores it AND is"
loud "            byte-identical to STOCK -- 0014 is a faithful restoration."

banner "4/5 -- RUNTIME A/B: doubles into a gcc-built (independent-ABI) receiver"
# driver.c: gcc-built softfp, freestanding.  Its receivers store each received
# double's raw bits; _start invokes the tcc-built callers, then write(2)s the
# array.  Being gcc-built, it is an independent reference for the softfp ABI --
# a matching bug in a tcc-built receiver could otherwise mask a caller bug.
arm-linux-gnueabihf-gcc -c -O0 -marm -march=armv7-a -mfloat-abi=softfp -mfpu=vfpv3-d16 \
    -o driver.o "$BUGDIR/driver.c"
# arm-gcc's own caller = a third, fully independent implementation of the ABI.
arm-linux-gnueabihf-gcc -c -O0 -marm -march=armv7-a -mfloat-abi=softfp -mfpu=vfpv3-d16 \
    -o caller-armgcc.o "$BUGDIR/caller.c"
expected=$(python3 - <<'PY'
import struct
words = [('d',1.5),('d',2.25),                     # c2
         ('d',1.5),('d',2.25),('d',3.75),          # c3
         ('d',1.5),('d',2.25),('d',3.75),('d',4.5),# c4
         ('i',7),('d',1.5),('i',9),('d',2.25)]     # cmix
b=b''.join(struct.pack('<d',v) if k=='d' else struct.pack('<Q',v) for k,v in words)
print(b.hex())
PY
)
run_caller () { # <caller-obj> -> hex of the 13 received words
  local obj="$1"
  arm-linux-gnueabihf-gcc -marm -nostdlib -static -z noexecstack -Wl,--no-warn-mismatch \
      -o ab.arm driver.o "$obj"
  qemu-arm-static ./ab.arm | od -An -v -tx1 | tr -d ' \n'
}
got_gcc=$(run_caller caller-armgcc.o)
got_stock=$(run_caller caller-stock.o)
got_fixed=$(run_caller "$FIXOBJ")
got_buggy=$(run_caller caller-buggy.o)
loud "expected (13 IEEE-754 words) : $expected"
loud "arm-gcc caller (ABI control) : $got_gcc"
loud "STOCK  tcc caller            : $got_stock"
loud "FIXED  tcc caller            : $got_fixed"
loud "BUGGY  tcc caller            : $got_buggy"
[ "$got_gcc"   = "$expected" ] || die "the arm-gcc ABI control did not produce the expected 13 words -- harness suspect"
[ "$got_stock" = "$expected" ] || die "STOCK tcc caller mismatched the ABI control -- unexpected"
[ "$got_buggy" != "$expected" ] || die "BUGGY tcc caller produced the CORRECT values -- bug19 did not reproduce at runtime"
[ "$got_fixed" = "$expected" ] || die "FIXED tcc caller did not deliver the doubles correctly \
(if ABLATE=1 this is the reproducer correctly going red: the buggy caller mis-marshals)"
loud "RUNTIME: BUGGY mis-passes the doubles; FIXED (and arm-gcc, and STOCK) pass them exactly."

banner "5/5 -- VERDICT"
cat <<EOF

  copy_params, softfp double arguments passed in core registers:

    STOCK (pristine fork)        pop {r0,r1,r2,r3} present; doubles arrive right
    + patches 4,5 (BUGGY)        pop {r0,r1,r2,r3} DROPPED; doubles mis-passed
                                 (r2(1.5,2.25): arg0 receives 0x${got_buggy:0:16}
                                  = the 2nd argument's 2.25, not 1.5)
    + patch 0014 (FIXED)         pop restored; object byte-identical to STOCK;
                                 doubles arrive exactly right

  So patch 0014 completes patches 4/5: it restores the softfp double-argument
  marshalling those patches regressed, as a faithful (byte-identical) return to
  stock codegen.  Stock upstream tcc is unaffected.
EOF
loud "PASS: patch 0014 verified -- bug19 reproduced and the fix restores stock behavior"
