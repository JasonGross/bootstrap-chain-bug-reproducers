/* gcc-built receiver + freestanding driver (softfp). Receivers store received
   doubles' raw bits into OUT[]; _start invokes the tcc-built callers then writes
   OUT as raw bytes (no printf/varargs on the measured values). */
typedef union { unsigned long long u; double d; } U;
unsigned long long OUT[32]; int NO=0;
static void put(double x){ U t; t.d=x; OUT[NO++]=t.u; }
void r2(double a,double b){ put(a); put(b); }
void r3(double a,double b,double c){ put(a); put(b); put(c); }
void r4(double a,double b,double c,double d){ put(a); put(b); put(c); put(d); }
void rmix(int i,double a,int j,double b){ OUT[NO++]=(unsigned)i; put(a); OUT[NO++]=(unsigned)j; put(b); }
extern void c2(void), c3(void), c4(void), cmix(void);
static long sys_write(int fd,const void*buf,long n){
  register long r0 asm("r0")=fd; register long r1 asm("r1")=(long)buf;
  register long r2v asm("r2")=n; register long r7 asm("r7")=4;
  asm volatile("svc 0":"+r"(r0):"r"(r1),"r"(r2v),"r"(r7):"memory");
  return r0;
}
static void sys_exit(int c){
  register long r0 asm("r0")=c; register long r7 asm("r7")=1;
  asm volatile("svc 0"::"r"(r0),"r"(r7)); for(;;){}
}
void _start(void){
  c2(); c3(); c4(); cmix();
  sys_write(1, OUT, (long)NO*8);
  sys_exit(0);
}
