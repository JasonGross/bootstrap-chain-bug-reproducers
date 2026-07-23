/* Runtime probe, uncast leg (the exact tcc-0.9.26-1147 assert shape).
   A conforming compiler exits 0; the MesCC riscv64 miscompile exits 42.  */
unsigned
f (unsigned imm)
{
  return (imm + (1 << 11)) >> 12;
}

int
main ()
{
  unsigned imm = (unsigned) -16;
  if (f (imm) != 0)
    return 42;
  return 0;
}
