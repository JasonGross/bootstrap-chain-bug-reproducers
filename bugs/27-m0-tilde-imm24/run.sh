#!/usr/bin/env bash
# m0-tilde-imm24: stage0's M0 macro assembler has no 24-bit `~` immediate.
#
# The mescc-tools M1 assembler numerates immediate operands by a one-character
# width prefix: `!` = 8-bit, `@`/`%` wider, and `~` = 24-bit (M1-macro.c:
# `else if('~' == c) number_of_bytes = 3;` / `value & 0xFFFFFF`).  The armv7l
# M2libc uses `~` for the 24-bit relative offset of an ARM `B{cond}`/`BL`,
# written `^~label` (e.g. `^~divide_loop JUMP_NE`).  This reproducer probes that
# same width with a minimal one-line `~0 JUMP_ALWAYS`, which must assemble to a
# 4-byte ARM `b .+8` (`000000` + the `EA` condition byte).  M0 -- the minimal
# per-architecture assembler used earlier in the stage0 ladder, shipped as
# `M0_<arch>.hex2` with readable `GAS/M0_<arch>.S` and `Development/M0_<arch>.M1`
# mirrors -- has no `~` case: its numerate routine special-cases only `%` and
# `@` and falls through to an 8-bit store for everything else, so it numerates
# `~` at only 8 bits.  So `~0` comes out as `00`, two bytes short of `000000`;
# every armv7l `~`-immediate site is two bytes short, misaligning every
# following label.
#
# GREEN == the bug REPRODUCES (by EXECUTION, not inspection):
#   A  PREMISE (live mescc-tools HEAD): M1 still numerates `~` as 24 bits
#      (3 bytes, `& 0xFFFFFF`) -- the correct width the armv7l idiom needs.
#   B  x86 M0 (built from pinned stage0-posix-x86, run under qemu-i386) renders
#      `~0` as the 8-bit `00`, NOT `000000`.
#   C  aarch64 M0 (built from pinned stage0-posix-aarch64, run under
#      qemu-aarch64) renders `~0` the SAME wrong way -- its output is
#      byte-identical to x86 M0's.  Two independent per-arch M0 lineages agree
#      on the wrong answer; that shared defect is why a three-way identity
#      check across lineages passes while every lineage is broken.
#   D  M1 (the referee, gcc-built) renders the same `~0` as the correct 24-bit
#      `000000`.
cd "$(dirname "$0")"
. ../common.sh
BUGDIR=$PWD

# Pinned upstreams (2026-07-28).  The BUILD uses these pins; PART A re-checks
# the live mescc-tools default branch for the correct-width referee.
MESCC_URL=https://github.com/oriansj/mescc-tools.git
MESCC_SHA=d59464d2641de8a90032ad2456bdb34b4db3436a
S0X86_URL=https://github.com/oriansj/stage0-posix-x86.git
S0X86_SHA=14721630c8d3e4a7de943e27488d0d582788837f
S0A64_URL=https://github.com/oriansj/stage0-posix-aarch64.git
S0A64_SHA=cedcddd24e74d10d0e41dd647e413fd7ee476530
M1MACRO_RAW=https://raw.githubusercontent.com/oriansj/mescc-tools/master/M1-macro.c

mkdir -p work

# ---------------------------------------------------------------------------
banner "PART A -- premise re-check: does M1 (the referee) still make ~ 24-bit?"
# ---------------------------------------------------------------------------
# The whole point of the reproducer is that M0 disagrees with M1 on the width
# of `~`.  Re-derive the *correct* width from the live M1 source every run, so
# that if upstream ever changed M1's `~` this reproducer's premise would go red
# rather than silently comparing against a stale reference.
if curl -fsSL --max-time 60 --retry 2 -o work/M1-macro-live.c "$M1MACRO_RAW" 2>/dev/null; then
  loud "fetched live mescc-tools M1-macro.c"
  grep -n "'~'" work/M1-macro-live.c | sed 's/^/    /'
  grep -qE "'~' == c\)[[:space:]]*number_of_bytes = 3" work/M1-macro-live.c \
    || die "M1 no longer numerates '~' as 3 bytes -- the correct-width referee changed; re-read"
  grep -qE "'~' == c\)[[:space:]]*value = value & 0xFFFFFF" work/M1-macro-live.c \
    || die "M1 no longer masks '~' to 0xFFFFFF (24-bit) -- re-read"
  loud "live M1: '~' is 3 bytes, masked to 0xFFFFFF -- 24-bit is the correct width"
else
  loud "PREMISE RE-CHECK SKIPPED: could not reach $M1MACRO_RAW"
  loud "  (host unreachable != bug fixed -- not failing the run over it)"
fi

# ---------------------------------------------------------------------------
banner "Build the tools: gcc-built M1 + hex2, and the two upstream M0 binaries"
# ---------------------------------------------------------------------------
command -v gcc >/dev/null || die "need gcc"
command -v git >/dev/null || die "need git"
command -v qemu-i386-static    >/dev/null || die "need qemu-user-static (qemu-i386-static)"
command -v qemu-aarch64-static >/dev/null || die "need qemu-user-static (qemu-aarch64-static)"

clone_pin () { # <url> <sha> <dir> [--recurse-submodules]
  local url="$1" sha="$2" dir="$3" rec="${4:-}"
  [ -d "$dir" ] && return 0
  git clone -q $rec "$url" "$dir"
  git -C "$dir" checkout -q "$sha" || die "checkout $sha failed in $dir"
  [ -n "$rec" ] && git -C "$dir" submodule update --init -q >/dev/null 2>&1 || true
}
clone_pin "$MESCC_URL" "$MESCC_SHA" work/mescc-tools --recurse-submodules
clone_pin "$S0X86_URL" "$S0X86_SHA" work/stage0-x86
clone_pin "$S0A64_URL" "$S0A64_SHA" work/stage0-aarch64

make -C work/mescc-tools -s M1 hex2 CC=gcc >/dev/null 2>&1 || die "mescc-tools build failed"
M1B=$BUGDIR/work/mescc-tools/bin/M1
HEX2=$BUGDIR/work/mescc-tools/bin/hex2
[ -x "$M1B" ] && [ -x "$HEX2" ] || die "M1/hex2 missing"
loud "built M1 + hex2 with gcc"

# link an M0 program (hex2 text) against its ELF header into a runnable binary.
# build_m0 <arch> <base> <elf-hex2> <m0-hex2> <out>
build_m0 () {
  "$HEX2" --architecture "$1" --little-endian --base-address "$2" \
    -f "$3" -f "$4" -o "$5" >/dev/null 2>&1 || die "hex2 link failed for M0 ($1)"
  chmod +x "$5"
}
build_m0 x86     0x08048000 work/stage0-x86/ELF-i386.hex2     work/stage0-x86/M0_x86.hex2       work/M0-x86
build_m0 aarch64 0x00400000 work/stage0-aarch64/ELF-aarch64.hex2 work/stage0-aarch64/M0_AArch64.hex2 work/M0-aarch64
file work/M0-x86     | grep -q '80386'        || die "M0-x86 is not an i386 ELF"
file work/M0-aarch64 | grep -q 'aarch64'      || die "M0-aarch64 is not an aarch64 ELF"
loud "linked M0-x86 (i386) and M0-aarch64 from pinned stage0-posix sources"

# assemble tilde.M1 with an M0 and echo the emitted hex2 text.
run_m0 () { rm -f "$2"; ( cd "$BUGDIR/work" && $1 ../tilde.M1 "$(basename "$2")" ) || die "M0 crashed"; }

# ---------------------------------------------------------------------------
banner "PART B -- x86 M0 renders ~0 as the 8-bit 00 (not 000000)"
# ---------------------------------------------------------------------------
run_m0 "qemu-i386-static ./M0-x86" work/x86.hex2
loud "x86 M0 output for '~0 JUMP_ALWAYS':"; cat work/x86.hex2 | sed 's/^/    /'
grep -q 'EA' work/x86.hex2       || die "x86 M0 did not emit JUMP_ALWAYS (EA) -- it did not run the input"
grep -q '000000' work/x86.hex2   && die "x86 M0 emitted a 24-bit '000000' -- the gap is CLOSED; re-read"
grep -qx '00' work/x86.hex2      || die "x86 M0 did not render '~0' as the 8-bit '00'"
loud "x86 M0: '~0' -> 00 (8-bit), two bytes short of 000000"

# ---------------------------------------------------------------------------
banner "PART C -- aarch64 M0 renders it the SAME wrong way (shared defect)"
# ---------------------------------------------------------------------------
run_m0 "qemu-aarch64-static ./M0-aarch64" work/aarch64.hex2
loud "aarch64 M0 output for '~0 JUMP_ALWAYS':"; cat work/aarch64.hex2 | sed 's/^/    /'
grep -q '000000' work/aarch64.hex2 && die "aarch64 M0 emitted a 24-bit '000000' -- the gap is CLOSED; re-read"
grep -qx '00' work/aarch64.hex2    || die "aarch64 M0 did not render '~0' as the 8-bit '00'"
cmp -s work/x86.hex2 work/aarch64.hex2 \
  || die "x86 and aarch64 M0 outputs differ -- expected byte-identical shared defect"
loud "aarch64 M0: '~0' -> 00, BYTE-IDENTICAL to x86 M0 -- both lineages agree on the wrong answer"

# ---------------------------------------------------------------------------
banner "PART D -- M1 (the referee) renders the same ~0 as the correct 24-bit 000000"
# ---------------------------------------------------------------------------
"$M1B" --architecture armv7l --little-endian -f tilde.M1 -o work/m1.hex2 >/dev/null 2>&1 || die "M1 crashed on tilde.M1"
loud "M1 output for '~0 JUMP_ALWAYS':"; cat work/m1.hex2 | sed 's/^/    /'
grep -q '000000' work/m1.hex2 || die "M1 did not render '~0' as 24-bit '000000' -- referee unexpectedly agrees with M0"
loud "M1: '~0' -> 000000 (24-bit) -- with the EA byte this is the ARM 'b .+8' the armv7l idiom needs"

banner "VERDICT"
loud "BUG REPRODUCED: stage0's M0 numerates the '~' immediate at 8 bits, so the"
loud "armv7l '~0 JUMP_ALWAYS' probe assembles two bytes short (00 vs 000000)."
loud "Both the x86 and aarch64 upstream M0 lineages emit the identical 8-bit"
loud "answer, while M1 -- the assembler used later in the same chain -- emits the"
loud "correct 24-bit form.  The two assemblers disagree on the width of '~'."
echo "PASS: m0-tilde-imm24 reproduced (x86 M0 == aarch64 M0 == 8-bit; M1 == 24-bit)"
