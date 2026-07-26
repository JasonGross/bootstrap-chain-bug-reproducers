/* Drives GNU Mes' float->decimal routine `dtoab` (compiled VERBATIM from the
   mes-0.27.1 tarball, with its helper ntoab) against the host libc as the
   correct-behavior control.

   dtoab is what mes libc's printf("%f"/"%e"/"%g") calls -- lib/stdio/vfprintf.c
   case 'f' does exactly `char *s = dtoab (d, 10, 1);`.  Its fractional part is
   computed as

       long f = (d - (double) i) * (double) 100000000;
       ... ntoab (f, base, 1) ...          <- printed with NO zero padding

   so every leading zero of the fraction is LOST: the digits are printed as a
   plain integer.  0.0625 has fraction digits "0625", which print as "625".
   The decimal point therefore lands in the wrong place, by a factor of 10 per
   dropped zero.  Trailing zeros are then stripped, so a fraction that is all
   zeros after scaling vanishes entirely.

   This is the OUTPUT-side mirror of the abtod input-side bug (bug 2 in this
   repo): both lose the position of the decimal point, and both can map two
   different numbers onto the same text.

   Exit status: 0 iff every buggy value and every control value is exactly as
   predicted.  */
#include <stdio.h>
#include <string.h>

char *dtoab (double d, int base, int signed_p);

/* host-side helpers for the mes sources */
int __mes_debug (void) { return 0; }
void eputs (char const *s) { (void) s; }
void assert_msg (int condition, char const *message)
{
  if (!condition)
    printf ("  (mes assert_msg: %s)\n", message);
}

static int failures = 0;

static void
check (double d, const char *want_mes, const char *note)
{
  char *got = dtoab (d, 10, 1);
  if (!strcmp (got, want_mes))
    printf ("  [as predicted] mes dtoab(%-14.10g) = %-10s  (correct: %.10g)  %s\n",
            d, got, d, note);
  else
    {
      printf ("  [UNEXPECTED]   mes dtoab(%-14.10g) = %-10s  (predicted %s)\n",
              d, got, want_mes);
      failures++;
    }
}

int
main (void)
{
  printf ("mes lib/mes/dtoab.c -- the float->decimal routine behind printf(\"%%f\"):\n");

  check (1.0625, "1.625", "fraction .0625 -> \"625\": one zero dropped, 10x off");
  check (0.0625, "0.625", "same, on a value < 1");
  check (3.0009, "3.9",   "fraction .0009 -> \"9\": THREE zeros dropped, 1000x off");
  check (0.05,   "0.5",   "10x off ...");
  check (0.005,  "0.5",   "... and 100x off -- BOTH print as \"0.5\"");
  check (0.5,    "0.5",   "... which is also what the CORRECT 0.5 prints as");
  check (2.00000001, "2", "fraction scaled to <1 and stripped: silently vanishes");

  printf ("\n  control -- the host libc on the same values:\n");
  const double v[] = { 1.0625, 0.0625, 3.0009, 0.05, 0.005, 0.5, 2.00000001 };
  for (int i = 0; i < 7; i++)
    printf ("    printf(\"%%.10g\") -> %.10g\n", v[i]);

  /* The conflation is the sharpest single fact: three different doubles all
     render as the same text, so the output cannot be parsed back. */
  if (!strcmp (dtoab (0.05, 10, 1), dtoab (0.5, 10, 1))
      && !strcmp (dtoab (0.005, 10, 1), dtoab (0.5, 10, 1)))
    printf ("\n  => 0.005, 0.05 and 0.5 ALL render as \"%s\": a generator that\n"
            "     prints a float through mes libc emits text that cannot be\n"
            "     read back as the value it had.\n", dtoab (0.5, 10, 1));
  else
    {
      printf ("\n  [UNEXPECTED] the three-way conflation did not occur\n");
      failures++;
    }

  return failures ? 1 : 0;
}
