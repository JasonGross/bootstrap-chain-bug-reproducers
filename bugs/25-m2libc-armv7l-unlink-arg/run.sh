#!/usr/bin/env bash
# m2libc-armv7l-unlink-arg: three M2libc armv7l syscall wrappers hand the kernel
# &arg instead of arg.  In M2libc/armv7l/linux/unistd.c the wrappers fetch each
# stack-passed argument with the pair
#     "!4 R0 SUB R12 ARITH_ALWAYS"     ; R0 = &arg   (address of the slot)
#     "!0 R0 LOAD32 R0 MEMORY"         ; R0 = *R0    (the argument value)
# Three wrappers have the first line but NOT the second, so they pass the
# ADDRESS of the stack slot instead of its contents -- one copy-paste omission
# repeated three times:
#     unlink(char* filename)   syscall !10   -> kernel gets &filename
#     chroot(char const* path) syscall !61   -> kernel gets &path
#     close(int fd)            syscall !6     -> kernel gets &fd
# Their arg-taking siblings access()/chdir()/symlink() all carry the LOAD32,
# and every other architecture (x86/amd64/riscv32/riscv64 dereference; aarch64
# needs no load) is correct -- this is armv7l-only.
#
# GREEN == the bug REPRODUCES:
#   A  PREMISE (live M2libc HEAD, re-checked every run so a fix goes red):
#      unlink()/chroot()/close() each carry "SUB R12" + their syscall number
#      but NO "LOAD32 R0 MEMORY", while access()/chdir()/symlink() all do.
#   B  RUNTIME unlink (armv7l, qemu-user): a real C program built through the
#      real M2-Planet -> M1 -> hex2 chain against pinned M2libc calls access()
#      and unlink() on a file that DEMONSTRABLY exists.  access() finds it,
#      unlink() fails, and the file SURVIVES.
#   B2 RUNTIME close (armv7l): open a file, close() the fd, then read() the
#      SAME fd.  A working close() closes the fd and the read fails; the broken
#      close() is a no-op, so the read SUCCEEDS.
#   B3 RUNTIME chroot (armv7l): access() then chroot() on the SAME string,
#      under qemu -strace.  chroot needs privilege we lack, but the trace shows
#      WHAT IT PASSES: access() gets the path string, chroot() gets a bogus
#      pointer.  (Argument, not return value -- so EPERM is irrelevant.)
#   C  CONTROL (amd64, native): the SAME unlink and close programs built the
#      SAME way for amd64 behave correctly -- the defect is the missing armv7l
#      dereference, not the programs.
#   D  FIX (armv7l): adding the one missing "LOAD32 R0 MEMORY" line to each of
#      the three wrappers -- and nothing else -- makes all three behave.
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

# the three accused wrappers, as "name:!syscall".  Used by PART A, the pinned-
# source check, and PART D so the set is stated exactly once.
ACCUSED="unlink:!10 chroot:!61 close:!6"

# ---------------------------------------------------------------------------
banner "PART A -- premise re-check against LIVE M2libc HEAD"
# ---------------------------------------------------------------------------
# A pinned reproducer proves the bug existed at the pin; it cannot see that
# upstream has since fixed it.  Re-derive the accused signatures from the live
# default branch every run.  (host unreachable != bug fixed -- skip, per the
# common.sh convention, rather than a red that teaches nobody anything.)
if curl -fsSL --max-time 60 --retry 2 -o work/unistd-live.c "$M2LIBC_RAW" 2>/dev/null; then
  loud "fetched live M2libc armv7l/linux/unistd.c"
  for pair in $ACCUSED; do
    name=${pair%%:*}; sys=${pair##*:}
    B=$(func_body work/unistd-live.c "^int $name[ (]")
    echo ">>> live $name():"; echo "$B" | sed 's/^/    /'
    echo "$B" | grep -q 'SUB R12'         || die "live $name() no longer uses the SUB R12 arg idiom -- re-read"
    echo "$B" | grep -q "$sys R7 LOADI8"  || die "live $name() is no longer syscall $sys -- re-read"
    if echo "$B" | grep -q 'LOAD32 R0 MEMORY'; then
      die "live $name() NOW dereferences its argument -- upstream may have FIXED this; a human must re-read the report"
    fi
    loud "live $name(): SUB R12 + syscall $sys, and NO 'LOAD32 R0 MEMORY' -- the defect stands"
  done
  for sib in access chdir symlink; do
    B=$(func_body work/unistd-live.c "^int $sib[ (]")
    echo "$B" | grep -q 'LOAD32 R0 MEMORY' \
      || die "sibling $sib() lost its 'LOAD32 R0 MEMORY' -- the contrast changed; re-read"
    loud "sibling $sib(): carries 'LOAD32 R0 MEMORY' (correctly dereferences)"
  done
  loud "PREMISE CONFIRMED at HEAD: unlink/chroot (char*) and close (int fd) all lack 'LOAD32 R0 MEMORY'; access/chdir/symlink carry it"
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

# the pinned build source must itself carry the defect at all three sites
# (ties PART A to the thing the runtime legs actually run).
for pair in $ACCUSED; do
  name=${pair%%:*}
  B=$(func_body work/M2libc/armv7l/linux/unistd.c "^int $name[ (]")
  echo "$B" | grep -q 'SUB R12' || die "pinned $name lost SUB R12"
  if echo "$B" | grep -q 'LOAD32 R0 MEMORY'; then
    die "pinned M2libc $name already dereferences -- the runtime legs would be vacuous"
  fi
done

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

# run_unlink <binary> <runner...> -> echoes "<exit> <SURVIVED|REMOVED>"
run_unlink () {
  local bin="$1"; shift
  rm -f "$BUGDIR/work/victim-file"; : > "$BUGDIR/work/victim-file"
  [ -e "$BUGDIR/work/victim-file" ] || die "victim-file was not created (guard against a vacuous survive)"
  local rc=0
  ( cd "$BUGDIR/work" && "$@" "$bin" ) || rc=$?
  local surv=REMOVED; [ -e "$BUGDIR/work/victim-file" ] && surv=SURVIVED
  rm -f "$BUGDIR/work/victim-file"
  echo "$rc $surv"
}

# run_close <binary> <runner...> -> echoes exit code (1=read-after-close ok=BUG,
# 0=read failed=correct, 10=setup failure).
run_close () {
  local bin="$1"; shift
  printf 'DATA' > "$BUGDIR/work/close-victim"
  local rc=0
  ( cd "$BUGDIR/work" && "$@" "$bin" ) || rc=$?
  rm -f "$BUGDIR/work/close-victim"
  [ "$rc" = 10 ] && die "close probe setup failed: open() did not return a descriptor"
  echo "$rc"
}

# chroot_arg <binary> -> echoes the strace argument chroot() received (raw),
# after asserting access() -- the correct sibling -- received the marker.
chroot_marker_in_chroot_line () {
  local bin="$1"
  ( cd "$BUGDIR/work" && qemu-arm-static -strace "$bin" ) >/dev/null 2>work/chroot-trace.txt || true
  # chroot's decoded garbage arg contains control bytes, so the trace file is
  # "binary" to grep -- force text mode (-a) or it prints "matches" not lines.
  local acc chr
  acc=$(grep -aE ' access\(' work/chroot-trace.txt | head -1 || true)
  chr=$(grep -aE ' chroot\(' work/chroot-trace.txt | head -1 || true)
  [ -n "$acc" ] || die "no access() syscall in the trace -- strace format changed or the probe failed to run"
  [ -n "$chr" ] || die "no chroot() syscall in the trace -- chroot() was not reached"
  # display sanitised, to stderr, so this function's stdout is ONLY the 0/1
  # result the caller captures (the chroot arg is raw pointer bytes).
  echo "    access line: $(printf '%s' "$acc" | tr -c '[:print:]\t' '.')" >&2
  echo "    chroot line: $(printf '%s' "$chr" | tr -c '[:print:]\t' '.')" >&2
  echo "$acc" | grep -aq 'ZQXPATHMARKER' \
    || die "access() did not receive the marker string -- qemu no longer decodes char* args; chroot leg needs review"
  # echo 1 iff the chroot line contains the marker (i.e. chroot got the string)
  if echo "$chr" | grep -aq 'ZQXPATHMARKER'; then echo 1; else echo 0; fi
}

# ---------------------------------------------------------------------------
banner "PART B -- RUNTIME unlink (armv7l, qemu-user): unlink fails, file survives"
# ---------------------------------------------------------------------------
build_prog armv7l 0x00010000 "$BUGDIR/work/M2libc" "$BUGDIR/test-unlink.c" work/probe-unlink-armv7l
file work/probe-unlink-armv7l | grep -q 'ARM' || die "armv7l unlink probe is not an ARM ELF"
read arm_rc arm_surv <<<"$(run_unlink "./probe-unlink-armv7l" qemu-arm-static)"
loud "armv7l unlink: exit=$arm_rc  victim=$arm_surv   (exit bit1=unlink failed, bit0=access failed)"
[ "$arm_surv" = SURVIVED ] || die "armv7l: the file was removed -- unlink bug not reproduced"
[ "$arm_rc" = 2 ]          || die "armv7l: expected exit 2 (access ok, unlink failed), got $arm_rc"
loud "REPRODUCED: access() found the file (exit bit0 clear) but unlink() failed and the file survives"

# ---------------------------------------------------------------------------
banner "PART B2 -- RUNTIME close (armv7l): read after close() still succeeds"
# ---------------------------------------------------------------------------
build_prog armv7l 0x00010000 "$BUGDIR/work/M2libc" "$BUGDIR/test-close.c" work/probe-close-armv7l
file work/probe-close-armv7l | grep -q 'ARM' || die "armv7l close probe is not an ARM ELF"
close_arm_rc=$(run_close "./probe-close-armv7l" qemu-arm-static)
loud "armv7l close: exit=$close_arm_rc   (1=read after close succeeded, 0=read failed)"
[ "$close_arm_rc" = 1 ] || die "armv7l: read after close() failed -- close bug not reproduced (expected exit 1, got $close_arm_rc)"
loud "REPRODUCED: close() was a silent no-op -- the fd stayed open and read() still returned data"

# ---------------------------------------------------------------------------
banner "PART B3 -- RUNTIME chroot (armv7l, -strace): chroot gets a bogus pointer"
# ---------------------------------------------------------------------------
build_prog armv7l 0x00010000 "$BUGDIR/work/M2libc" "$BUGDIR/test-chroot.c" work/probe-chroot-armv7l
file work/probe-chroot-armv7l | grep -q 'ARM' || die "armv7l chroot probe is not an ARM ELF"
chr_has_marker=$(chroot_marker_in_chroot_line "./probe-chroot-armv7l")
[ "$chr_has_marker" = 0 ] \
  || die "chroot() DID receive the marker string -- upstream may have added the deref; a human must re-read"
loud "REPRODUCED: access() -- same string literal -- was handed the path, chroot() a bogus pointer"

# ---------------------------------------------------------------------------
banner "PART C -- CONTROL on amd64 (native): unlink removes, close closes"
# ---------------------------------------------------------------------------
build_prog amd64 0x00600000 "$BUGDIR/work/M2libc" "$BUGDIR/test-unlink.c" work/probe-unlink-amd64
file work/probe-unlink-amd64 | grep -q 'x86-64' || die "amd64 unlink probe is not an x86-64 ELF"
read x86_rc x86_surv <<<"$(run_unlink "./probe-unlink-amd64")"
loud "amd64 unlink: exit=$x86_rc  victim=$x86_surv"
[ "$x86_surv" = REMOVED ] || die "amd64: the file survived -- unlink control is not clean"
[ "$x86_rc" = 0 ]         || die "amd64: expected exit 0 (both syscalls succeed), got $x86_rc"

build_prog amd64 0x00600000 "$BUGDIR/work/M2libc" "$BUGDIR/test-close.c" work/probe-close-amd64
file work/probe-close-amd64 | grep -q 'x86-64' || die "amd64 close probe is not an x86-64 ELF"
close_x86_rc=$(run_close "./probe-close-amd64")
loud "amd64 close: exit=$close_x86_rc"
[ "$close_x86_rc" = 0 ] || die "amd64: read after close() succeeded -- close control is not clean (expected exit 0, got $close_x86_rc)"
loud "CONTROL CLEAN: on amd64 unlink() removes the file and close() closes the fd; the defect is armv7l-specific"

# ---------------------------------------------------------------------------
banner "PART D -- FIX: add the missing 'LOAD32 R0 MEMORY' to all three wrappers"
# ---------------------------------------------------------------------------
rm -rf work/M2libc-fixed; cp -r work/M2libc work/M2libc-fixed
F=work/M2libc-fixed/armv7l/linux/unistd.c
before=$(grep -c 'LOAD32 R0 MEMORY' "$F")
# insert the dereference after the SUB R12 line ONLY where it is immediately
# followed by one of the three accused syscalls (!6 close, !10 unlink, !61
# chroot), so no correct sibling is touched.
perl -0pi -e 's/("!4 R0 SUB R12 ARITH_ALWAYS"\n\s*)("!(?:6|10|61) R7 LOADI8_ALWAYS")/${1}"!0 R0 LOAD32 R0 MEMORY"\n\t    ${2}/g' "$F"
after=$(grep -c 'LOAD32 R0 MEMORY' "$F")
[ "$after" = "$((before + 3))" ] || die "fix changed $((after - before)) sites, expected exactly 3"
for name in unlink close chroot; do
  func_body "$F" "^int $name[ (]" | grep -q 'LOAD32 R0 MEMORY' || die "fix did not land inside $name()"
done
loud "inserted exactly three 'LOAD32 R0 MEMORY' lines (unlink, close, chroot); nothing else changed"

build_prog armv7l 0x00010000 "$BUGDIR/work/M2libc-fixed" "$BUGDIR/test-unlink.c" work/probe-unlink-fixed
read fu_rc fu_surv <<<"$(run_unlink "./probe-unlink-fixed" qemu-arm-static)"
loud "armv7l unlink (fixed): exit=$fu_rc  victim=$fu_surv"
[ "$fu_surv" = REMOVED ] && [ "$fu_rc" = 0 ] || die "fixed unlink still did not remove the file (exit=$fu_rc surv=$fu_surv)"

build_prog armv7l 0x00010000 "$BUGDIR/work/M2libc-fixed" "$BUGDIR/test-close.c" work/probe-close-fixed
fc_rc=$(run_close "./probe-close-fixed" qemu-arm-static)
loud "armv7l close (fixed): exit=$fc_rc"
[ "$fc_rc" = 0 ] || die "fixed close still let the read succeed (expected exit 0, got $fc_rc)"

build_prog armv7l 0x00010000 "$BUGDIR/work/M2libc-fixed" "$BUGDIR/test-chroot.c" work/probe-chroot-fixed
fchr_has_marker=$(chroot_marker_in_chroot_line "./probe-chroot-fixed")
loud "armv7l chroot (fixed): chroot line carries the marker string? $fchr_has_marker (1=yes)"
[ "$fchr_has_marker" = 1 ] || die "fixed chroot() still did not receive the path string"
loud "FIX VERIFIED: the three added deref lines make unlink remove, close close, and chroot receive its path"

banner "VERDICT"
loud "BUG REPRODUCED: three M2libc armv7l wrappers pass &arg, not arg (missing"
loud "'LOAD32 R0 MEMORY'): unlink(char*), chroot(char*), close(int fd)."
loud "  * unlink: a chain-built program cannot delete a file access() finds;"
loud "  * close:  the fd stays open and a post-close read() still succeeds;"
loud "  * chroot: -strace shows it handed the kernel a bogus pointer."
loud "The identical amd64 builds behave; adding the one missing line to each"
loud "of the three wrappers fixes armv7l.  One copy-paste omission, three sites."
echo "PASS: m2libc-armv7l-unlink-arg reproduced (unlink survives, close no-ops, chroot bogus-ptr; amd64 controls clean; 3-line fix works)"
