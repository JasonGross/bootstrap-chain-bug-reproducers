/* Reproducer probe for the M2libc armv7l chroot() defect.
 *
 * chroot()'s armv7l asm computes &path (the stack-slot address) but is MISSING
 * the "!0 R0 LOAD32 R0 MEMORY" line, so it hands the kernel &path instead of
 * the char* the caller passed.  chroot needs privilege we don't have, so it
 * cannot SUCCEED here -- but we don't need it to.  We only need to see what it
 * PASSES, and qemu-user's -strace prints each syscall's pointer argument.
 *
 * The probe calls access() then chroot() on the SAME string literal.  access()
 * dereferences correctly, so the trace shows the real path; chroot() passes
 * &path, so the trace shows a bogus pointer where the path should be.  The
 * marker string is deliberately distinctive so the harness can assert that the
 * access line contains it and the chroot line does not.
 */
int main()
{
	access("ZQXPATHMARKER", 0);
	chroot("ZQXPATHMARKER");
	return 0;
}
