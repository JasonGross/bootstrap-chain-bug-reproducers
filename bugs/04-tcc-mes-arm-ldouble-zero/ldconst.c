/* Two initialized globals; their IEEE-754 images land in .data.
   On ARM EABI, long double == double == 8 bytes.

   big : the VT_LDOUBLE case of init_putv.  Under BOOTSTRAP && __arm__ the
         store is an EMPTY block ("XXX TODO: breaks on mescc/tcc-mes based
         build"), so the .data slot stays zero-filled -> 0.0.
   frac: the VT_DOUBLE case sibling (same guard): a CONVERTING assignment
         (*llptr = vtop->c.d) stores (long long)2.5 == 2 instead of the bit
         pattern -> 0x0000000000000002.  */
long double big = 1000000000.0L;
double frac = 2.5;
