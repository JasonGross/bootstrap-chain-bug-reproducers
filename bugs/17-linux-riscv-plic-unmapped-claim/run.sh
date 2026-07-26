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
# GREEN == this matrix holds exactly, with the SAME machine, SAME device tree
# and SAME pre-kernel stub in each row -- only the kernel differs:
#
#                                     stock kernel   one-line-fixed kernel
#   poison  (src 10 enabled+asserted)      1 warn        >= 2 warns
#   control (src 10 enabled, not asserted) 0 warns          0 warns
#   none    (stub touches nothing)         0 warns          0 warns
#
#   ... and all six boots reach userspace.
#
# The 1-vs-many cell is the bug: the poison source keeps re-asserting (the
# console UART's THRE line goes high again after every character OpenSBI
# prints), yet the stock kernel is delivered it exactly ONCE, because the
# leaked claim latches that gateway shut.  Completing the claim restores
# delivery.  The control rows show the warning is not spontaneous and that
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

loud "the same structural check, on the pinned source we build:"
python3 "$BUGDIR/check-plic-source.py" unfixed "$SRC/$PLIC_REL"

cd "$SRC"
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
python3 "$BUGDIR/patch-ndev.py" virt-stock.dtb "$POISON_SRC" "$CONTRIVED_NDEV" virt-ndev.dtb
if cmp -s virt-stock.dtb virt-ndev.dtb; then die "the DTB edit changed nothing"; fi
loud "PLIC source $POISON_SRC (qemu virt's UART0) is now above riscv,ndev=$CONTRIVED_NDEV"

# ---------------------------------------------------------------------------
# One boot.  Sets LAST_N to the number of unmapped-claim warnings.
#   check_leg <label> <stub-mode> <image> <log>
# ---------------------------------------------------------------------------
LAST_N=
check_leg () {
  local label="$1" mode="$2" image="$3" log="$4" n
  timeout 180 qemu-system-riscv64 -M virt "${QEMU_COMMON[@]}" \
    -dtb virt-ndev.dtb -kernel "stub-$mode.bin" \
    -device loader,file="$image",addr=0x80400000 \
    -initrd initramfs.cpio > "$log" 2>&1 || true
  n=$(grep -c "can't find mapping for hwirq $POISON_SRC" "$log" || true)
  if ! grep -q REPRO-USERSPACE-REACHED "$log"; then
    echo "--- last 40 lines of $log ---"
    tail -40 "$log"
    die "$label: the boot never reached userspace"
  fi
  printf '  %-32s warnings=%-4s boot reached userspace\n' "$label" "$n"
  LAST_N=$n
}

# ---------------------------------------------------------------------------
banner "4/6 -- BUG: the stock kernel, three stubs"
# ---------------------------------------------------------------------------
check_leg "poison  / stock kernel"  2 Image-stock poison-stock.log;  N_POISON_STOCK=$LAST_N
check_leg "control / stock kernel"  1 Image-stock control-stock.log; N_CTRL_STOCK=$LAST_N
check_leg "none    / stock kernel"  0 Image-stock none-stock.log;    N_NONE_STOCK=$LAST_N

echo
echo "  the PLIC probe's own summary, and the warning, from the poison run:"
grep -E "riscv-plic" poison-stock.log | sed 's/^/    /'

[ "$N_POISON_STOCK" = "1" ] \
  || die "expected EXACTLY 1 unmapped-claim warning on the stock kernel, got $N_POISON_STOCK"
[ "$N_CTRL_STOCK" = "0" ] \
  || die "control leg warned $N_CTRL_STOCK times -- the warning is not caused by the assertion"
[ "$N_NONE_STOCK" = "0" ] \
  || die "no-stub leg warned $N_NONE_STOCK times -- something other than the stub enabled the source"
loud "stock kernel: source $POISON_SRC is delivered exactly ONCE and never again."

# ---------------------------------------------------------------------------
banner "5/6 -- CONTROL: the same three legs with the claim completed"
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

check_leg "poison  / FIXED kernel"  2 Image-fixed poison-fixed.log;  N_POISON_FIXED=$LAST_N
check_leg "control / FIXED kernel"  1 Image-fixed control-fixed.log; N_CTRL_FIXED=$LAST_N
check_leg "none    / FIXED kernel"  0 Image-fixed none-fixed.log;    N_NONE_FIXED=$LAST_N

[ "$N_POISON_FIXED" -ge 2 ] \
  || die "the fixed kernel saw $N_POISON_FIXED warning(s); once the claim is completed the still-asserted source must be delivered again"
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

                                        stock      one-line fix
    poison  (enabled + asserted)         $N_POISON_STOCK           $N_POISON_FIXED
    control (enabled, not asserted)      $N_CTRL_STOCK           $N_CTRL_FIXED
    none    (stub touches nothing)       $N_NONE_STOCK           $N_NONE_FIXED
                                       occurrences of
                                       "can't find mapping for hwirq $POISON_SRC"

  Same hardware, same DTB, same stub in every row; the only difference between
  the two columns is the one-line completion in plic_handle_irq().

  * The stock kernel is delivered the source ONCE.  The line is still being
    asserted afterwards -- the fixed column proves that, since it is delivered
    $N_POISON_FIXED times off the same line -- so the single delivery is the
    leaked claim latching the gateway shut, not the device going quiet.
  * The control rows pin down what is being demonstrated: with the source
    enabled but never asserted nothing is claimed at all, and with the stub not
    configuring the PLIC the source is not deliverable even when asserted --
    qemu's PLIC is enable-gated, unlike the emulator this was first found on.
  * All six boots reach userspace.  The above-ndev variant demonstrates
    reachability and recovery, NOT a hang: the masked source here has no Linux
    driver waiting on it.  The boot-hang consequence needs a boot-critical
    device on the masked line.

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
