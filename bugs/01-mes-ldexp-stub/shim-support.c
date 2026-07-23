/* Host-side definitions for the two mes-libc helpers that the Mes source
   under test calls.  Debugging is off, exactly as in a default mes build.  */
int __mes_debug (void) { return 0; }
void eputs (char const *s) { (void) s; }
