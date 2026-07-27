/* Drives GNU Mes' strtod backend `abtod` (compiled verbatim from the
   mes-0.27.1 tarball, with its helpers abtol and isnumber) against the host
   libc's strtod as the correct-behavior control.

   Bug under test (negative-exponent off-by-one-decade): abtod's exponent
   scaling is

       if (e < 0)
         while (e++)
           d = d / dbase;
       while (e--)
         d = d * dbase;

   The post-increment in the first loop fires on the loop-EXITING test too, so
   after it ends e == 1 (not 0), and the second loop then multiplies once:
   a negative exponent -n is applied as 10^(1-n).  "5e-1" parses as 5.0.

   Composed with the two defects of reproducer #2 (whole fraction divided by
   10 once; 32-bit wrap in abtol), this maps musl-1.1.24 src/math/log10.c's
   own constants -- when a mes-libc-linked compiler parses them -- to exact,
   predictable garbage.  In the riscv64 full-source bootstrap
   (ekaitz-zarraga/commencement.scm) that garbage log10_2hi is what makes
   flex 2.5.39 die with "fatal internal error, allocation of macro definition
   failed" on GCC's gengtype-lex.l: flex main.c sizes an allocation with
   (int)(1 + log10(i)) per start condition.

   The predictions below are IEEE-754 double results of the exact operation
   sequence abtod performs (int32-wrapped digit accumulation, one divide by
   10.0, mis-scaled exponent); they are architecture-independent.

   ABLATE=1 (set by run.sh's ablation step): route the "mes" legs through the
   host's correct strtod instead.  Every buggy-value prediction must then FAIL
   -- proving these assertions are capable of noticing the bug's absence.

   Exit status: 0 iff all predictions (buggy AND control) hold.  */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

/* mes-0.27.1/lib/mes/abtod.c */
double abtod (char const **p, int base);

/* host-side helpers for the mes sources */
int __mes_debug (void) { return 0; }
void eputs (char const *s) { (void) s; }

static int failures = 0;
static int ablate = 0;

static double
mes_parse (const char *s)
{
  const char *p = s;
  if (ablate)
    return strtod (s, 0);       /* ablation: the correct parser */
  return abtod (&p, 10);
}

static uint64_t
bits_of (double d)
{
  uint64_t u;
  memcpy (&u, &d, 8);
  return u;
}

static void
check_bits (const char *what, double got, uint64_t want_bits)
{
  if (bits_of (got) == want_bits)
    printf ("  [as predicted] %-52s = %.17g (bits %016llx)\n",
            what, got, (unsigned long long) bits_of (got));
  else
    {
      printf ("  [UNEXPECTED]   %-52s = %.17g (bits %016llx, predicted %016llx)\n",
              what, got, (unsigned long long) bits_of (got),
              (unsigned long long) want_bits);
      failures++;
    }
}

static void
check_int (const char *what, long got, long want)
{
  if (got == want)
    printf ("  [as predicted] %-52s = %ld\n", what, got);
  else
    {
      printf ("  [UNEXPECTED]   %-52s = %ld (predicted %ld)\n", what, got, want);
      failures++;
    }
}

int
main (void)
{
  ablate = getenv ("ABLATE") && *getenv ("ABLATE") == '1';
  if (ablate)
    printf ("ABLATION MODE: mes legs rerouted to host strtod; "
            "buggy-value predictions must now FAIL\n\n");

  printf ("== the off-by-one-decade, minimal form ==\n");
  check_bits ("mes abtod(\"5e-1\")  [BUGGY: exponent -1 applied as 10^0]",
              mes_parse ("5e-1"), bits_of (5.0));
  check_bits ("mes abtod(\"5e-2\")  [BUGGY: exponent -2 applied as 10^-1]",
              mes_parse ("5e-2"), bits_of (0.5));
  check_bits ("mes abtod(\"5e+2\")  [positive exponents are fine]",
              mes_parse ("5e+2"), bits_of (500.0));
  check_bits ("host strtod(\"5e-1\") [control]",
              strtod ("5e-1", 0), bits_of (0.5));
  check_bits ("host strtod(\"5e-2\") [control]",
              strtod ("5e-2", 0), bits_of (0.05));

  printf ("\n== why it hides: simple literals come out right ==\n");
  check_bits ("mes abtod(\"0.5\")", mes_parse ("0.5"), bits_of (0.5));
  check_bits ("mes abtod(\"2.5\")", mes_parse ("2.5"), bits_of (2.5));

  printf ("\n== musl-1.1.24 src/math/log10.c constants through mes abtod ==\n");
  printf ("(run.sh greps these exact literals out of the pinned musl tarball\n"
          " before this runs; a mes-libc-linked compiler parses every FP\n"
          " literal with this abtod)\n");
  /* log10_2hi = 3.01029995663611771306e-01:
     fraction "01029995663611771306" wraps int32 to 1371912618, one /10,
     e-01 not applied  ->  3 + 137191261.8  =  137191264.8  */
  check_bits ("mes abtod(\"3.01029995663611771306e-01\") [log10_2hi]",
              mes_parse ("3.01029995663611771306e-01"),
              UINT64_C (0x41A05ABEC199999A) /* 137191264.8 */);
  /* ivln10hi = 4.34294481878168880939e-01 -> 4 + 2018756395/10  */
  check_bits ("mes abtod(\"4.34294481878168880939e-01\") [ivln10hi]",
              mes_parse ("4.34294481878168880939e-01"),
              UINT64_C (0x41A810C177000000) /* 201875643.5 */);
  /* log10(2) itself, as a literal: 20 fractional digits wrap NEGATIVE  */
  check_bits ("mes abtod(\"0.30102999566398119521\")     [log10(2)]",
              mes_parse ("0.30102999566398119521"),
              UINT64_C (0xC171C368FE666666) /* -18626191.9 */);
  check_bits ("host strtod(\"3.01029995663611771306e-01\") [control]",
              strtod ("3.01029995663611771306e-01", 0),
              UINT64_C (0x3FD34413509F6000));
  check_bits ("host strtod(\"4.34294481878168880939e-01\") [control]",
              strtod ("4.34294481878168880939e-01", 0),
              UINT64_C (0x3FDBCB7B15200000));
  check_bits ("host strtod(\"0.30102999566398119521\")     [control]",
              strtod ("0.30102999566398119521", 0),
              UINT64_C (0x3FD34413509F79FF));

  printf ("\n== the flex 2.5.39 crash arithmetic ==\n");
  printf ("flex main.c sizes a per-start-condition allocation with\n"
          "(int)(1 + log10(i)); a libm whose log10_2hi is the value above\n"
          "returns ~1.3719e8 for log10(2):\n");
  check_int ("(int)(1 + [mes-parsed log10_2hi])  [BUGGY: the flex alloc size]",
             (long) (1 + mes_parse ("3.01029995663611771306e-01")),
             137191265);
  printf ("  -> a ~137 MB allocation per start condition; when it fails, flex\n"
          "     aborts: \"fatal internal error, allocation of macro definition"
          " failed\"\n");

  if (ablate)
    {
      /* the six buggy-value predictions above must all have failed */
      if (failures == 5 + 1) /* 5e-1, 5e-2, log10_2hi, ivln10hi, log10(2), int */
        {
          printf ("\nABLATION OK: exactly the %d buggy-value predictions "
                  "failed; the harness notices the bug's absence\n", failures);
          return 0;
        }
      printf ("\nABLATION BROKEN: %d predictions failed (expected 6)\n",
              failures);
      return 1;
    }

  return failures ? 1 : 0;
}
