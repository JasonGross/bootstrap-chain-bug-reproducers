/* Quad (128-bit long double) soft-float STUBS.
 * riscv64 long double is IEEE binary128; musl's vfprintf references these
 * libgcc helpers for the %Lf path.  TinyEMU NEVER formats a long double (its
 * only float output is %f/%g on double), so these are unreachable in temu.
 * Stubbed to abort so any reachability would be loud rather than silent.
 * Linked INSTEAD of gcc's libgcc.a, which this tcc's riscv64 linker cannot
 * consume (FIXME: handle reloc type 1a = R_RISCV_HI20 in gcc-built objects). */
void abort(void);
static void tf_unreachable(void){ abort(); }
long double __addtf3(long double a,long double b){(void)a;(void)b;tf_unreachable();return 0;}
long double __subtf3(long double a,long double b){(void)a;(void)b;tf_unreachable();return 0;}
long double __multf3(long double a,long double b){(void)a;(void)b;tf_unreachable();return 0;}
long double __extenddftf2(double a){(void)a;tf_unreachable();return 0;}
int __netf2(long double a,long double b){(void)a;(void)b;tf_unreachable();return 0;}
int __fixtfsi(long double a){(void)a;tf_unreachable();return 0;}
unsigned int __fixunstfsi(long double a){(void)a;tf_unreachable();return 0;}
long double __floatsitf(int a){(void)a;tf_unreachable();return 0;}
long double __floatunsitf(unsigned int a){(void)a;tf_unreachable();return 0;}
