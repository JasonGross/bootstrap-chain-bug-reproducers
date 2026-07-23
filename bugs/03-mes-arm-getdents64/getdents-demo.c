/* Behavioral demo, built as a static ARM EABI binary and run under qemu-user:
   invoke the syscall number that GNU Mes' include/linux/arm/syscall.h calls
   SYS_getdents64 (0xdc = 220 -- the x86 number; on arm EABI 220 is madvise)
   on a directory fd, then invoke the REAL arm getdents64 number (217 = 0xd9).

   The mes header is force-included on the compile command line (-include), so
   SYS_getdents64 below is mes' own definition, used exactly the way mes libc's
   readdir would use it.

   Exit 0 iff the bug reproduces: mes' number does NOT return directory
   entries, while 217 does.  */
#define _GNU_SOURCE
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>

#ifndef SYS_getdents64
#error "expected mes' include/linux/arm/syscall.h to be force-included"
#endif

#define ARM_TRUE_GETDENTS64 217 /* linux v4.19 arch/arm/tools/syscall.tbl */

struct lin_dirent64
{
  unsigned long long d_ino;
  long long d_off;
  unsigned short d_reclen;
  unsigned char d_type;
  char d_name[];
};

static int
open_demo_dir (void)
{
  int fd;
  mkdir ("demo-dir", 0700);
  fd = open ("demo-dir/alpha", O_CREAT | O_WRONLY, 0600); if (fd >= 0) close (fd);
  fd = open ("demo-dir/beta",  O_CREAT | O_WRONLY, 0600); if (fd >= 0) close (fd);
  fd = open ("demo-dir", O_RDONLY | O_DIRECTORY);
  if (fd < 0) { perror ("open demo-dir"); _exit (2); }
  return fd;
}

int
main (void)
{
  char buf[4096];
  int failures = 0;

  printf ("mes include/linux/arm/syscall.h says: SYS_getdents64 = %d (0x%x)\n",
          (int) SYS_getdents64, (int) SYS_getdents64);
  printf ("linux arm EABI truth:                 getdents64     = 217 (0xd9)\n");
  printf ("                                      madvise        = 220 (0xdc)\n\n");

  /* Leg 1: the number mes uses. */
  int fd = open_demo_dir ();
  memset (buf, 0, sizeof buf);
  errno = 0;
  long r_mes = syscall (SYS_getdents64, fd, buf, sizeof buf);
  int e_mes = errno;
  printf ("syscall(SYS_getdents64 /* mes: %d */, dirfd, buf, %zu) = %ld, errno=%d (%s)\n",
          (int) SYS_getdents64, sizeof buf, r_mes, e_mes, strerror (e_mes));
  if (r_mes > 0)
    {
      printf ("  UNEXPECTED: mes' number returned data -- bug did NOT reproduce\n");
      failures++;
    }
  else
    printf ("  -> madvise semantics on arm (no directory entries; %s)\n",
            r_mes < 0 ? "error return" : "returns 0, buffer untouched");
  close (fd);

  /* Leg 2: the correct arm number, same call otherwise. */
  fd = open_demo_dir ();
  memset (buf, 0, sizeof buf);
  errno = 0;
  long r_true = syscall (ARM_TRUE_GETDENTS64, fd, buf, sizeof buf);
  int e_true = errno;
  printf ("syscall(217 /* real arm getdents64 */,  dirfd, buf, %zu) = %ld, errno=%d\n",
          sizeof buf, r_true, e_true);
  if (r_true <= 0)
    {
      printf ("  UNEXPECTED: real getdents64 failed -- environment problem\n");
      failures++;
    }
  else
    {
      long off = 0;
      printf ("  directory entries returned:");
      while (off < r_true)
        {
          struct lin_dirent64 *d = (struct lin_dirent64 *) (buf + off);
          printf (" %s", d->d_name);
          off += d->d_reclen;
        }
      printf ("\n");
    }
  close (fd);

  if (failures)
    return 1;
  printf ("\nBUG REPRODUCED: a program using mes' arm SYS_getdents64 (220) gets\n"
          "madvise, not getdents64; the correct number is 217.\n");
  return 0;
}
