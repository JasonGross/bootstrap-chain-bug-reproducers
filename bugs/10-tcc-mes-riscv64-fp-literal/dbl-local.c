/* MesCC leg, local double: MesCC (which has no floating-point support at
   all) lowers this to an INTEGER addi whose immediate is the literal string:
       rd_t0 rs1_x0 !0.9999 addi
   -- i.e. nothing upstream of tcc-musl in the mes lineage can materialize an
   IEEE-754 constant.  */
double
h (void)
{
  double d = 0.9999;
  return d;
}
