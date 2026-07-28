/* Reproducer probe for the M2libc armv7l unlink() defect.
 *
 * Calls two M2libc char*-taking syscall wrappers on the SAME path:
 *   - access(): its armv7l asm DEREFERENCES the pointer argument
 *               (it carries "!0 R0 LOAD32 R0 MEMORY").
 *   - unlink(): its armv7l asm is MISSING that dereference, so it hands the
 *               kernel &filename (the stack slot address) instead of filename.
 *
 * The exit code encodes both outcomes so the harness can tell them apart:
 *   bit0 (1) set  <=> access() returned nonzero  (path not found / deref wrong)
 *   bit1 (2) set  <=> unlink() returned nonzero  (removal failed)
 *
 * The harness creates the victim file before running this and checks its
 * survival afterwards as the ground truth -- no stdio needed.
 *
 * Expected: armv7l -> exit 2 (access ok, unlink failed) + file survives;
 *           amd64  -> exit 0 (both ok) + file removed.
 */
int main()
{
	int a;
	int u;
	a = access("victim-file", 0);   /* F_OK: 0 iff the path exists */
	u = unlink("victim-file");
	return (a != 0) + ((u != 0) * 2);
}
