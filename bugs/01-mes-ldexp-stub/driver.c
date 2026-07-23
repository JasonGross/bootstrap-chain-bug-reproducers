/* Calls ldexp(1.0, 10) and prints the result.
   - Linked against the object compiled from mes-0.27.1/lib/stub/ldexp.c, this
     demonstrates the bug (result 0 instead of 1024).
   - Linked against -lm, the same source is the correct-behavior control
     (result 1024).
   volatile inputs + -fno-builtin keep the compiler from constant-folding the
   call, so the value really comes from the linked ldexp at run time.  */
#include <stdio.h>
#include <string.h>

double ldexp (double, int);

int
main (void)
{
  volatile double x = 1.0;
  volatile int n = 10;
  double got = ldexp (x, n);
  unsigned long long bits;
  memcpy (&bits, &got, sizeof bits);
  printf ("ldexp(1.0, 10) = %.17g   (IEEE-754 bits 0x%016llx)\n", got, bits);
  return 0;
}
