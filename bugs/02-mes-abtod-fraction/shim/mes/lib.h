/* Minimal host-side stand-in for GNU Mes' <mes/lib.h>.  It provides ONLY the
   declarations that the unmodified Mes sources under test reference; the
   functions under test (abtod, abtol, isnumber) come verbatim from the
   mes-0.27.1 tarball.  */
#ifndef SHIM_MES_LIB_H
#define SHIM_MES_LIB_H
int __mes_debug (void);
void eputs (char const *s);
int isnumber (int c, int base);
long abtol (char const **p, int base);
double abtod (char const **p, int base);
#endif
