/* Drives GNU Mes' strtod (compiled VERBATIM from the mes-0.27.1 tarball --
   lib/stdlib/strtod.c with only a -Dstrtod=mes_strtod symbol rename so it can
   coexist with the host libc control -- plus its backend abtod/abtol/isnumber)
   on the literal the riscv64 tcc-mes lineage actually stumbles over.

   The mes-lineage riscv64 tcc parses every decimal FP literal in the source
   it compiles via strtod/strtold FROM THE LIBC ITS OWN BINARY LINKS -- mes
   libc in the bootstrap.  mes strtod -> abtod computes  d = i + f / dbase
   (whole fractional digit string divided by 10 once), so:

       "0.9999"  ->  0 + 9999/10  =  999.9      (NOT 0.9999)
       "999.9"   ->  999 + 9/10   =  999.9

   i.e. the two DIFFERENT literals collapse to the SAME double, and the value
   emitted for mes libc's own ceil() constant `0.9999` (lib/math/ceil.c) is
   exactly 999.9 -- the 8-byte constant observed in the self-rebuilt tcc-mes
   generation in the nix-bootstrapping riscv64 fixpoint forensics.

   Exit status: 0 iff the buggy values and the control values are all exactly
   as predicted, bit for bit.  */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

double mes_strtod (char const *string, char **tailptr);  /* lib/stdlib/strtod.c */

/* host-side helpers for the mes sources */
int __mes_debug (void) { return 0; }
void eputs (char const *s) { (void) s; }

static uint64_t
bits (double d)
{
  uint64_t u;
  memcpy (&u, &d, sizeof u);
  return u;
}

static int failures = 0;

static void
check (const char *what, double got, double want)
{
  if (bits (got) == bits (want))
    printf ("  [as predicted] %-42s = %.17g  (0x%016llX)\n", what, got,
            (unsigned long long) bits (got));
  else
    {
      printf ("  [UNEXPECTED]   %-42s = %.17g  (0x%016llX; predicted %.17g)\n",
              what, got, (unsigned long long) bits (got), want);
      failures++;
    }
}

int
main (void)
{
  double mes1 = mes_strtod ("0.9999", 0);
  double mes2 = mes_strtod ("999.9", 0);
  double ctl1 = strtod ("0.9999", 0);
  double ctl2 = strtod ("999.9", 0);

  printf ("mes strtod (verbatim mes-0.27.1 stack) vs. host strtod:\n");
  printf ("input \"0.9999\" (mes libc ceil()'s own literal):\n");
  printf ("  mes strtod  -> %.17g  (0x%016llX)\n", mes1, (unsigned long long) bits (mes1));
  printf ("  host strtod -> %.17g  (0x%016llX)\n", ctl1, (unsigned long long) bits (ctl1));
  check ("mes strtod(\"0.9999\") [expect the BUGGY 999.9]", mes1, 999.9);
  check ("host strtod(\"0.9999\") [control]", ctl1, 0.9999);

  printf ("input \"999.9\":\n");
  printf ("  mes strtod  -> %.17g  (0x%016llX)\n", mes2, (unsigned long long) bits (mes2));
  printf ("  host strtod -> %.17g  (0x%016llX)\n", ctl2, (unsigned long long) bits (ctl2));
  check ("mes strtod(\"999.9\")", mes2, 999.9);
  check ("host strtod(\"999.9\") [control]", ctl2, 999.9);

  if (bits (mes1) == bits (mes2))
    printf ("  => mes strtod CONFLATES \"0.9999\" and \"999.9\": both parse to the\n"
            "     byte-identical double 0x%016llX (999.9); a compiler whose literal\n"
            "     parser runs on this libc cannot tell the two source constants apart.\n",
            (unsigned long long) bits (mes1));
  else
    {
      printf ("  [UNEXPECTED] conflation did not occur\n");
      failures++;
    }

  return failures ? 1 : 0;
}
