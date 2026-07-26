#!/usr/bin/env bash
# linux-riscv-plic-unmapped-claim: drivers/irqchip/irq-sifive-plic.c leaks a
# PLIC claim.  plic_handle_irq() claims a source with readl(claim); if the hwirq
# has no Linux irqdomain mapping it warns and moves on WITHOUT writing the ID
# back.  The PLIC's per-source gateway will not forward that source again until
# the outstanding claim is completed, so the source is masked for the rest of
# the boot.
#
# The reachable-on-real-hardware path is a source numbered ABOVE the DT's
# "riscv,ndev": __plic_init() clears the per-context enable bits only for
# hwirq 1..ndev and sizes the irqdomain to the same range, so a source above
# ndev that a prior boot stage left enabled + asserted survives Linux's init,
# can never be mapped, and is claimed on the first external interrupt.
#
# Everything below runs on STOCK qemu-system-riscv64 -M virt, whose PLIC is
# spec-compliant and enable-gated (hw/intc/sifive_plic.c: a source is claimable
# only if `pending & ~claimed & enable`, and only if its priority exceeds the
# context threshold).  Nothing here depends on an emulator shortcut.
#
# GREEN == this matrix holds exactly, on the SAME machine, with only the named
# variable changing between rows:
#
#                                              stock kernel   + the one-liner
#   poison, above ndev (enabled + asserted)         1 warn       >= 2 warns
#   poison, IN range   (qemu's own ndev)            0 warns         0 warns
#   control, above ndev (enabled, not asserted)     0 warns         0 warns
#   none,   above ndev (stub touches nothing)       0 warns         0 warns
#
#   ... and all eight boots reach userspace.
#
# Row 1 vs row 2 answers the maintainer's first question -- "why did
# __plic_init() not clear it?".  Identical stub, identical kernel; the ONLY
# difference is whether the source is inside the DT's riscv,ndev.  In range,
# Linux's clear-enables loop neutralises the prior stage and nothing is
# delivered at all; above it, the enable survives and the source is claimed
# while unmapped.
#
# The 1-vs-many cell in row 1 is the bug itself: the poison source keeps
# re-asserting (the console UART's THRE line goes high again after every
# character OpenSBI prints), yet the stock kernel is delivered it exactly ONCE,
# because the leaked claim latches that gateway shut.  Completing the claim
# restores delivery.  Rows 3 and 4 show the warning is not spontaneous and that
# qemu's PLIC really is enable-gated.
cd "$(dirname "$0")"
. ../common.sh
BUGDIR=$PWD

for t in qemu-system-riscv64 riscv64-linux-gnu-gcc flex bison bc cpio python3 patch; do
  command -v "$t" >/dev/null || die "need $t (see the workflow file for apt names)"
done

LINUX_VER=6.12.1
LINUX_URL=https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${LINUX_VER}.tar.xz
LINUX_SHA=0193b1d86dd372ec891bae799f6da20deef16fc199f30080a4ea9de8cef0c619
PLIC_REL=drivers/irqchip/irq-sifive-plic.c
UPSTREAM_RAW=https://raw.githubusercontent.com/torvalds/linux/master/$PLIC_REL

# qemu virt facts we depend on (include/hw/riscv/virt.h): UART0_IRQ = 10, PLIC
# at 0x0c000000.  stub.S carries the full register map.
POISON_SRC=10
CONTRIVED_NDEV=9

WORK=$BUGDIR/work
mkdir -p "$WORK"
cd "$WORK"

JOBS=$(nproc 2>/dev/null || echo 2)
export ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu-

# ---------------------------------------------------------------------------
banner "1/6 -- PREMISE: does upstream still leak the claim?"
# ---------------------------------------------------------------------------
# Cheap fixed-string check first (shared helper: an unreachable host warns, a
# missing construct after a SUCCESSFUL fetch is fatal).
upstream_still_has "torvalds/linux master $PLIC_REL" \
  "$UPSTREAM_RAW" "can't find mapping for hwirq"

# ...then the structural check, which is the one that would actually notice a
# fix landing, since the warning survives the fix.
if curl -fsSL --max-time 60 --retry 2 -o upstream-plic.c "$UPSTREAM_RAW"; then
  loud "structural check against torvalds/linux master:"
  python3 "$BUGDIR/check-plic-source.py" unfixed upstream-plic.c
else
  loud "UPSTREAM RE-CHECK SKIPPED: could not fetch $UPSTREAM_RAW"
  loud "  (host unreachable != bug fixed -- not failing the run over it)"
fi

# ---------------------------------------------------------------------------
banner "2/6 -- the pinned kernel we actually run"
# ---------------------------------------------------------------------------
fetch "$LINUX_URL" "$LINUX_SHA" "linux-${LINUX_VER}.tar.xz"
[ -d "linux-${LINUX_VER}" ] || tar -xf "linux-${LINUX_VER}.tar.xz"
SRC=$WORK/linux-${LINUX_VER}

# A previous local run leaves the fix applied in this tree.  Revert it, or the
# premise check below would report "upstream has fixed it" about our own edit.
# (Safe: the tarball is sha256-pinned, so its content cannot change under us,
# and this only ever reverts our own patch.)
if grep -q 'writel(hwirq, claim)' "$SRC/$PLIC_REL"; then
  loud "this work tree still carries the fix from a previous run; reverting it"
  ( cd "$SRC" && patch -p1 -R --batch < "$BUGDIR/plic-complete-unmapped.patch" )
fi

if [ "${ABLATE:-0}" = 1 ]; then
  loud "ABLATE=1 -- skipping the pinned-source premise check (see the hook below)"
else
  loud "the same structural check, on the pinned source we build:"
  python3 "$BUGDIR/check-plic-source.py" unfixed "$SRC/$PLIC_REL"
fi

cd "$SRC"
# ABLATION HOOK (AGENTS.md "show the reproducer going red, once"):
# ABLATE=1 applies the fix BEFORE the "stock" build, i.e. points the bug legs at
# a kernel where the defect is absent.  The run must then FAIL at the
# `N_POISON_STOCK = 1` assertion.  Not exercised in CI -- run it by hand when
# changing this harness.
if [ "${ABLATE:-0}" = 1 ] && [ ! -f .ablated ]; then
  loud "ABLATE=1: applying the fix before the stock build; this run MUST fail"
  patch -p1 --forward < "$BUGDIR/plic-complete-unmapped.patch"
  python3 "$BUGDIR/check-plic-source.py" fixed "$PLIC_REL"
  touch .ablated
fi
if [ ! -f .config.stamped ]; then
  make defconfig >/dev/null
  # Two config decisions are load-bearing; the rest is only build time.
  #   * The console must NOT be the 8250.  Linux's 8250 driver writes IER=0
  #     during probe, which would silently de-assert the poison source; the SBI
  #     console leaves the UART entirely to OpenSBI and to our stub.
  #   * An initramfs, so every leg ends at a userspace marker rather than a
  #     root-filesystem panic -- a clean "did this boot finish?" assertion.
  ./scripts/config --file .config \
    -d SERIAL_8250 -d SERIAL_8250_CONSOLE -d SERIAL_OF_PLATFORM \
    -e NONPORTABLE -e RISCV_SBI_V01 -e HVC_DRIVER -e HVC_RISCV_SBI \
    -e SERIAL_EARLYCON_RISCV_SBI -e BLK_DEV_INITRD \
    -d NET -d SOUND -d DRM -d USB_SUPPORT -d MEDIA_SUPPORT -d SCSI -d ATA \
    -d MD -d KVM -d NFS_FS -d BTRFS_FS -d XFS_FS -d EXT4_FS -d F2FS_FS
  make olddefconfig >/dev/null
  touch .config.stamped
fi

# Assert the config we asked for is the config we got: `scripts/config` happily
# succeeds on a symbol that does not exist, and olddefconfig can put one back.
# A silently-8250 console would invalidate the whole experiment.
for sym in SIFIVE_PLIC RISCV_SBI_V01 HVC_RISCV_SBI SERIAL_EARLYCON_RISCV_SBI \
           BLK_DEV_INITRD; do
  grep -q "^CONFIG_$sym=y" .config || die "CONFIG_$sym is not set -- config drift"
done
if grep -q "^CONFIG_SERIAL_8250=" .config; then
  die "CONFIG_SERIAL_8250 is enabled; its probe would clear the UART IER"
fi
loud "config OK: SBI console, no 8250 driver, PLIC + initrd in"

loud "building the stock Image (-j$JOBS); this is the slow step"
make -j"$JOBS" Image >/dev/null
cp arch/riscv/boot/Image "$WORK/Image-stock"
[ -s "$WORK/Image-stock" ] || die "stock Image is empty"
loud "Image-stock: $(stat -c%s "$WORK/Image-stock") bytes"
cd "$WORK"

# ---------------------------------------------------------------------------
banner "3/6 -- the pre-kernel stub, the /init marker, and the contrived DTB"
# ---------------------------------------------------------------------------
# MODE 0 = touch nothing, 1 = configure PLIC source 10 but do not assert it,
# 2 = configure AND assert it (our stand-in for a prior boot stage).
for m in 0 1 2; do
  riscv64-linux-gnu-gcc -nostdlib -static -Wl,--build-id=none \
    -Wl,-Ttext=0x80200000 -Wl,-e,_start \
    -DMODE=$m -DKERNEL_ADDR=0x80400000 -o "stub-$m.elf" "$BUGDIR/stub.S"
  riscv64-linux-gnu-objcopy -O binary -j .text "stub-$m.elf" "stub-$m.bin"
  sz=$(stat -c%s "stub-$m.bin")
  # objcopy emits an EMPTY file for a section name that does not exist, and
  # qemu would then boot with no stub at all -- a silently gutted experiment
  # that still exits 0.  Size-gate every variant.
  [ "$sz" -ge 8 ] || die "stub-$m.bin is $sz bytes -- objcopy produced nothing"
done
[ "$(stat -c%s stub-2.bin)" -gt "$(stat -c%s stub-1.bin)" ] \
  || die "the poison stub is not larger than the control stub -- MODE is not taking"
[ "$(stat -c%s stub-1.bin)" -gt "$(stat -c%s stub-0.bin)" ] \
  || die "the control stub is not larger than the no-op stub -- MODE is not taking"
loud "stubs: $(stat -c%s stub-0.bin) / $(stat -c%s stub-1.bin) / $(stat -c%s stub-2.bin) bytes (none / control / poison)"
echo "  poison stub, disassembled:"
riscv64-linux-gnu-objdump -d stub-2.elf > stub-2.dis
sed -n '/<_start>:/,$p' stub-2.dis | sed 's/^/    /'

rm -rf irfs && mkdir -p irfs
riscv64-linux-gnu-gcc -nostdlib -static -Wl,--build-id=none -o irfs/init "$BUGDIR/init.S"
[ -s irfs/init ] || die "/init did not build"
( cd irfs && echo init | cpio -o -H newc --quiet > ../initramfs.cpio )
[ -s initramfs.cpio ] || die "initramfs is empty"

CMDLINE="console=hvc0 earlycon=sbi panic=1"
QEMU_COMMON=(-m 512 -smp 1 -nographic -no-reboot)
loud "qemu: $(qemu-system-riscv64 --version | head -1)"

# Dump the machine's own device tree -- with the bootargs baked in, because a
# supplied -dtb replaces the generated one wholesale so -append no longer
# reaches the guest -- then lower riscv,ndev so source 10 falls outside it.
rm -f virt-stock.dtb
qemu-system-riscv64 -M virt,dumpdtb=virt-stock.dtb "${QEMU_COMMON[@]}" \
  -kernel stub-0.bin -append "$CMDLINE" >/dev/null 2>&1 || true
[ -s virt-stock.dtb ] || die "qemu did not dump a device tree"
python3 "$BUGDIR/patch-ndev.py" virt-stock.dtb "$POISON_SRC" "$CONTRIVED_NDEV" virt-ndev.dtb \
  > ndev.txt
cat ndev.txt
STOCK_NDEV=$(sed -n 's/^riscv,ndev: \([0-9]*\) .*/\1/p' ndev.txt)
[ -n "$STOCK_NDEV" ] || die "could not read qemu's stock riscv,ndev"
if cmp -s virt-stock.dtb virt-ndev.dtb; then die "the DTB edit changed nothing"; fi
loud "two device trees: qemu's own (riscv,ndev=$STOCK_NDEV, source $POISON_SRC IN range)"
loud "                  and the contrived one (riscv,ndev=$CONTRIVED_NDEV, source $POISON_SRC ABOVE range)"

# ---------------------------------------------------------------------------
# One boot.  Sets LAST_N to the number of unmapped-claim warnings.
#   check_leg <label> <stub-mode> <image> <log>
# ---------------------------------------------------------------------------
LAST_N=
check_leg () {              # <label> <stub-mode> <dtb> <expected-ndev> <image> <log>
  local label="$1" mode="$2" dtb="$3" ndev="$4" image="$5" log="$6" n
  timeout 180 qemu-system-riscv64 -M virt "${QEMU_COMMON[@]}" \
    -dtb "$dtb" -kernel "stub-$mode.bin" \
    -device loader,file="$image",addr=0x80400000 \
    -initrd initramfs.cpio > "$log" 2>&1 || true
  # STIMULUS ASSERTIONS -- without these the job could pass while proving
  # nothing.  (1) the boot has to finish, and (2) Linux has to have sized its
  # PLIC irqdomain from the device tree we meant to give it: if the DTB edit
  # silently failed, source 10 would be IN range and the whole "above ndev"
  # argument would be unsupported while the warning still appeared (an
  # in-range source with no driver is unmapped too).
  if ! grep -q REPRO-USERSPACE-REACHED "$log"; then
    echo "--- last 40 lines of $log ---"; tail -40 "$log"
    die "$label: the boot never reached userspace"
  fi
  grep -q "mapped $ndev interrupts with" "$log" \
    || { grep -E "riscv-plic" "$log" | sed 's/^/    /'
         die "$label: Linux did not size its PLIC domain to $ndev interrupts -- \
the device tree this leg meant to use is not the one it got"; }
  n=$(grep -c "can't find mapping for hwirq $POISON_SRC" "$log" || true)
  printf '  %-38s warnings=%-4s boot reached userspace, domain=%s\n' "$label" "$n" "$ndev"
  LAST_N=$n
}

# ---------------------------------------------------------------------------
banner "4/6 -- BUG: the stock kernel, four configurations"
# ---------------------------------------------------------------------------
check_leg "poison  above ndev / stock kernel" 2 virt-ndev.dtb  "$CONTRIVED_NDEV" Image-stock poison-stock.log;  N_POISON_STOCK=$LAST_N
check_leg "poison  IN range   / stock kernel" 2 virt-stock.dtb "$STOCK_NDEV"     Image-stock inrange-stock.log; N_INRANGE_STOCK=$LAST_N
check_leg "control above ndev / stock kernel" 1 virt-ndev.dtb  "$CONTRIVED_NDEV" Image-stock control-stock.log; N_CTRL_STOCK=$LAST_N
check_leg "none    above ndev / stock kernel" 0 virt-ndev.dtb  "$CONTRIVED_NDEV" Image-stock none-stock.log;    N_NONE_STOCK=$LAST_N

echo
echo "  the PLIC probe's own summary, and the warning, from the poison run:"
grep -E "riscv-plic" poison-stock.log | sed 's/^/    /'

[ "$N_POISON_STOCK" = "1" ] \
  || die "expected EXACTLY 1 unmapped-claim warning on the stock kernel, got $N_POISON_STOCK"
[ "$N_INRANGE_STOCK" = "0" ] \
  || die "the in-range leg warned $N_INRANGE_STOCK times; with riscv,ndev=$STOCK_NDEV, __plic_init() \
must have cleared source $POISON_SRC's enable bit, so it must not be deliverable at all"
[ "$N_CTRL_STOCK" = "0" ] \
  || die "control leg warned $N_CTRL_STOCK times -- the warning is not caused by the assertion"
[ "$N_NONE_STOCK" = "0" ] \
  || die "no-stub leg warned $N_NONE_STOCK times -- something other than the stub enabled the source"
loud "stock kernel: source $POISON_SRC is delivered exactly ONCE and never again,"
loud "and ONLY when it is above riscv,ndev -- the identical stub against qemu's own"
loud "riscv,ndev=$STOCK_NDEV device tree is neutralised by __plic_init()'s clear-enables loop."

# ---------------------------------------------------------------------------
banner "5/6 -- CONTROL: the same four legs with the claim completed"
# ---------------------------------------------------------------------------
cd "$SRC"
patch -p1 --forward < "$BUGDIR/plic-complete-unmapped.patch" || true
# The patch may have been a no-op on a re-run; this is the assertion that the
# built source really carries the completion.
python3 "$BUGDIR/check-plic-source.py" fixed "$PLIC_REL"
make -j"$JOBS" Image >/dev/null
cp arch/riscv/boot/Image "$WORK/Image-fixed"
cd "$WORK"
if cmp -s Image-stock Image-fixed; then
  die "the fixed Image is byte-identical to the stock one -- the patch never reached the build"
fi
loud "Image-fixed differs from Image-stock, as it must"

check_leg "poison  above ndev / FIXED kernel" 2 virt-ndev.dtb  "$CONTRIVED_NDEV" Image-fixed poison-fixed.log;  N_POISON_FIXED=$LAST_N
check_leg "poison  IN range   / FIXED kernel" 2 virt-stock.dtb "$STOCK_NDEV"     Image-fixed inrange-fixed.log; N_INRANGE_FIXED=$LAST_N
check_leg "control above ndev / FIXED kernel" 1 virt-ndev.dtb  "$CONTRIVED_NDEV" Image-fixed control-fixed.log; N_CTRL_FIXED=$LAST_N
check_leg "none    above ndev / FIXED kernel" 0 virt-ndev.dtb  "$CONTRIVED_NDEV" Image-fixed none-fixed.log;    N_NONE_FIXED=$LAST_N

[ "$N_POISON_FIXED" -ge 2 ] \
  || die "the fixed kernel saw $N_POISON_FIXED warning(s); once the claim is completed the still-asserted source must be delivered again"
[ "$N_INRANGE_FIXED" = "0" ] || die "fixed in-range leg warned $N_INRANGE_FIXED times"
[ "$N_CTRL_FIXED" = "0" ] || die "fixed control leg warned $N_CTRL_FIXED times"
[ "$N_NONE_FIXED" = "0" ] || die "fixed no-stub leg warned $N_NONE_FIXED times"

# ---------------------------------------------------------------------------
banner "6/6 -- RESULT"
# ---------------------------------------------------------------------------
cat <<EOF

  Machine:      stock qemu-system-riscv64 -M virt -- spec-compliant,
                enable-gated PLIC
  Kernel:       linux-${LINUX_VER}, pinned tarball, built here
  Device tree:  qemu's own, with riscv,ndev lowered to $CONTRIVED_NDEV so that PLIC
                source $POISON_SRC (UART0) sits outside __plic_init()'s
                clear-enables loop and outside the irqdomain
  Prior stage:  a tiny pre-kernel S-mode stub

                                              stock    one-line fix
    poison,  above ndev=$CONTRIVED_NDEV  (enabled+asserted)   $N_POISON_STOCK         $N_POISON_FIXED
    poison,  IN range ndev=$STOCK_NDEV (enabled+asserted)  $N_INRANGE_STOCK         $N_INRANGE_FIXED
    control, above ndev (enabled, not asserted)   $N_CTRL_STOCK         $N_CTRL_FIXED
    none,    above ndev (stub touches nothing)    $N_NONE_STOCK         $N_NONE_FIXED
                                        occurrences of
                                        "can't find mapping for hwirq $POISON_SRC"

  Every leg asserted that Linux really sized its PLIC irqdomain from the device
  tree that leg intended ("mapped N interrupts"), so none of the zeros above can
  be a leg that quietly ran the wrong configuration.

  * Row 1 vs row 2 is the reachability argument, measured: the SAME stub against
    qemu's own riscv,ndev=$STOCK_NDEV is completely neutralised, because
    __plic_init() clears the enable bits for hwirq 1..ndev.  Only above ndev does
    the prior stage's enable survive into Linux.
  * The stock kernel is delivered the source ONCE.  The line is still being
    asserted afterwards -- the fixed column proves that, since it is delivered
    $N_POISON_FIXED times off the same line -- so the single delivery is the
    leaked claim latching the gateway shut, not the device going quiet.
  * Rows 3 and 4 pin down what is being demonstrated: with the source enabled
    but never asserted nothing is claimed at all, and with the stub not
    configuring the PLIC the source is not deliverable even when asserted --
    qemu's PLIC is enable-gated, unlike the emulator this was first found on.
  * All eight boots reach userspace.  The above-ndev variant demonstrates
    reachability, the permanent mask, and recovery -- but NOT a hang: the masked
    source here has no Linux driver waiting on it.  The boot-hang consequence
    needs a boot-critical device on the masked line, which is what we hit under
    TinyEMU and is NOT reproduced by this workflow.

  Honest note for a reviewer: the poison source here is the console UART, so
  the fixed kernel's own warning output re-asserts the line -- that is why
  $N_POISON_FIXED (the printk rate-limit burst) rather than exactly one.  It is
  also a fair caution about the fix: completing a still-asserted,
  permanently-unmapped level source means it will be re-delivered until
  something quiesces it.  Here that is rate-limit-bounded and the boot finishes
  normally.

EOF
loud "REPRODUCED: a claimed-but-unmapped PLIC source is never completed, and is"
loud "masked for the rest of the boot -- on spec-compliant hardware."
