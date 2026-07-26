/*
 * Minimal riscv64 /init for the reproducer's initramfs: print one marker so
 * the log has an unambiguous "the boot reached userspace" line, then power the
 * machine off through the reboot(2) syscall (RISC-V routes this to SBI SRST,
 * which makes qemu exit).  No libc, so nothing else can influence the boot.
 */
#define MSGLEN 24

	.section .text
	.globl _start
_start:
	li	a7, 64			/* __NR_write */
	li	a0, 1
	lla	a1, msg
	li	a2, MSGLEN
	ecall

	li	a7, 142			/* __NR_reboot */
	li	a0, 0xfee1dead		/* LINUX_REBOOT_MAGIC1 */
	li	a1, 672274793		/* LINUX_REBOOT_MAGIC2 */
	li	a2, 0x4321fedc		/* LINUX_REBOOT_CMD_POWER_OFF */
	li	a3, 0
	ecall

	li	a7, 93			/* __NR_exit (only if reboot failed) */
	li	a0, 1
	ecall

	.section .rodata
msg:
	.ascii "REPRO-USERSPACE-REACHED\n"
msg_end:
	/* guard the hand-computed length: a silent mismatch would truncate the
	 * marker (or read past it) and the log assertion would go quiet */
	.if (msg_end - msg) != MSGLEN
	.error "MSGLEN does not match the marker string"
	.endif
