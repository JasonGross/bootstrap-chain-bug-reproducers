#!/usr/bin/env bash
# builder-hex0-riscv64-unified-seed -- a DEMONSTRATION, not a bug reproducer.
#
# The evidence for a contribution offer: a SINGLE riscv64 builder-hex0 seed --
# one hand-auditable hex0 machine-code image -- that boots on TWO different
# riscv64 machines (QEMU 'virt' and TinyEMU) and runs the real stage0-posix
# chain to M2-Planet on both, producing a BYTE-IDENTICAL result.
#
# This is the UNIFIED-seed sibling of bug 15.  Where bug 15 shows two
# independently-targeted seeds (one per machine) agree, this shows ONE seed
# that detects its machine at runtime and agrees with itself across machines.
# One seed removes a variable rather than comparing two artefacts, and the
# claim -- equality of the two outputs -- reproduces for anyone who clones
# this, citing no fixed hash.
#
# GREEN == all of:
#   (a) ROUND-TRIP: the seed's .S -> .hex0 holds (the hex a human audits is
#       provably the hex that runs), asserted by the fork's own oracle -- the
#       booted binary is decoded from the checked-in hex0.
#   (b) ONE seed boots on QEMU 'virt' AND on TinyEMU, at 128 MiB on BOTH.  The
#       128 MiB is part of the claim: the seed carries a capability layer
#       (an M-mode kexec service) that imposes NOTHING on the bootstrap path,
#       so the stage0 chain still runs on a small machine.
#   (c) PROBE DISCRIMINATED: the same binary printed the qemu-virt banner on
#       QEMU and the TinyEMU banner on TinyEMU -- each on that machine's own
#       console.  Same-binary agreement that got lucky on one machine would
#       fail this.
#   (d) both runs produced a NON-EMPTY M2-Planet and the two are
#       BYTE-IDENTICAL to each other.
#
# Inverted convention vs the bug reproducers: here GREEN means the
# demonstration SUCCEEDED (see the repo README's note on demonstration jobs).
#
# Red-for-the-right-reason -- verified once at authoring time (2026-07-26),
# NOT run on every CI invocation:
#   ABLATE=1 feeds the QEMU log where the TinyEMU log belongs, simulating a
#     probe that failed to discriminate (both legs looked like qemu-virt).
#     Observed RED with the named assertion
#       "PROBE DID NOT DISCRIMINATE: TinyEMU leg is missing its banner".
#   ABLATE=2 flips one byte of the TinyEMU M2 before the equality check.
#     Observed RED with the named assertion
#       "the two M2-Planet artifacts are NOT byte-identical".
#   The unablated path (ABLATE unset) is GREEN.  Each ABLATE red is a NAMED
#   assertion, not a build error or a missing artefact -- so a vacuous harness
#   that always passed would be caught.
cd "$(dirname "$0")"
. ../common.sh
BUGDIR=$PWD

for t in qemu-system-riscv64 xxd riscv64-linux-gnu-as riscv64-linux-gnu-ld \
         riscv64-linux-gnu-objcopy make git; do
  command -v "$t" >/dev/null || die "need $t (see the workflow for apt names)"
done

# --- pins ------------------------------------------------------------------
# The unified seed under offer (fork branch riscv64-probing-seed-capabilities:
# the census-unified probing seed plus the additive capability layer).
BH0_URL=https://github.com/JasonGross/builder-hex0
BH0_COMMIT=9589b9be01580b7461c9fff4e7d80ed384804aff   # branch riscv64-probing-seed-capabilities
BH0_BRANCH=riscv64-probing-seed-capabilities
# stage0-posix inputs, pinned to the same mutually-consistent set as bug 15.
# We fetch the four submodules the riscv64 chain needs directly and skip the
# superproject (its mescc-tools submodule lives on git.savannah.nongnu.org,
# unneeded here and intermittently unreachable).
S0_RISCV64=4688bc66bdfd00efd5964350c9d76bdb90a0f72e   # oriansj/stage0-posix-riscv64
S0_M2LIBC=95e9006162944febf5ca9ad8a78a1d24e301160e    # oriansj/M2libc
S0_M2PLANET=cadf52af3d235b2f7745ee10f50e6dd27601209a  # oriansj/M2-Planet
S0_SEEDS=cedec6b8066d1db229b6c77d42d120a23c6980ed     # oriansj/bootstrap-seeds
# TinyEMU: Bellard's last release.
TE_URL=https://bellard.org/tinyemu/tinyemu-2019-12-21.tar.gz
TE_SHA=be8351f2121819b3172fcedce5cb1826fa12c87da1b7ed98f269d3e802a05555

# The discriminating banners the seed's runtime machine-probe prints, verbatim
# from builder-hex0-riscv64-stage2.S.
QEMU_BANNER='builder-hex0-riscv64: detected qemu-virt (PMP present)'
TEMU_BANNER='builder-hex0-riscv64: detected TinyEMU (no PMP)'

mkdir -p work

fetch_git () { # fetch_git <url> <commit> <dir>
  local url="$1" commit="$2" dir="$3"
  if [ ! -d "$dir/.git" ]; then
    git init -q "$dir"
    git -C "$dir" fetch -q --depth 1 "$url" "$commit" 2>/dev/null \
      || { loud "shallow by-sha fetch refused for $url; full fetch"; git -C "$dir" fetch -q "$url"; }
    git -C "$dir" checkout -q "$commit" 2>/dev/null || git -C "$dir" checkout -q FETCH_HEAD
  fi
}

banner "1/7 -- THE UNIFIED SEED UNDER OFFER"
fetch_git "$BH0_URL" "$BH0_COMMIT" work/builder-hex0
[ "$(git -C work/builder-hex0 rev-parse HEAD)" = "$BH0_COMMIT" ] || die "wrong builder-hex0 commit"
git -C work/builder-hex0 log -1 --format='pinned: %H %s'
BH0=$PWD/work/builder-hex0
loud "the ONE checked-in seed (hand-auditable hex0, serves both machines):"
ls -l "$BH0"/builder-hex0-riscv64-stage2.hex0 | sed 's/^/    /'
[ -e "$BH0/builder-hex0-riscv64-tinyemu-stage2.hex0" ] \
  && die "a per-machine second seed is present -- this demonstration is for the UNIFIED single seed"
loud "confirmed: no per-machine second seed on this branch"

banner "2/7 -- ROUND-TRIP: the .S a human audits IS the .hex0 that runs"
# The fork's own oracle: assemble stage2.S, regenerate hex0 from the ELF, diff
# it against the checked-in hex0, and cmp the .S-built .bin against the .bin
# decoded from the checked-in hex0.  A clean run means the binary booted below
# is exactly the checked-in hex0, which is exactly the audited .S.
make -C "$BH0" XXD=xxd riscv64-stage2-oracle > work/roundtrip.log 2>&1 \
  || { tail -30 work/roundtrip.log; die "ROUND-TRIP FAILED: stage2.S does not match the checked-in stage2.hex0"; }
loud "round-trip holds: stage2.S == stage2.hex0 == booted binary"
# Boot the binary decoded from the AUDITED hex0 (the oracle proved it == the .S).
SEED="$BH0/BUILD/builder-hex0-riscv64-stage2-from-hex0.bin"
[ -s "$SEED" ] || die "seed binary missing after round-trip"
printf '    %-46s %6s bytes  sha256 %s...\n' "$(basename "$SEED")" \
  "$(wc -c < "$SEED")" "$(sha256sum "$SEED" | cut -c1-16)"

banner "3/7 -- STAGE0-POSIX INPUTS (pinned, public, unmodified)"
fetch_git https://github.com/oriansj/stage0-posix-riscv64.git "$S0_RISCV64" work/s0/riscv64
fetch_git https://github.com/oriansj/M2-Planet.git            "$S0_M2PLANET" work/s0/M2-Planet
fetch_git https://github.com/oriansj/bootstrap-seeds.git      "$S0_SEEDS"    work/s0/bootstrap-seeds
fetch_git https://github.com/oriansj/M2libc.git               "$S0_M2LIBC"   work/s0/M2libc
S0=$PWD/work/s0
for f in riscv64/mescc-tools-mini-kaem.kaem M2-Planet/cc.c M2libc/bootstrappable.c \
         bootstrap-seeds/POSIX/riscv64/hex0_riscv64.hex0; do
  [ -f "$S0/$f" ] || die "missing stage0-posix input: $f"
done
loud "stage0-posix riscv64 chain inputs present"

banner "4/7 -- BUILD TinyEMU (Bellard's last release, pinned)"
fetch "$TE_URL" "$TE_SHA" work/tinyemu.tar.gz
[ -d work/tinyemu-src ] || { mkdir -p work/tinyemu-src; tar -C work/tinyemu-src -xf work/tinyemu.tar.gz --strip-components=1; }
if [ ! -x work/tinyemu-src/temu ]; then
  make -C work/tinyemu-src -j"$(nproc)" temu CONFIG_SDL= CONFIG_FS_NET= > work/temu-build.log 2>&1 \
    || { tail -20 work/temu-build.log; die "temu build failed"; }
fi
TEMU=$PWD/work/tinyemu-src/temu
loud "temu built: $("$TEMU" 2>&1 | head -1)"

banner "5/7 -- ONE srcfs DISK IMAGE, USED BY BOTH MACHINES"
# Faithful to the upstream test harness: a BXHDRSV2 control block in sector 0,
# then a script of `src LEN PATH` records carrying the stage0-posix sources.
SCRIPT=work/BUILD/chain.script
MINI=work/BUILD/mini.kaem
mkdir -p work/BUILD
sed -n '1,78p' "$S0/riscv64/mescc-tools-mini-kaem.kaem" > "$MINI"
printf '%s\n' './riscv64/artifact/catm /dev/hda ./riscv64/artifact/M2' >> "$MINI"
: > "$SCRIPT"
add () { local src="$1" tgt="$2" n; n=$(wc -c < "$src")
         { printf 'src %s /%s\n' "$n" "$tgt"; cat "$src"; printf '\n'; } >> "$SCRIPT"; }
add "$S0/bootstrap-seeds/POSIX/riscv64/hex0_riscv64.hex0" riscv64/hex0_riscv64.hex0
add "$S0/riscv64/kaem-minimal.hex0"    riscv64/kaem-minimal.hex0
add "$S0/riscv64/hex1_riscv64.hex0"    riscv64/hex1_riscv64.hex0
add "$S0/riscv64/hex2_riscv64.hex1"    riscv64/hex2_riscv64.hex1
add "$S0/riscv64/catm_riscv64.hex2"    riscv64/catm_riscv64.hex2
add "$S0/riscv64/ELF-riscv64.hex2"     riscv64/ELF-riscv64.hex2
add "$S0/riscv64/M0_riscv64.hex2"      riscv64/M0_riscv64.hex2
add "$S0/riscv64/riscv64_defs.M1"      riscv64/riscv64_defs.M1
add "$S0/riscv64/cc_riscv64.M1"        riscv64/cc_riscv64.M1
add "$S0/riscv64/libc-core.M1"         riscv64/libc-core.M1
add "$S0/M2libc/riscv64/linux/bootstrap.c" M2libc/riscv64/linux/bootstrap.c
add "$S0/M2libc/bootstrappable.c"      M2libc/bootstrappable.c
for f in cc.h cc_globals.c cc_reader.c cc_strings.c cc_types.c cc_emit.c cc_core.c cc_macro.c cc.c; do
  add "$S0/M2-Planet/$f" "M2-Planet/$f"
done
add "$MINI" riscv64/mini.kaem
printf '%s\n' \
  'hex0 /riscv64/hex0_riscv64.hex0 /riscv64/artifact/hex0' \
  'hex0 /riscv64/kaem-minimal.hex0 /riscv64/artifact/kaem-0' \
  '/riscv64/artifact/kaem-0 /riscv64/mini.kaem' 'f' 'halt' >> "$SCRIPT"

wu64 () { local v=$1 c=0 o; while [ "$c" -lt 8 ]; do o=$(printf '%03o' "$((v & 255))")
          printf '%b' "\\$o"; v=$((v >> 8)); c=$((c + 1)); done; }
SB=$(wc -c < "$SCRIPT")
build_image () { # build_image <path>
  truncate -s 4194304 "$1"
  { printf 'BXHDRSV2'; wu64 1; wu64 "$SB"; } > work/BUILD/hdr
  dd if=work/BUILD/hdr of="$1" conv=notrunc status=none
  dd if="$SCRIPT" of="$1" bs=512 seek=1 conv=notrunc status=none
}
# Each machine gets its OWN copy: the chain's final step writes M2 over
# /dev/hda from sector 0, destroying the control block it booted from.
rm -f work/BUILD/chain-qemu.img work/BUILD/chain-temu.img
build_image work/BUILD/chain-qemu.img
build_image work/BUILD/chain-temu.img
cmp work/BUILD/chain-qemu.img work/BUILD/chain-temu.img \
  || die "the two disk images differ -- they must be identical"
loud "one image built (script $SB B), copied per machine; the copies are identical"

banner "6/7 -- RUN THE SAME SINGLE SEED ON BOTH MACHINES (128 MiB each)"
extract_m2 () { # extract_m2 <log> <img> <out>
  local log="$1" img="$2" out="$3" lh len
  grep -q 'shell and flush passed' "$log" || { tail -15 "$log"; die "no flush marker in $log"; }
  lh=$(grep -E '^[0-9A-F]{16}$' "$log" | tail -1)
  [ -n "$lh" ] || { tail -15 "$log"; die "no output length in $log"; }
  len=$((16#$lh))
  dd if="$img" of="$out" bs=1 count="$len" status=none
  echo "$len"
}
QLOG=work/BUILD/qemu.log
TLOG=work/BUILD/temu.log

loud "QEMU virt, 128 MiB, the unified seed ..."
timeout 900 qemu-system-riscv64 -M virt -m 128M -smp 1 -nographic -bios none \
  -kernel "$SEED" \
  -drive if=none,file=work/BUILD/chain-qemu.img,format=raw,id=hd0 \
  -device virtio-blk-device,drive=hd0 -no-reboot > "$QLOG" 2>&1 || true
LEN_Q=$(extract_m2 "$QLOG" work/BUILD/chain-qemu.img work/BUILD/M2-qemu)

loud "TinyEMU, 128 MiB, the SAME unified seed ..."
cat > work/BUILD/temu.cfg <<EOF
{ version: 1, machine: "riscv64", memory_size: 128,
  bios: "$SEED",
  drive0: { file: "$PWD/work/BUILD/chain-temu.img" } }
EOF
# -rw is required: TinyEMU otherwise sends writes to a COW overlay and the
# builder's flushed output never reaches the file.
timeout 900 "$TEMU" -rw work/BUILD/temu.cfg > "$TLOG" 2>&1 || true
LEN_T=$(extract_m2 "$TLOG" work/BUILD/chain-temu.img work/BUILD/M2-temu)

banner "7/7 -- ASSERTIONS"
# (c) the runtime probe discriminated: the SAME binary printed the correct
# per-machine banner on each machine's own console.
assert_discriminated () { # <label> <log> <want-banner> <other-banner>
  local m="$1" log="$2" want="$3" other="$4"
  grep -qF "$want" "$log" || { tail -15 "$log"; die "PROBE DID NOT DISCRIMINATE: $m leg is missing its banner"; }
  grep -qF "$other" "$log" && die "PROBE DID NOT DISCRIMINATE: $m leg also printed the other machine's banner"
  return 0
}
# ABLATE=1: feed the QEMU log where the TinyEMU log belongs (probe "did not
# discriminate").  The TinyEMU banner is then absent -> named assertion fires.
if [ "${ABLATE:-0}" = 1 ]; then
  loud "ABLATE=1: TinyEMU leg fed the QEMU log -- the discrimination check MUST fail"
  TLOG="$QLOG"
fi
assert_discriminated "QEMU virt" "$QLOG" "$QEMU_BANNER" "$TEMU_BANNER"
assert_discriminated "TinyEMU"   "$TLOG" "$TEMU_BANNER" "$QEMU_BANNER"
loud "probe discriminated: one binary, qemu-virt banner on QEMU, TinyEMU banner on TinyEMU"

# (d) stimulus present, then byte-identical.  Check both outputs exist and are
# non-empty BEFORE comparing: cmp of two absent files would pass trivially.
[ -s work/BUILD/M2-qemu ] || die "no M2-Planet from the QEMU run (empty/absent)"
[ -s work/BUILD/M2-temu ] || die "no M2-Planet from the TinyEMU run (empty/absent)"
[ "$LEN_Q" -gt 100000 ] || die "implausibly small M2 from QEMU ($LEN_Q B)"
# ABLATE=2: corrupt one byte of the TinyEMU M2 -> the equality check must fire.
if [ "${ABLATE:-0}" = 2 ]; then
  loud "ABLATE=2: flipping one byte of M2-temu -- the equality check MUST fail"
  printf '\377' | dd of=work/BUILD/M2-temu bs=1 seek=0 count=1 conv=notrunc status=none
fi
[ "$LEN_Q" = "$LEN_T" ] || die "M2-Planet lengths differ: qemu $LEN_Q vs temu $LEN_T"
cmp work/BUILD/M2-qemu work/BUILD/M2-temu || die "the two M2-Planet artifacts are NOT byte-identical"

banner "RESULT"
printf '  QEMU virt (128 MiB) : M2-Planet %s bytes  sha256 %s\n' "$LEN_Q" "$(sha256sum work/BUILD/M2-qemu | cut -d' ' -f1)"
printf '  TinyEMU   (128 MiB) : M2-Planet %s bytes  sha256 %s\n' "$LEN_T" "$(sha256sum work/BUILD/M2-temu | cut -d' ' -f1)"

banner "VERDICT"
loud "DEMONSTRATION SUCCEEDED: ONE unified riscv64 hex0 seed, booted on two"
loud "different riscv64 machines (QEMU virt and TinyEMU) at 128 MiB from an"
loud "identical disk image, detected its machine at runtime (distinct banner"
loud "per machine) and ran the real stage0-posix chain to a BYTE-IDENTICAL"
loud "M2-Planet ($LEN_Q bytes)."
loud "The .S the human audits round-trips to the hex0 that ran, and the"
loud "capability layer imposes nothing on the bootstrap (128 MiB suffices)."
echo "PASS: builder-hex0-riscv64-unified-seed demonstrated"
