/* No struct-return trigger — just printf, to isolate the RELOCATION defect from
 * the codegen defect. Links against GCC-built musl, which carries R_RISCV_HI20. */
int printf(const char*,...);
int main(void){ printf("HELLO from a tcc-linked musl binary\n"); return 0; }
