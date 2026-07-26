#!/usr/bin/env python3
"""Extract tcc's riscv64 12-bit-immediate guard VERBATIM from a source tree and
emit a probe that evaluates exactly that expression.

We do not retype the expression: it is lifted character-for-character out of
`riscv64-gen.c`'s EI() from the pinned tarball, so the probe cannot drift from
what the pinned compiler actually compiles.

usage: extract-guard.py <riscv64-gen.c> <out.c> <label>
"""
import pathlib
import re
import sys

src = pathlib.Path(sys.argv[1]).read_text()
out = pathlib.Path(sys.argv[2])
label = sys.argv[3]

# The guard sits in EI(): assert(! (<EXPR>));
m = re.search(r"^\s*assert\(!\s*(\(.*\))\);\s*$", src, re.M)
if not m:
    sys.exit("FATAL: no assert(! ...) guard found in %s" % sys.argv[1])
expr = m.group(1)
line_no = src[: m.start()].count("\n") + 1

print("    %s: %s:%d" % (label, pathlib.Path(sys.argv[1]).name, line_no))
print("      %s" % m.group(0).strip())

out.write_text("""/* GENERATED -- do not edit.
 * The guard expression below is lifted VERBATIM from
 *   %s line %d
 * which is the body of tcc's EI() (and identically ES()): the assertion that
 * an immediate fits RISC-V's signed 12-bit field.
 *
 * Evaluated with imm = (unsigned)-16, which is the immediate of the very first
 * instruction any tcc-generated function epilogue emits: `addi sp,sp,-16`.
 * The assertion is written to PASS for that value (C wraps the unsigned add
 * mod 2^32: 0xfffffff0 + 0x800 = 0x7f0, >> 12 == 0), so a conforming compiler
 * exits 0.  A compiler that evaluates the 32-bit add in 64 bits without
 * re-truncating gets 0x100000 and the assertion FIRES -- exit 42.
 */
typedef unsigned int uint32_t;

unsigned
guard (unsigned imm)
{
  return %s;
}

int
main ()
{
  if (guard ((unsigned) -16))
    return 42;                  /* assert would fire -> tcc dies here */
  return 0;                     /* assert passes -> tcc proceeds */
}
""" % (pathlib.Path(sys.argv[1]).name, line_no, expr))
