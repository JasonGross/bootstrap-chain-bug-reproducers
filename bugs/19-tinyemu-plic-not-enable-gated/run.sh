#!/usr/bin/env bash
# tinyemu-plic-not-enable-gated: TinyEMU's RISC-V PLIC (riscv_machine.c) models
# only the pending/served claim-and-complete latch.  It has NO per-context
# interrupt-enable registers, NO per-source priority registers, and NO
# per-context threshold -- the three gating mechanisms a spec-compliant PLIC
# uses to decide whether a source may be delivered to, and claimed by, a hart
# context.  plic_read returns 0 for every offset except the claim register
# (default: val = 0) and plic_write drops every write except a completion
# (default: break), so a guest can be interrupted by, and can claim, a source it
# never enabled.  On real silicon that is impossible; the divergence is not
# merely lenient -- it can MANUFACTURE a hang conformant hardware would not (see
# this bug's entry in the repository README).  This reproducer demonstrates
# the root property directly: the gating registers are absent.
#
# GREEN == all of these hold, on the verbatim pinned TinyEMU release:
#   SOURCE     temu's PLIC state is two 32-bit words (pending, served); the
#              source carries no enable/priority/threshold register at all, and
#              the claim is ctz32(pending & ~served) with no enable term.
#   BUG        an M-mode program that writes a known pattern to the PLIC
#              priority[5], enable[ctx0] and threshold[ctx0] registers on temu
#              reads back 0 from every one -- the registers do not exist.
#   CONTROL    the SAME program on stock qemu-system-riscv64 -M virt (a
#              spec-compliant, enable-gated SiFive PLIC) reads back exactly what
#              it wrote -- the registers are present.  The nonzero qemu readback
#              is also what proves the writes are a real stimulus, not a vacuous
#              read of a register that was 0 anyway.
#
# The CONTROL is the spec-compliant reference: qemu is the "version where the
# defect (missing gating) is absent".  The ablation (ABLATE=1) points temu's
# "registers absent" assertion at qemu's output; it MUST go red on the enable
# register, proving the harness would notice if temu were enable-gated.
#
# ABLATION EXECUTED 2026-07-26 (authoring-time, NOT run in CI -- the green badge
# above covers only the normal run).  Normal run: green, temu reads back
# PRIO5/EN0/THR0 = 0/0/0.  ABLATE=1: red for the right reason -- the check,
# pointed at qemu's spec-compliant output, sees the written 0x20 read back and
# dies at the enable-register assertion:
#   FATAL: temu enable readback was '00000020', expected 00000000 (if ABLATE=1
#   this is the reproducer correctly going red: a gated PLIC returns the written
#   value)
# So the green run's temu 00000000 is a real observation, not a check that
# cannot fail.  Compare your own `ABLATE=1 bash run.sh` against that line.
cd "$(dirname "$0")"
. ../common.sh
BUGDIR=$PWD

# The riscv64 cross compiler is used only freestanding; either gcc or clang
# works.  CI installs gcc-riscv64-linux-gnu (see the workflow).  Override
# RISCV_CC / RISCV_LD / RISCV_OBJCOPY to dry-run with a different toolchain.
RISCV_CC=${RISCV_CC:-riscv64-linux-gnu-gcc}
RISCV_LD=${RISCV_LD:-riscv64-linux-gnu-ld}
RISCV_OBJCOPY=${RISCV_OBJCOPY:-riscv64-linux-gnu-objcopy}
RVCFLAGS="-march=rv64imac -mabi=lp64 -mcmodel=medany -nostdlib -ffreestanding -fno-pic -O2 -Wall"

for t in $RISCV_CC $RISCV_LD $RISCV_OBJCOPY qemu-system-riscv64 gcc make curl; do
  command -v "$t" >/dev/null || die "need $t (see the workflow file for apt names)"
done

TE_URL=https://bellard.org/tinyemu/tinyemu-2019-12-21.tar.gz
TE_SHA=be8351f2121819b3172fcedce5cb1826fa12c87da1b7ed98f269d3e802a05555

# The three values the probe writes.  EN is a plain per-context bitmask (bit 5),
# so a spec-compliant PLIC stores it exactly; priority and threshold may be
# masked to the target's priority-bit width, so the control only requires them
# to be present (nonzero), while the enable register is checked exactly.
EN_EXPECT=00000020

mkdir -p work
cd work

# ---------------------------------------------------------------------------
banner "1/5 -- PREMISE: the pinned TinyEMU release still has the un-gated PLIC"
# ---------------------------------------------------------------------------
# TinyEMU ships as a tarball from one host (bellard.org): no VCS, no tracker, no
# mirror, and dormant since this 2019-12-21 release.  The "is this still true
# upstream?" check is therefore "is the release at that URL still the one we
# pinned?".  Unreachable host -> warn and carry on (a host being down says
# nothing about the model); reachable but changed -> re-check the property on
# the new tarball, loudly.
if curl -fsSL --max-time 60 --retry 2 -o live-tinyemu.tar.gz "$TE_URL"; then
  live_sha=$(sha256sum live-tinyemu.tar.gz | cut -d' ' -f1)
  if [ "$live_sha" = "$TE_SHA" ]; then
    loud "bellard.org still serves the pinned release ($TE_SHA)"
  else
    loud "!! bellard.org now serves a DIFFERENT tarball: $live_sha"
    loud "!! (a new TinyEMU release -- checking whether its PLIC is still un-gated;"
    loud "!!  the reproduction below still uses the pin)"
    rm -rf live-src && mkdir -p live-src
    tar -C live-src -xf live-tinyemu.tar.gz --strip-components=1
    if grep -qiE 'plic.*(enable|priorit|threshold)' live-src/riscv_machine.c; then
      die "the new TinyEMU release's riscv_machine.c now mentions a PLIC \
enable/priority/threshold -- it may have gained gating; a human must re-read \
the report before trusting the pinned reproduction"
    fi
    loud "the new release's PLIC still has no enable/priority/threshold registers"
  fi
else
  loud "UPSTREAM RE-CHECK SKIPPED: could not reach $TE_URL"
  loud "  (host unreachable != model changed -- not failing the run over it)"
fi

fetch "$TE_URL" "$TE_SHA" tinyemu.tar.gz
rm -rf temu-stock && mkdir -p temu-stock
tar -C temu-stock -xf tinyemu.tar.gz --strip-components=1
loud "TinyEMU $(cat temu-stock/VERSION 2>/dev/null || echo 2019-12-21)"

# ---------------------------------------------------------------------------
banner "2/5 -- SOURCE: temu's PLIC has no enable / priority / threshold at all"
# ---------------------------------------------------------------------------
RM=temu-stock/riscv_machine.c
echo "  PLIC state fields in riscv_machine.c:"
grep -nE 'plic_[a-z_]*irq' "$RM" | sed 's/^/    /'
# The entire PLIC state is two bitmask words plus the incoming IRQ signals.
grep -qE 'uint32_t[[:space:]]+plic_pending_irq,[[:space:]]*plic_served_irq;' "$RM" \
  || die "temu's PLIC state is not the two-bitmask-word shape this reproducer expects"
if grep -qiE 'plic.*(enable|priorit|threshold)|(enable|priorit|threshold).*plic' "$RM"; then
  die "riscv_machine.c mentions a PLIC enable/priority/threshold -- the premise \
(no gating registers) is stale; re-read the report"
fi
loud "no enable / priority / threshold register exists in temu's PLIC"
# The claim path: ctz32(pending & ~served), no enable term.
grep -qE 's->plic_pending_irq & ~s->plic_served_irq' "$RM" || die "claim mask is not pending & ~served"
grep -qE 'i = ctz32\(mask\);' "$RM" || die "claim does not use ctz32 of that mask"
loud "claim = ctz32(pending & ~served): any pending, not-yet-served source is claimable"
# And plic_read's default returns 0 -- which is what the probe will observe.
awk '/uint32_t plic_read/,/^}/' "$RM" | grep -qE 'default:' \
  && awk '/uint32_t plic_read/,/^}/' "$RM" | grep -qE 'val = 0;' \
  || die "plic_read no longer returns 0 for unmodelled offsets"
loud "plic_read returns 0 for every offset except the claim register"

# ---------------------------------------------------------------------------
banner "3/5 -- build temu from the pinned tarball (host gcc, no SDL/net/x86)"
# ---------------------------------------------------------------------------
# temu's Makefile uses `ifdef` for its CONFIG knobs.  An empty command-line
# override (`make CONFIG_SDL=`) makes `ifdef` false, so it disables them too;
# this script comments the lines in the Makefile instead, to the same effect.
# Keep CONFIG_INT128 -- host gcc has __int128.  We build only the `temu`
# target, which needs no SDL / libcurl / openssl.
sed -i -E 's/^(CONFIG_FS_NET=y)/#\1/; s/^(CONFIG_SDL=y)/#\1/; s/^(CONFIG_SLIRP=y)/#\1/; s/^(CONFIG_X86EMU=y)/#\1/' temu-stock/Makefile
grep -qE '^#CONFIG_SDL=y' temu-stock/Makefile || die "sed did not disable CONFIG_SDL (Makefile changed?)"
( cd temu-stock && make temu -j"$(nproc)" ) > temu-build.log 2>&1 \
  || { tail -30 temu-build.log; die "temu build failed"; }
TEMU=$PWD/temu-stock/temu
[ -x "$TEMU" ] || die "no temu binary after build"
# temu with no config prints usage and exits nonzero; don't let that abort us.
{ "$TEMU" 2>&1 || true; } | head -1 | sed 's/^/    /'

# ---------------------------------------------------------------------------
banner "4/5 -- build the PLIC register-presence probe (temu + qemu variants)"
# ---------------------------------------------------------------------------
build_probe () { # <define> <out-elf>
  local def="$1" out="$2"
  $RISCV_CC $RVCFLAGS $def -c "$BUGDIR/probe.c" -o probe.o
  $RISCV_CC $RVCFLAGS $def -c "$BUGDIR/start.S" -o start.o
  $RISCV_LD -T "$BUGDIR/probe.ld" -o "$out" start.o probe.o
}
build_probe "-DTARGET_TEMU" probe-temu.elf
$RISCV_OBJCOPY -O binary probe-temu.elf probe-temu.bin
build_probe "" probe-qemu.elf
loud "built probe-temu.bin (flat, temu bios) and probe-qemu.elf (qemu -kernel)"

cat > probe-temu.cfg <<EOF
{ version: 1, machine: "riscv64", memory_size: 128, bios: "$PWD/probe-temu.bin", }
EOF

# ---------------------------------------------------------------------------
banner "5/5 -- RUN the probe on both emulators and compare the readback"
# ---------------------------------------------------------------------------
loud "temu (the finding): writes to priority/enable/threshold, reads each back"
timeout 30 "$TEMU" probe-temu.cfg > temu.out 2>&1 || true
sed 's/^/    /' temu.out
loud "qemu -M virt (spec-compliant control): same program, same writes"
timeout 30 qemu-system-riscv64 -M virt -nographic -bios none \
    -kernel probe-qemu.elf -m 256M > qemu.out 2>&1 || true
sed 's/^/    /' qemu.out

getval () { grep -E "^$1 " "$2" | awk '{print $2}' | head -1; }

# CONTROL: qemu must have all three registers present.  Enable is exact; the
# other two need only be present (priority/threshold may be masked to the
# target's priority-bit width).
q_prio=$(getval PRIO5 qemu.out); q_en=$(getval EN0 qemu.out); q_thr=$(getval THR0 qemu.out)
grep -q '^DONE'          qemu.out || die "qemu control did not run to completion"
[ "$q_en" = "$EN_EXPECT" ]        || die "qemu enable readback was '$q_en', expected $EN_EXPECT -- control is wrong, harness suspect"
[ -n "$q_prio" ] && [ "$q_prio" != "00000000" ] || die "qemu priority register absent? readback '$q_prio' -- control is wrong"
[ -n "$q_thr" ]  && [ "$q_thr"  != "00000000" ] || die "qemu threshold register absent? readback '$q_thr' -- control is wrong"
loud "CONTROL OK: qemu reads back PRIO5=$q_prio EN0=$q_en THR0=$q_thr -- gating registers present"

# BUG: temu must read back 0 from all three despite the identical writes.
# ABLATE=1 points this same check at qemu's output; it must die on the enable
# register (AGENTS.md "show the reproducer going red, once").
CHECK=temu.out
if [ "${ABLATE:-0}" = 1 ]; then
  loud "ABLATE=1: pointing the 'registers absent' check at the QEMU output;"
  loud "          this run MUST fail on the enable register."
  CHECK=qemu.out
fi
t_prio=$(getval PRIO5 "$CHECK"); t_en=$(getval EN0 "$CHECK"); t_thr=$(getval THR0 "$CHECK")
grep -q '^DONE' "$CHECK" || die "the probe did not run to completion on temu"
[ "$t_en"   = "00000000" ] || die "temu enable readback was '$t_en', expected 00000000 \
(if ABLATE=1 this is the reproducer correctly going red: a gated PLIC returns the written value)"
[ "$t_prio" = "00000000" ] || die "temu priority readback was '$t_prio', expected 00000000"
[ "$t_thr"  = "00000000" ] || die "temu threshold readback was '$t_thr', expected 00000000"
loud "BUG: temu reads back PRIO5=$t_prio EN0=$t_en THR0=$t_thr -- the registers do not exist"

banner "VERDICT"
cat <<EOF

  Same M-mode program writes priority[5]=3, enable[ctx0]=0x20, threshold[ctx0]=3
  and reads each back:

    TinyEMU 2019-12-21   PRIO5=$t_prio EN0=$t_en THR0=$t_thr   (registers absent -- reads 0)
    qemu -M virt         PRIO5=$q_prio EN0=$q_en THR0=$q_thr   (registers present -- reads back)

  temu has no PLIC enable/priority/threshold gating: a source it never enabled
  is deliverable and claimable.  That is the property behind the manufactured
  boot hang described in this bug's entry in the repository README.
EOF
loud "REPRODUCED: TinyEMU's PLIC is not enable-gated; qemu (spec-compliant) is."
