/*
 * Pre-kernel S-mode stub for the SiFive-PLIC unmapped-claim reproducer.
 *
 * OpenSBI hands control here in S-mode with a0 = hartid, a1 = FDT address.
 * We stand in for "a prior boot stage" (firmware / bootloader / kexec'd
 * kernel): we configure ONE PLIC source for the S-mode context and, in the
 * poison build, leave it ASSERTED.  Then we jump to the real Linux Image,
 * preserving a0/a1 exactly as we received them.
 *
 * qemu-system-riscv64 -M virt memory map (matches the dumped DTB):
 *   PLIC base            0x0c000000
 *     priority[src]      base + src*4
 *     enable[ctx]        base + 0x2000 + ctx*0x80
 *     threshold[ctx]     base + 0x200000 + ctx*0x1000
 *     claim/complete     base + 0x200004 + ctx*0x1000
 *   hart 0 contexts: 0 = M-mode, 1 = S-mode  -> Linux uses context 1
 *   ns16550a UART0       0x10000000 (reg-shift 0), IER at +1, PLIC source 10
 *
 * Build variants (-DMODE=n):
 *   0 NOSTUB  - jump straight to Linux (nothing touched)
 *   1 CONTROL - configure the PLIC for source 10, do NOT assert it
 *   2 POISON  - configure the PLIC for source 10 AND assert it (UART IER.THRI)
 */

#ifndef MODE
#error "define MODE"
#endif

#ifndef KERNEL_ADDR
#error "define KERNEL_ADDR"
#endif

#define PLIC_BASE        0x0c000000
#define PLIC_PRIORITY_10 (PLIC_BASE + 10*4)          /* 0x0c000028 */
#define PLIC_ENABLE_S    (PLIC_BASE + 0x2000 + 0x80) /* 0x0c002080, ctx 1 */
#define PLIC_THRESH_S    (PLIC_BASE + 0x200000 + 0x1000) /* 0x0c201000 */
#define UART0_IER        (0x10000000 + 1)

	.section .text.start, "ax", @progbits
	.globl _start
_start:
	/* a0 = hartid, a1 = fdt  -- must reach Linux untouched */
#if MODE >= 1
	/* priority[10] = 7 (any value > the context threshold works) */
	li	t0, PLIC_PRIORITY_10
	li	t1, 7
	sw	t1, 0(t0)

	/* enable source 10 for the S-mode context of hart 0 */
	li	t0, PLIC_ENABLE_S
	li	t1, (1 << 10)
	sw	t1, 0(t0)

	/* context threshold 0 -> any priority > 0 is deliverable */
	li	t0, PLIC_THRESH_S
	sw	zero, 0(t0)
#endif
#if MODE >= 2
	/*
	 * Assert source 10: enable the 8250's THRE ("transmit holding register
	 * empty") interrupt.  THRE is true whenever the UART is idle, so the
	 * line goes high immediately and the PLIC latches source 10 pending.
	 */
	li	t0, UART0_IER
	li	t1, 0x02
	sb	t1, 0(t0)
#endif
	/* chain to the Linux Image, a0/a1 preserved */
	li	t0, KERNEL_ADDR
	jr	t0
