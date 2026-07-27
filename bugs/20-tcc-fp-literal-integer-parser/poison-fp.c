/* A broken-FP bootstrap libc, in the form a MesCC-built tcc actually links.
 *
 * The janneke tinycc fork parses floating literals THROUGH the C library its
 * own binary is linked against (tccpp.c: the hex path ends in ldexp, the
 * decimal path calls strtof/strtod/strtold).  In a bootstrap the libc is
 * DOWNSTREAM of the compiler, so a broken-FP libc poisons every FP constant the
 * compiler emits (see bugs/05-tcc-fp-parse-libc-poison
 * for the mechanism).  GNU Mes' lib/stub/ldexp.c is literally `return 0;`, and
 * its strtod backend (abtod) is wrong.
 *
 * We reproduce that condition by interposing these four definitions via
 * -Wl,--wrap on the tcc binary (the tcc under test is -static, so LD_PRELOAD --
 * bug 05's method -- does not apply; --wrap redirects the calls at link time and
 * works in a static binary).  __wrap_ldexp returns 0 exactly as mes-libc does;
 * the strto* stubs return 0 for any input.  A tcc whose literal parser depends
 * on these will bake 0.0 for every literal; a tcc that parses with integer
 * arithmetic (patch 0013) will not call them at all.
 */
double      __wrap_ldexp  (double x, int e)          { (void)x; (void)e; return 0.0; }
double      __wrap_strtod (const char *s, char **e)  { if (e) *e = (char *)s; return 0.0; }
float       __wrap_strtof (const char *s, char **e)  { if (e) *e = (char *)s; return 0.0f; }
long double __wrap_strtold(const char *s, char **e)  { if (e) *e = (char *)s; return 0.0L; }
