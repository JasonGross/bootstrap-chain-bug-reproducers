/* Minimal host-side stand-in for GNU Mes' <mes/lib.h>.  It declares ONLY what
   the unmodified Mes sources under test reference; dtoab and ntoab come
   verbatim from the mes-0.27.1 tarball.  */
#ifndef SHIM_MES_LIB_H
#define SHIM_MES_LIB_H
int __mes_debug (void);
void eputs (char const *s);
void assert_msg (int condition, char const *message);
char *ntoab (long x, unsigned base, int signed_p);
char *dtoab (double d, int base, int signed_p);
#endif
