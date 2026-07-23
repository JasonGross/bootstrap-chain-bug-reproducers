/* Drives GNU Mes' strtod backend `abtod` (compiled verbatim from the
   mes-0.27.1 tarball, together with its helpers abtol and isnumber) against
   the host libc's strtod as the correct-behavior control.

   Bug 1 (fraction scaling): abtod computes  d = i + f / dbase  -- the WHOLE
   fractional digit string (parsed as one integer f) divided by the base (10)
   exactly once, instead of by 10^(number of fractional digits).  So
   "123456.75" parses as 123456 + 75/10 = 123463.5.

   Bug 2 (32-bit integer accumulation): abtol accumulates into a 32-bit `int`,
   so the integer part of "4294967296.0" (2^32) wraps to 0.

   Exit status: 0 iff BOTH buggy values and BOTH control values are exactly as
   predicted.  */
#include <stdio.h>
#include <stdlib.h>

/* mes-0.27.1/lib/mes/abtod.c */
double abtod (char const **p, int base);

/* host-side helpers for the mes sources */
int __mes_debug (void) { return 0; }
void eputs (char const *s) { (void) s; }

static int failures = 0;

static double
mes_parse (const char *s)
{
  const char *p = s;
  return abtod (&p, 10);
}

static void
check (const char *what, double got, double want)
{
  if (got == want)
    printf ("  [as predicted] %s = %.17g\n", what, got);
  else
    {
      printf ("  [UNEXPECTED]   %s = %.17g (predicted %.17g)\n", what, got, want);
      failures++;
    }
}

int
main (void)
{
  printf ("mes abtod vs. host strtod:\n");
  double mes1 = mes_parse ("123456.75");
  double ctl1 = strtod ("123456.75", 0);
  printf ("input \"123456.75\":\n");
  printf ("  mes abtod  -> %.17g\n", mes1);
  printf ("  host strtod-> %.17g\n", ctl1);
  check ("mes abtod(\"123456.75\") [expect the BUGGY 123456 + 75/10]", mes1, 123463.5);
  check ("host strtod(\"123456.75\") [control]", ctl1, 123456.75);

  double mes2 = mes_parse ("4294967296.0");
  double ctl2 = strtod ("4294967296.0", 0);
  printf ("input \"4294967296.0\" (= 2^32; integer part wraps mes' 32-bit accumulator):\n");
  printf ("  mes abtod  -> %.17g\n", mes2);
  printf ("  host strtod-> %.17g\n", ctl2);
  check ("mes abtod(\"4294967296.0\") [expect the BUGGY 2^32 mod 2^32 = 0]", mes2, 0.0);
  check ("host strtod(\"4294967296.0\") [control]", ctl2, 4294967296.0);

  return failures ? 1 : 0;
}
