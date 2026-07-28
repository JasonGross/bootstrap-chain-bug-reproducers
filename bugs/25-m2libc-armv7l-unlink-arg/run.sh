#!/usr/bin/env bash
# m2libc-armv7l-unlink-arg: M2libc's armv7l unlink() hands the kernel &filename
# instead of filename.  In M2libc/armv7l/linux/unistd.c the syscall wrappers
# fetch each stack-passed argument with the pair
#     "!4 R0 SUB R12 ARITH_ALWAYS"     ; R0 = &arg   (address of the slot)
#     "!0 R0 LOAD32 R0 MEMORY"         ; R0 = *R0    (the argument value)
# unlink() has the first line but NOT the second, so it passes the ADDRESS of
# the pointer.  The kernel reads a bogus path, returns nonzero (ENOENT), and
# the file is never removed -- a chain-built `rm` cannot delete.  Its char*
# siblings access()/chdir()/symlink() all carry the LOAD32, and every other
# architecture (x86/amd64/riscv32/riscv64 dereference; aarch64 needs no load)
# is correct -- this is armv7l-only.
#
# GREEN == the bug REPRODUCES:
#   A  PREMISE (live M2libc HEAD, re-checked every run so a fix goes red):
#      unlink()'s wrapper carries "SUB R12" + syscall !10 but has NO
#      "LOAD32 R0 MEMORY", while access()/chdir()/symlink() all do.
#   B  RUNTIME (armv7l, qemu-user): a real C program built through the real
#      M2-Planet -> M1 -> hex2 chain against pinned M2libc calls access() and
#      unlink() on a file that DEMONSTRABLY exists.  access() succeeds (finds
#      it), unlink() fails, and the file SURVIVES.
#   C  CONTROL (amd64, native): the SAME program built the SAME way for amd64
#      removes the file -- the defect is the missing armv7l dereference, not
#      the program.
#   D  FIX (armv7l): adding the single missing "LOAD32 R0 MEMORY" line to
#      unlink() -- and nothing else -- makes it remove the file.
cd "$(dirname "$0")"
. ../common.sh
BUGDIR=$PWD

# Pinned upstreams (mutually compatible HEADs, 2026-07-28).  The BUILD uses
# these pins for reproducibility; PART A re-checks the LIVE default branch.
M2PLANET_URL=https://github.com/oriansj/M2-Planet.git
M2PLANET_SHA=34fbd5c2a9b6eb634a4f6ad95158dcd1efcf19e0
MESCC_URL=https://github.com/oriansj/mescc-tools.git
MESCC_SHA=d59464d2641de8a90032ad2456bdb34b4db3436a
M2LIBC_URL=https://github.com/oriansj/M2libc.git
M2LIBC_SHA=b7e5d1cbd24fbd335e65620a395720d500015eb0
M2LIBC_RAW=https://raw.githubusercontent.com/oriansj/M2libc/master/armv7l/linux/unistd.c

mkdir -p work

# print the asm body of a M2libc syscall wrapper: from its `int NAME (` line
# through the closing brace of the function.
func_body () { awk -v re="$2" '$0 ~ re {p=1} p{print} p&&/^}/{exit}' "$1"; }

# ---------------------------------------------------------------------------
banner "PART A -- premise re-check against LIVE M2libc HEAD"
# ---------------------------------------------------------------------------
# A pinned reproducer proves the bug existed at the pin; it cannot see that
# upstream has since fixed it.  Re-derive the accused signature from the live
# default branch every run.  (host unreachable != bug fixed -- skip, per the
# common.sh convention, rather than a red that teaches nobody anything.)
if curl -fsSL --max-time 60 --retry 2 -o work/unistd-live.c "$M2LIBC_RAW" 2>/dev/null; then
  loud "fetched live M2libc armv7l/linux/unistd.c"
  U=$(func_body work/unistd-live.c '^int unlink[ (]')
  echo "$U" | sed 's/^/    /'
  echo "$U" | grep -q 'SUB R12'            || die "live unlink() no longer uses the SUB R12 arg idiom -- re-read"
  echo "$U" | grep -q '!10 R7 LOADI8'      || die "live unlink() is no longer syscall !10 -- re-read"
  if echo "$U" | grep -q 'LOAD32 R0 MEMORY'; then
    die "live unlink() NOW dereferences its argument -- upstream may have FIXED this; a human must re-read the report"
  fi
  loud "live unlink(): SUB R12 + syscall !10, and NO 'LOAD32 R0 MEMORY' -- the defect stands"
  for sib in access chdir symlink; do
    B=$(func_body work/unistd-live.c "^int $sib[ (]")
    echo "$B" | grep -q 'LOAD32 R0 MEMORY' \
      || die "sibling $sib() lost its 'LOAD32 R0 MEMORY' -- the contrast changed; re-read"
    loud "sibling $sib(): carries 'LOAD32 R0 MEMORY' (correctly dereferences)"
  done
  loud "PREMISE CONFIRMED at HEAD: unlink() has SUB R12 + syscall !10 but no 'LOAD32 R0 MEMORY'; access/chdir/symlink all carry it"
  # NOTE: this leg checks unlink() against access/chdir/symlink only, so it
  # cannot and does NOT establish that unlink is the sole affected wrapper.
  # It is not: chroot() (char*) and close() (int fd) in this same file share
  # the identical missing 'LOAD32 R0 MEMORY' (verified by reading the asm).
  # Do not read the line above as a uniqueness claim.
else
  loud "PREMISE RE-CHECK SKIPPED: could not reach $M2LIBC_RAW"
  loud "  (host unreachable != bug fixed -- not failing the run over it)"
fi

# ---------------------------------------------------------------------------
banner "Build the real bootstrap toolchain (gcc-built M2-Planet, M1, hex2)"
# ---------------------------------------------------------------------------
command -v gcc            >/dev/null || die "need gcc"
command -v git            >/dev/null || die "need git"
command -v qemu-arm-static >/dev/null || die "need qemu-user-static (qemu-arm-static)"

clone_pin () { # <url> <sha> <dir> [--recurse]
  local url="$1" sha="$2" dir="$3" rec="${4:-}"
  [ -d "$dir" ] && return 0
  git clone -q $rec "$url" "$dir"
  git -C "$dir" checkout -q "$sha" || die "checkout $sha failed in $dir"
}
clone_pin "$M2PLANET_URL" "$M2PLANET_SHA" work/M2-Planet  --recurse-submodules
clone_pin "$MESCC_URL"    "$MESCC_SHA"    work/mescc-tools --recurse-submodules
clone_pin "$M2LIBC_URL"   "$M2LIBC_SHA"   work/M2libc

make -C work/M2-Planet  -s M2-Planet CC=gcc >/dev/null 2>&1 || die "M2-Planet build failed"
make -C work/mescc-tools -s M1 hex2 CC=gcc  >/dev/null 2>&1 || die "mescc-tools build failed"
M2P=$BUGDIR/work/M2-Planet/bin/M2-Planet
M1B=$BUGDIR/work/mescc-tools/bin/M1
HEX2=$BUGDIR/work/mescc-tools/bin/hex2
[ -x "$M2P" ] && [ -x "$M1B" ] && [ -x "$HEX2" ] || die "toolchain binaries missing"
loud "built M2-Planet + M1 + hex2 with gcc"

# the pinned build source must itself carry the defect (ties PART A to the
# thing PART B actually runs).
grep -q 'SUB R12' <(func_body work/M2libc/armv7l/linux/unistd.c '^int unlink[ (]') || die "pinned unlink lost SUB R12"
if func_body work/M2libc/armv7l/linux/unistd.c '^int unlink[ (]' | grep -q 'LOAD32 R0 MEMORY'; then
  die "pinned M2libc unlink already dereferences -- the runtime legs would be vacuous"
fi

# build_prog <arch> <base-addr> <m2libc-dir> <src.c> <out-binary>
build_prog () {
  local arch="$1" base="$2" lib="$3" src="$4" out="$5"
  "$M2P" --architecture "$arch" \
    -f "$lib/sys/types.h" -f "$lib/stddef.h" -f "$lib/sys/utsname.h" \
    -f "$lib/$arch/linux/unistd.c" -f "$lib/$arch/linux/fcntl.c" -f "$lib/fcntl.c" \
    -f "$lib/$arch/linux/sys/stat.c" -f "$lib/ctype.c" -f "$lib/stdlib.c" \
    -f "$lib/stdarg.h" -f "$lib/stdio.h" -f "$lib/stdio.c" -f "$lib/bootstrappable.c" \
    -f "$src" -o "$out.M1" >/dev/null 2>&1 || die "M2-Planet failed ($arch)"
  "$M1B" -f "$lib/$arch/${arch}_defs.M1" -f "$lib/$arch/libc-full.M1" -f "$out.M1" \
    --little-endian --architecture "$arch" -o "$out.hex2" >/dev/null 2>&1 || die "M1 failed ($arch)"
  "$HEX2" -f "$lib/$arch/ELF-$arch.hex2" -f "$out.hex2" \
    --little-endian --architecture "$arch" --base-address "$base" -o "$out" >/dev/null 2>&1 || die "hex2 failed ($arch)"
  chmod +x "$out"
}

# run_probe <binary> <runner...> -> echoes "<exit> <SURVIVED|REMOVED>"
run_probe () {
  local bin="$1"; shift
  rm -f "$BUGDIR/work/victim-file"; : > "$BUGDIR/work/victim-file"
  [ -e "$BUGDIR/work/victim-file" ] || die "victim-file was not created (guard against a vacuous survive)"
  local rc=0
  ( cd "$BUGDIR/work" && "$@" "$bin" ) || rc=$?
  local surv=REMOVED; [ -e "$BUGDIR/work/victim-file" ] && surv=SURVIVED
  rm -f "$BUGDIR/work/victim-file"
  echo "$rc $surv"
}

# ---------------------------------------------------------------------------
banner "PART B -- RUNTIME on armv7l (qemu-user): unlink fails, the file survives"
# ---------------------------------------------------------------------------
build_prog armv7l 0x00010000 "$BUGDIR/work/M2libc" "$BUGDIR/test-unlink.c" work/probe-armv7l
file work/probe-armv7l | grep -q 'ARM' || die "armv7l probe is not an ARM ELF"
read arm_rc arm_surv <<<"$(run_probe "./probe-armv7l" qemu-arm-static)"
loud "armv7l: exit=$arm_rc  victim=$arm_surv   (exit bit1=unlink failed, bit0=access failed)"
[ "$arm_surv" = SURVIVED ] || die "armv7l: the file was removed -- bug not reproduced"
[ "$arm_rc" = 2 ]          || die "armv7l: expected exit 2 (access ok, unlink failed), got $arm_rc"
loud "REPRODUCED: access() found the file (exit bit0 clear) but unlink() failed and the file survives"

# ---------------------------------------------------------------------------
banner "PART C -- CONTROL on amd64 (native): the SAME program removes the file"
# ---------------------------------------------------------------------------
build_prog amd64 0x00600000 "$BUGDIR/work/M2libc" "$BUGDIR/test-unlink.c" work/probe-amd64
file work/probe-amd64 | grep -q 'x86-64' || die "amd64 probe is not an x86-64 ELF"
read x86_rc x86_surv <<<"$(run_probe "./probe-amd64")"
loud "amd64: exit=$x86_rc  victim=$x86_surv"
[ "$x86_surv" = REMOVED ] || die "amd64: the file survived -- control is not clean"
[ "$x86_rc" = 0 ]         || die "amd64: expected exit 0 (both syscalls succeed), got $x86_rc"
loud "CONTROL CLEAN: amd64 unlink() dereferences and removes the file; the defect is armv7l-specific"

# ---------------------------------------------------------------------------
banner "PART D -- FIX: add the one missing 'LOAD32 R0 MEMORY' line to unlink()"
# ---------------------------------------------------------------------------
cp -r work/M2libc work/M2libc-fixed
before=$(grep -c 'LOAD32 R0 MEMORY' work/M2libc-fixed/armv7l/linux/unistd.c)
# insert the dereference ONLY into unlink() -- keyed on the SUB R12 line
# immediately followed by unlink's syscall (!10), so no sibling is touched.
perl -0pi -e 's/("!4 R0 SUB R12 ARITH_ALWAYS"\n\s*)("!10 R7 LOADI8_ALWAYS")/${1}"!0 R0 LOAD32 R0 MEMORY"\n\t    ${2}/' \
  work/M2libc-fixed/armv7l/linux/unistd.c
after=$(grep -c 'LOAD32 R0 MEMORY' work/M2libc-fixed/armv7l/linux/unistd.c)
[ "$after" = "$((before + 1))" ] || die "fix changed $((after - before)) sites, expected exactly 1"
func_body work/M2libc-fixed/armv7l/linux/unistd.c '^int unlink[ (]' | grep -q 'LOAD32 R0 MEMORY' \
  || die "fix did not land inside unlink()"
loud "inserted exactly one 'LOAD32 R0 MEMORY' line, inside unlink()"
build_prog armv7l 0x00010000 "$BUGDIR/work/M2libc-fixed" "$BUGDIR/test-unlink.c" work/probe-fixed
read fix_rc fix_surv <<<"$(run_probe "./probe-fixed" qemu-arm-static)"
loud "armv7l (fixed): exit=$fix_rc  victim=$fix_surv"
[ "$fix_surv" = REMOVED ] || die "fixed unlink still did not remove the file"
[ "$fix_rc" = 0 ]         || die "fixed build: expected exit 0, got $fix_rc"
loud "FIX VERIFIED: the single missing deref line makes armv7l unlink() remove the file"

banner "VERDICT"
loud "BUG REPRODUCED: M2libc armv7l unlink() passes &filename, not filename"
loud "(missing 'LOAD32 R0 MEMORY').  Under qemu-user a real chain-built program"
loud "cannot delete a file that access() -- its correctly-dereferencing sibling"
loud "on the same path -- finds; the identical amd64 build deletes it; and adding"
loud "the one missing line fixes armv7l."
echo "PASS: m2libc-armv7l-unlink-arg reproduced (armv7l survives, amd64 removes, 1-line fix works)"
