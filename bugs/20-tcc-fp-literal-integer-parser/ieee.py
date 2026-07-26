#!/usr/bin/env python3
"""ieee.py float|double <literal> -> the little-endian IEEE-754 bytes (hex).

The reference oracle for the FP-literal battery: a correctly-rounded conversion
done by CPython (a conforming implementation), independent of any C compiler's
.data layout.  Accepts the same C literal syntax the battery uses -- decimal or
0x hex-float, with an optional f/F/l/L suffix -- so the harness can feed the
exact string that appears in the .c file.
"""
import struct
import sys

kind, lit = sys.argv[1], sys.argv[2]
lit = lit.strip()
while lit and lit[-1] in "fFlL":
    lit = lit[:-1]
v = float.fromhex(lit) if "x" in lit.lower() else float(lit)
print(struct.pack("<f" if kind == "float" else "<d", v).hex())
