/* Reproducer probe for the M2libc armv7l close() defect.
 *
 * close()'s armv7l asm computes &fd (the stack-slot address) but is MISSING
 * the "!0 R0 LOAD32 R0 MEMORY" line that would load the fd value out of it,
 * so it hands the kernel a stack address instead of the descriptor number.
 * The kernel rejects that bogus fd (EBADF) and closes NOTHING.
 *
 * The probe opens a file, closes the fd, then reads from the SAME fd:
 *   - correct close():  the fd is closed, so read() fails  (returns < 0).
 *   - broken  close():  the fd is still open, so read() succeeds (returns > 0).
 *
 * open() and read() both dereference their arguments correctly on armv7l, so
 * the only variable across archs is close().  Exit code:
 *   0   read() failed  -> close() really closed the fd  (correct / control)
 *   1   read() succeeded -> close() was a silent no-op   (BUG)
 *   10  setup failure (open() did not return a descriptor)
 *
 * The harness writes >=4 bytes into close-victim before running this.
 */
int main()
{
	int fd;
	int n;
	char buf[8];
	fd = open("close-victim", 0, 0);   /* O_RDONLY */
	if(fd < 0)
	{
		return 10;                 /* setup failure sentinel */
	}
	close(fd);
	n = read(fd, buf, 4);              /* > 0 iff fd is still open */
	return (n > 0);
}
