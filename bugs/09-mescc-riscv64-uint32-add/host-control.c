/* Host-gcc control: evaluate the same two expressions under a conforming
   compiler and print the values.  Exit 0 iff both are the wrapped-correct 0. */
#include <stdio.h>

unsigned
f (unsigned imm)
{
  return (imm + (1 << 11)) >> 12;
}

unsigned
g (unsigned imm)
{
  return ((unsigned) (imm + (1 << 11))) >> 12;
}

int
main (void)
{
  unsigned imm = (unsigned) -16;
  unsigned rf = f (imm);
  unsigned rg = g (imm);
  printf ("  imm = (unsigned)-16 = 0x%08x\n", imm);
  printf ("  (imm + (1<<11)) >> 12            = 0x%x  %s\n", rf,
          rf == 0 ? "[correct: wrapped mod 2^32]" : "[WRONG]");
  printf ("  ((unsigned)(imm + (1<<11))) >> 12 = 0x%x  %s\n", rg,
          rg == 0 ? "[correct]" : "[WRONG]");
  return (rf == 0 && rg == 0) ? 0 : 1;
}
