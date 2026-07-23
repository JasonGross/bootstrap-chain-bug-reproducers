#!/usr/bin/env python3
"""Make the janneke tinycc fork's BOOTSTRAP+arm configuration compile under a
real (gcc) host compiler.  BOTH edits are DISJOINT from the bug under test
(init_putv's VT_LDOUBLE case in tccgen.c) and mirror what the nix-bootstrapping
arm bootstrap driver itself does:

1. arm-gen.c gfunc_prolog: under -DBOOTSTRAP, `avregs = AVAIL_REGS_INITIALIZER;`
   expands to `avregs = {0};`, which is not valid C (a brace list can
   initialize but not assign).  Rewrite as decl-init + struct assignment.

2. tccgen.c struct-copy/zero-init: the `#if BOOTSTRAP && __arm__` arms push
   TOK___memmove/TOK___memset, but tcctok.h only DEFs those tokens under
   `#ifndef TCC_ARM_EABI`; an EABI build must use the plain TOK_memmove /
   TOK_memset (-> __aeabi_*).  Gate the double-underscore uses off EABI.
"""
import sys

armgen, tccgen = sys.argv[1], sys.argv[2]

s = open(armgen).read()
old = "    avregs = AVAIL_REGS_INITIALIZER;"
new = "    { struct avail_regs _tmp = AVAIL_REGS_INITIALIZER; avregs = _tmp; }"
assert old in s, "arm-gen.c avregs pattern not found (fork changed?)"
open(armgen, "w").write(s.replace(old, new, 1))

s = open(tccgen).read()
n = 0
for tok in ("TOK___memmove", "TOK___memset"):
    guard = "#if BOOTSTRAP && __arm__\n"
    idx = s.find("vpush_global_sym(&func_old_type, %s);" % tok)
    assert idx >= 0, tok
    g = s.rfind(guard, 0, idx)
    assert g >= 0, tok
    s = s[:g] + "#if BOOTSTRAP && __arm__ && !defined (TCC_ARM_EABI)\n" + s[g + len(guard):]
    n += 1
assert n == 2
open(tccgen, "w").write(s)
print("mescc-era shims applied (arm-gen.c avregs; tccgen.c TOK___mem* EABI gate)")
