/* One hex-float literal.  tcc's preprocessor reconstructs the mantissa as an
   integer bignum, converts it to double, then finishes with
   `d = ldexp(d, exp)` (tccpp.c) -- i.e. the VALUE of this constant in the
   emitted object depends on the C library the RUNNING tcc binary links.  */
double x = 0x1p3; /* == 8.0 */
