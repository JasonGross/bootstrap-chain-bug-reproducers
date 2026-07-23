/* Runtime probe, cast leg (the tcc rev-1157 dodge shape).  The (unsigned)
   cast is a C no-op, but it makes MesCC emit the missing mod-2^32 re-mask,
   so even the MesCC-built binary exits 0.  Exit 43 would mean the cast leg
   broke too (never observed).  */
unsigned
g (unsigned imm)
{
  return ((unsigned) (imm + (1 << 11))) >> 12;
}

int
main ()
{
  unsigned imm = (unsigned) -16;
  if (g (imm) != 0)
    return 43;
  return 0;
}
