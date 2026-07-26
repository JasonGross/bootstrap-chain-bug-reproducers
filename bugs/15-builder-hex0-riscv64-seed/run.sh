#!/usr/bin/env bash
# builder-hex0-riscv64-seed -- a DEMONSTRATION, not a bug reproducer.
#
# This is the evidence attached to a contribution offer: a riscv64 port of
# builder-hex0 (an auditable hex0 machine-code seed) that boots on TWO
# different riscv64 machines and runs the real stage0-posix chain to
# M2-Planet on both.
#
# GREEN == both seeds boot, both run the identical stage0-posix chain from the
# same disk image, and the M2-Planet each produces is BYTE-IDENTICAL to the
# other.  That equality is the whole claim: retargeting the seed to a second
# machine changed how the builder does I/O and nothing about what the chain
# computes.
#
# Note the inverted convention vs the rest of this repo: here green means the
# demonstration SUCCEEDED (see the repo README's note on demonstration jobs).
cd "$(dirname "$0")"
. ../common.sh
BUGDIR=$PWD

for t in qemu-system-riscv64 xxd; do
  command -v "$t" >/dev/null || die "need $t"
done

# --- pins ------------------------------------------------------------------
# The seed under offer (our fork's riscv64 port branch).
BH0_URL=https://github.com/JasonGross/builder-hex0
BH0_COMMIT=dfc103e62f83ecdab29e2eda8a802ac7ddf205bb   # branch riscv64-port
# stage0-posix, by submodule, pinned to a mutually consistent set.  We fetch
# the four submodules the riscv64 chain actually needs DIRECTLY from GitHub and
# skip the superproject: its `mescc-tools` submodule lives on
# git.savannah.nongnu.org, which the chain does not need and which has been
# unreachable during this work.
S0_RISCV64=4688bc66bdfd00efd5964350c9d76bdb90a0f72e   # oriansj/stage0-posix-riscv64
S0_M2LIBC=95e9006162944febf5ca9ad8a78a1d24e301160e    # oriansj/M2libc (see note below)
S0_M2PLANET=cadf52af3d235b2f7745ee10f50e6dd27601209a  # oriansj/M2-Planet
S0_SEEDS=cedec6b8066d1db229b6c77d42d120a23c6980ed     # oriansj/bootstrap-seeds
# TinyEMU: Bellard's last release.
TE_URL=https://bellard.org/tinyemu/tinyemu-2019-12-21.tar.gz
TE_SHA=be8351f2121819b3172fcedce5cb1826fa12c87da1b7ed98f269d3e802a05555

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

banner "1/6 -- THE SEED UNDER OFFER"
fetch_git "$BH0_URL" "$BH0_COMMIT" work/builder-hex0
[ "$(git -C work/builder-hex0 rev-parse HEAD)" = "$BH0_COMMIT" ] || die "wrong builder-hex0 commit"
git -C work/builder-hex0 log -1 --format='pinned: %H %s'
BH0=$PWD/work/builder-hex0
loud "the two checked-in seeds (hand-auditable hex0, one per machine):"
ls -l "$BH0"/builder-hex0-riscv64-stage2.hex0 \
      "$BH0"/builder-hex0-riscv64-tinyemu-stage2.hex0 | sed 's/^/    /'

banner "2/6 -- STAGE0-POSIX INPUTS (pinned, public, unmodified)"
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

banner "3/6 -- BUILD BOTH SEEDS FROM THEIR CHECKED-IN hex0"
mkdir -p work/BUILD
for s in builder-hex0-riscv64-stage2 builder-hex0-riscv64-tinyemu-stage2; do
  cut "$BH0/$s.hex0" -f1 -d'#' | cut -f1 -d';' | xxd -r -p > "work/BUILD/$s.bin"
  printf '    %-42s %6s bytes  sha256 %s\n' "$s.bin" \
    "$(wc -c < "work/BUILD/$s.bin")" "$(sha256sum "work/BUILD/$s.bin" | cut -c1-16)…"
done

banner "4/6 -- BUILD TinyEMU (Bellard's last release, pinned)"
fetch "$TE_URL" "$TE_SHA" work/tinyemu.tar.gz
[ -d work/tinyemu-src ] || { mkdir -p work/tinyemu-src; tar -C work/tinyemu-src -xf work/tinyemu.tar.gz --strip-components=1; }
if [ ! -x work/tinyemu-src/temu ]; then
  make -C work/tinyemu-src -j"$(nproc)" temu CONFIG_SDL= CONFIG_FS_NET= > work/temu-build.log 2>&1 \
    || { tail -20 work/temu-build.log; die "temu build failed"; }
fi
TEMU=$PWD/work/tinyemu-src/temu
loud "temu built: $("$TEMU" 2>&1 | head -1)"

banner "5/6 -- BUILD ONE srcfs DISK IMAGE, USED BY BOTH MACHINES"
# Faithful to the upstream test harness: a BXHDRSV2 control block in sector 0,
# then a script of `src LEN PATH` records carrying the stage0-posix sources.
SCRIPT=work/BUILD/chain.script
MINI=work/BUILD/mini.kaem
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
# /dev/hda starting at sector 0, destroying the control block it booted from.
rm -f work/BUILD/chain-qemu.img work/BUILD/chain-temu.img
build_image work/BUILD/chain-qemu.img
build_image work/BUILD/chain-temu.img
cmp work/BUILD/chain-qemu.img work/BUILD/chain-temu.img \
  || die "the two disk images differ -- they must be identical"
loud "one image built (script $SB B), copied per machine; the copies are identical"

banner "6/6 -- RUN THE SAME CHAIN ON BOTH MACHINES"
extract_m2 () { # extract_m2 <log> <img> <out>
  local log="$1" img="$2" out="$3" lh len
  grep -q 'shell and flush passed' "$log" || { tail -15 "$log"; die "no flush marker in $log"; }
  lh=$(grep -E '^[0-9A-F]{16}$' "$log" | tail -1)
  [ -n "$lh" ] || { tail -15 "$log"; die "no output length in $log"; }
  len=$((16#$lh))
  dd if="$img" of="$out" bs=1 count="$len" status=none
  echo "$len"
}

loud "QEMU virt + the baseline seed ..."
timeout 900 qemu-system-riscv64 -M virt -m 128M -smp 1 -nographic -bios none \
  -kernel work/BUILD/builder-hex0-riscv64-stage2.bin \
  -drive if=none,file=work/BUILD/chain-qemu.img,format=raw,id=hd0 \
  -device virtio-blk-device,drive=hd0 -no-reboot > work/BUILD/qemu.log 2>&1 || true
LEN_Q=$(extract_m2 work/BUILD/qemu.log work/BUILD/chain-qemu.img work/BUILD/M2-qemu)

loud "TinyEMU + the retargeted seed ..."
cat > work/BUILD/temu.cfg <<EOF
{ version: 1, machine: "riscv64", memory_size: 2048,
  bios: "$PWD/work/BUILD/builder-hex0-riscv64-tinyemu-stage2.bin",
  drive0: { file: "$PWD/work/BUILD/chain-temu.img" } }
EOF
# -rw is required: TinyEMU otherwise sends writes to a COW overlay and the
# builder's flushed output never reaches the file.
timeout 900 "$TEMU" -rw work/BUILD/temu.cfg > work/BUILD/temu.log 2>&1 || true
LEN_T=$(extract_m2 work/BUILD/temu.log work/BUILD/chain-temu.img work/BUILD/M2-temu)

banner "RESULT"
printf '  QEMU virt  : M2-Planet %s bytes  sha256 %s\n' "$LEN_Q" "$(sha256sum work/BUILD/M2-qemu | cut -d' ' -f1)"
printf '  TinyEMU    : M2-Planet %s bytes  sha256 %s\n' "$LEN_T" "$(sha256sum work/BUILD/M2-temu | cut -d' ' -f1)"
[ "$LEN_Q" -gt 100000 ] || die "implausibly small M2 from QEMU ($LEN_Q B)"
[ "$LEN_Q" = "$LEN_T" ] || die "lengths differ: qemu $LEN_Q vs temu $LEN_T"
cmp work/BUILD/M2-qemu work/BUILD/M2-temu || die "the two M2 artifacts are NOT byte-identical"

banner "VERDICT"
loud "DEMONSTRATION SUCCEEDED: two independently-targeted hex0 seeds, booted on"
loud "two different riscv64 machines (QEMU virt and TinyEMU) from an identical"
loud "disk image, each ran the real stage0-posix chain and produced a"
loud "BYTE-IDENTICAL M2-Planet ($LEN_Q bytes)."
loud "The retarget changed how the builder performs console/disk I/O and"
loud "nothing about what the chain computes -- which is the property that"
loud "makes the second machine target reviewable."
echo "PASS: builder-hex0-riscv64-seed demonstrated"
