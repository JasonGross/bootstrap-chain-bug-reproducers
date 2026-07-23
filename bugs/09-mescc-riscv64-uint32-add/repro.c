/* MesCC riscv64 unsigned-32-bit wraparound miscompile -- minimal probe.
 *
 * C semantics: `unsigned` arithmetic is mod 2^32.  For imm = (unsigned) -16
 * = 0xfffffff0, the expression in `f` is
 *     (0xfffffff0 + 0x800) mod 2^32 = 0x7f0,   0x7f0 >> 12 = 0.
 * MesCC's riscv64 backend performs the add in a full 64-bit register and
 * feeds the UNtruncated 64-bit result (0x1000007f0) straight to the shift:
 * f evaluates to 0x100000 instead of 0.
 *
 * `g` is the same expression with an explicit (unsigned) cast on the sum;
 * MesCC then re-masks with 0xffffffff after the add and compiles it
 * correctly -- the cast is semantically a no-op in C (the sum already HAS
 * type unsigned), which is what makes `f` a genuine miscompile.
 *
 * In-chain consequence: tcc 0.9.26-1147 (the mes-lineage riscv64 tcc)
 * guards its 12-bit immediates with
 *     assert(!((imm + (1 << 11)) >> 12))        [imm is uint32_t]
 * exactly the `f` shape, so the MesCC-built tcc-mes asserts out on EVERY
 * negative immediate -- fatally, on the first function epilogue it ever
 * emits (addi sp,sp,-16).  tcc rev 1157 dodges it with the explicit
 * (uint32_t) cast, i.e. the `g` shape.
 */
unsigned f (unsigned imm)
{
  return (imm + (1 << 11)) >> 12;
}

unsigned g (unsigned imm)
{
  return ((unsigned) (imm + (1 << 11))) >> 12;
}
