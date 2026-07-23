/* LD_PRELOAD shim: a broken-FP C library, modeled on GNU Mes' lib/stub/ldexp.c
   (whose body is literally `return 0;`).  Interposes the mantissa-scaling
   functions tcc's floating-literal parser leans on.  */
double ldexp (double x, int n) { (void) x; (void) n; return 0; }
long double ldexpl (long double x, int n) { (void) x; (void) n; return 0; }
float ldexpf (float x, int n) { (void) x; (void) n; return 0; }
double scalbn (double x, int n) { (void) x; (void) n; return 0; }
long double scalbnl (long double x, int n) { (void) x; (void) n; return 0; }
