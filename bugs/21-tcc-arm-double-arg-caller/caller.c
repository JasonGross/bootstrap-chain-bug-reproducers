/* tcc under test compiles this. Values built from integer bit-puns (union) so
   the test isolates the softfp CALLER argument marshalling (bug19) and never
   depends on FP-literal parsing. */
typedef union { unsigned long long u; double d; } U;
extern void r2(double, double);
extern void r3(double, double, double);
extern void r4(double, double, double, double);
extern void rmix(int, double, int, double);
void c2(void){ U a,b; a.u=0x3FF8000000000000ULL; b.u=0x4002000000000000ULL;
               r2(a.d, b.d); }
void c3(void){ U a,b,c; a.u=0x3FF8000000000000ULL; b.u=0x4002000000000000ULL; c.u=0x400E000000000000ULL;
               r3(a.d, b.d, c.d); }
void c4(void){ U a,b,c,d; a.u=0x3FF8000000000000ULL; b.u=0x4002000000000000ULL; c.u=0x400E000000000000ULL; d.u=0x4012000000000000ULL;
               r4(a.d, b.d, c.d, d.d); }
void cmix(void){ U a,b; a.u=0x3FF8000000000000ULL; b.u=0x4002000000000000ULL;
                 rmix(7, a.d, 9, b.d); }
