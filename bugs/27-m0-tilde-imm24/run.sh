#!/usr/bin/env bash
# m0-tilde-imm24: stage0's M0 macro assembler has no 24-bit `~` immediate.
#
# The mescc-tools M1 assembler numerates immediate operands by a one-character
# width prefix: `!` = 8-bit, `@`/`%` wider, and `~` = 24-bit (M1-macro.c:
# `else if('~' == c) number_of_bytes = 3;` / `value & 0xFFFFFF`).  M0 -- the
# minimal per-architecture assembler used earlier in the stage0 ladder, shipped
# as `M0_<arch>.hex2` with readable `GAS/M0_<arch>.S` and
# `Development/M0_<arch>.M1` mirrors -- has no `~` case: its numerate routine
# special-cases only `%` and `@` and falls through to an 8-bit store for
# everything else, so it numerates a `~` LITERAL at only 8 bits.  `~0` comes out
# as `00`, two bytes short of the 24-bit `000000`.
#
# `~` has TWO operand forms, and only ONE of them reaches M0's numerate routine:
#   * LITERAL number `~0` -- resolved by the ASSEMBLER (M0/M1).  M0 gets it
#     wrong (8 bits); M1 gets it right (24 bits).  The armv7l `unshare` wrapper
#     uses exactly this at `armv7l/linux/unistd.c:201`: `~0 JUMP_ALWAYS`
#     (`b .+8`, jumping over an embedded syscall-number word).  This single site
#     is the whole impact of the bug.
#   * LABEL operand (a `~` before a label, not a number) -- NOT numerated by the
#     assembler at all: M0 and M1 alike copy the token through unresolved to the
#     hex2 LINKER, which sizes `~` at 3 bytes (hex2_linker.c: `ip = ip + 3` and
#     `outputPointer(displacement, 3, FALSE)`).  armv7l's M2libc writes these as
#     `^~label` (e.g. `^~divide_loop JUMP_NE`); the leading `^` is a hex2
#     alignment marker, not a signal to the assembler.  So the label form
#     assembles byte-identically whether the assembler was M0 or M1 -- M2libc's
#     13 armv7l `^~label` branch/call targets are UNAFFECTED; only the one
#     literal `~0` site is mis-assembled.
#
# GREEN == the bug REPRODUCES (by EXECUTION, not inspection):
#   A  PREMISE (live mescc-tools HEAD): M1 still numerates `~` as 24 bits
#      (3 bytes, `& 0xFFFFFF`) -- the correct width the armv7l idiom needs.
#   B  x86 M0 (built from pinned stage0-posix-x86, run under qemu-i386) renders
#      the LITERAL `~0` as the 8-bit `00`, NOT `000000`.
#   C  aarch64 M0 (built from pinned stage0-posix-aarch64, run under
#      qemu-aarch64) renders `~0` the SAME wrong way -- its output is
#      byte-identical to x86 M0's.  Two independent per-arch M0 lineages agree
#      on the wrong answer; that shared defect is why a cross-lineage identity
#      check between them cannot catch it.
#   D  M1 (the referee, gcc-built) renders the same `~0` as the correct 24-bit
#      `000000`.
#   E  BOUNDARY / control: the LABEL form `^~loop JUMP_NE`, taken through the
#      full M0->hex2 and M1->hex2 pipelines, assembles byte-identically (a
#      4-byte ARM branch, `fe ff ff 1a`).  hex2 sizes `~` correctly, so the M0
#      gap does not reach the 13 `^~label` sites -- the bug is confined to the
#      one literal `~0` site, not "every armv7l `~` site".
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

# assemble an .M1 file with an M0 and echo the emitted hex2 text.
# run_m0 <m0-invocation> <out-hex2> <input.M1>
run_m0 () { rm -f "$2"; ( cd "$BUGDIR/work" && $1 "../$3" "$(basename "$2")" ) || die "M0 crashed"; }

# ---------------------------------------------------------------------------
banner "PART B -- x86 M0 renders the LITERAL ~0 as the 8-bit 00 (not 000000)"
# ---------------------------------------------------------------------------
run_m0 "qemu-i386-static ./M0-x86" work/x86.hex2 tilde.M1
loud "x86 M0 output for '~0 JUMP_ALWAYS':"; cat work/x86.hex2 | sed 's/^/    /'
grep -q 'EA' work/x86.hex2       || die "x86 M0 did not emit JUMP_ALWAYS (EA) -- it did not run the input"
grep -q '000000' work/x86.hex2   && die "x86 M0 emitted a 24-bit '000000' -- the gap is CLOSED; re-read"
grep -qx '00' work/x86.hex2      || die "x86 M0 did not render '~0' as the 8-bit '00'"
loud "x86 M0: '~0' -> 00 (8-bit), two bytes short of 000000"

# ---------------------------------------------------------------------------
banner "PART C -- aarch64 M0 renders it the SAME wrong way (shared defect)"
# ---------------------------------------------------------------------------
run_m0 "qemu-aarch64-static ./M0-aarch64" work/aarch64.hex2 tilde.M1
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

# ---------------------------------------------------------------------------
banner "PART E -- BOUNDARY: the label form ^~label is hex2-LINKER-resolved, so UNAFFECTED"
# ---------------------------------------------------------------------------
# `^~label`'s operand is a label, not a number, so the assembler (M0 or M1) does
# not numerate it -- it copies the token through to the hex2 linker, which sizes
# `~` at 3 bytes (the leading `^` is a hex2 alignment marker, not an assembler
# signal).  So it must assemble byte-identically through M0->hex2 and through
# M1->hex2.  This is the control that BOUNDS the bug to the literal `~0` site
# (PART B-D): the 13 armv7l `^~label` branch/call targets are NOT mis-assembled.
#
# M2libc's 13 sites use TWO mnemonics -- 9 `CALL_ALWAYS` (EB) and 4 `JUMP_NE`
# (1A) -- so this leg exercises BOTH rather than letting one sample stand for the
# whole set.  Each file (label.M1 / label_call.M1) defines a `:loop` and branches
# back to it; the correct armv7l encoding is a 4-byte branch: the 24-bit
# displacement -2 (`fe ff ff`) plus the mnemonic's opcode byte -- `fe ff ff 1a`
# for JUMP_NE, `fe ff ff eb` for CALL_ALWAYS.

# assemble one label-form file through M0-x86, M0-aarch64 and M1, link each to an
# armv7l binary (where `~` is sized), and assert all three agree on a 4-byte
# branch carrying the expected opcode byte.  <src.M1> <tag> <opcode-hex> <human>
check_label_form () {
  run_m0 "qemu-i386-static ./M0-x86"        "work/${2}_x86.hex2" "$1"
  run_m0 "qemu-aarch64-static ./M0-aarch64" "work/${2}_a64.hex2" "$1"
  "$M1B" --architecture armv7l --little-endian -f "$1" -o "work/${2}_m1.hex2" >/dev/null 2>&1 || die "M1 crashed on $1"
  for who in x86 a64 m1; do
    "$HEX2" --architecture armv7l --little-endian --base-address 0x0 -f "work/${2}_${who}.hex2" -o "work/${2}_${who}.bin" >/dev/null 2>&1 \
      || die "hex2 link failed for ${2}_${who}"
  done
  loud "$4  M0-x86 : $(od -An -tx1 work/${2}_x86.bin | tr -s ' ')"
  loud "$4  M0-a64 : $(od -An -tx1 work/${2}_a64.bin | tr -s ' ')"
  loud "$4  M1     : $(od -An -tx1 work/${2}_m1.bin  | tr -s ' ')"
  [ "$(wc -c < work/${2}_m1.bin)" -eq 4 ] || die "$4 is not a 4-byte ARM branch -- re-read"
  cmp -s "work/${2}_x86.bin" "work/${2}_m1.bin" || die "$4: M0-x86 != M1 -- expected byte-identical (linker-sized)"
  cmp -s "work/${2}_a64.bin" "work/${2}_m1.bin" || die "$4: M0-aarch64 != M1 -- expected byte-identical (linker-sized)"
  [ "$(od -An -tx1 work/${2}_m1.bin | tr -d ' \n')" = "feffff$3" ] \
    || die "$4: expected fe ff ff $3, got $(od -An -tx1 work/${2}_m1.bin | tr -s ' ')"
  loud "$4: M0-x86 == M0-aarch64 == M1, 4-byte branch fe ff ff $3 -- hex2 sizes ~, the M0 gap does not reach it"
}
check_label_form label.M1      lblJ 1a "JUMP_NE ^~loop (covers the 4 JUMP_NE sites)"
check_label_form label_call.M1 lblC eb "CALL_ALWAYS ^~loop (covers the 9 CALL_ALWAYS sites)"
# both mnemonics carry the SAME 3-byte displacement (fe ff ff), differing only in
# the trailing opcode byte -- direct evidence that hex2 sizes `~` on the `~`
# character alone, independent of the instruction it prefixes.
cmp -s <(head -c3 work/lblJ_m1.bin) <(head -c3 work/lblC_m1.bin) \
  || die "JUMP_NE and CALL_ALWAYS label forms differ in the ~ displacement -- expected identical fe ff ff"
loud "both label mnemonics share the ~ displacement fe ff ff, differ only in opcode (1a vs eb) -- hex2 sizes ~ on the character, not the opcode"

banner "VERDICT"
loud "BUG REPRODUCED: stage0's M0 numerates the LITERAL '~' immediate at 8 bits,"
loud "so the armv7l '~0 JUMP_ALWAYS' site (armv7l/linux/unistd.c:201) assembles"
loud "two bytes short (00 vs 000000).  Both the x86 and aarch64 upstream M0"
loud "lineages emit the identical 8-bit answer, while M1 -- the assembler used"
loud "later in the same chain -- emits the correct 24-bit form.  The label form"
loud "^~label is hex2-linker-resolved and assembles identically under M0 and M1,"
loud "so the impact is the one literal site, not the 13 label-relative ones."
echo "PASS: m0-tilde-imm24 reproduced (literal ~0: x86 M0 == aarch64 M0 == 8-bit; M1 == 24-bit; both label mnemonics ^~loop JUMP_NE and ^~loop CALL_ALWAYS identical via hex2)"
