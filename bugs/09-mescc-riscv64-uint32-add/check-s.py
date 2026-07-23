#!/usr/bin/env python3
"""Assert the MesCC riscv64 .s discriminator for the uint32-wraparound bug.

Input: the M1 assembly mescc -S emitted for repro.c (functions f and g).
Both functions compute (imm + (1 << 11)) >> 12; g wraps the sum in a C no-op
(unsigned) cast.  MesCC truncates unsigned values to 32 bits with an
`... %0xffffffff ... and` sequence.  The bug: in f, the 64-bit `add` result
flows into the arithmetic-shift `sra` with NO truncating `and` in between;
only the cast in g makes MesCC emit it.

Exit 0 iff the buggy shape is present in f AND the correct shape in g.
"""
import re
import sys

path = sys.argv[1]
lines = open(path).read().splitlines()

def body(label):
    try:
        start = next(i for i, l in enumerate(lines) if l.strip() == ":" + label)
    except StopIteration:
        sys.exit("FATAL: no label :%s in %s" % (label, path))
    out = []
    for l in lines[start + 1:]:
        s = l.strip()
        if s.startswith(":") or s == "<":     # next label / section marker
            break
        if s:
            out.append(s)
    return out

def add_to_sra_slice(label):
    """Lines strictly between the (imm + 2048) `add` and the `sra`."""
    b = body(label)
    try:
        sra = next(i for i, l in enumerate(b) if l.endswith("sra"))
    except StopIteration:
        sys.exit("FATAL: no sra in :%s -- codegen shape changed?" % label)
    adds = [i for i, l in enumerate(b[:sra]) if re.search(r"rs2_t\d+ add$", l)]
    if not adds:
        sys.exit("FATAL: no add before sra in :%s" % label)
    return b, b[adds[-1] + 1:sra]

print("== emitted f (uncast, the tcc-1147 assert shape) ==")
fb, fslice = add_to_sra_slice("f")
print("\n".join("    " + l for l in fb))
print("== emitted g (with the C no-op (unsigned) cast) ==")
gb, gslice = add_to_sra_slice("g")
print("\n".join("    " + l for l in gb))

f_masked = any("0xffffffff" in l for l in fslice)
g_masked = any("0xffffffff" in l for l in gslice)

print()
print(">>> between the 32-bit add and the >>12 shift:")
print(">>>   f: %s" % ("re-mask %0xffffffff present" if f_masked
                       else "NO mod-2^32 truncation (64-bit sum flows into sra)  <-- THE BUG"))
print(">>>   g: %s" % ("re-mask %0xffffffff present (cast forces truncation)" if g_masked
                       else "NO truncation"))

if f_masked:
    sys.exit("bug did NOT reproduce: f truncates the sum")
if not g_masked:
    sys.exit("control failed: even the explicit cast in g emits no truncation")
print(">>> .s discriminator: BUG REPRODUCED (f untruncated, g truncated)")
