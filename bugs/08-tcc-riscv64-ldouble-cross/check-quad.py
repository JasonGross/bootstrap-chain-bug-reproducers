#!/usr/bin/env python3
"""check-quad.py <data.bin> prefix|fixed

data.bin = the raw 16-byte .data section of ldc.o (long double x = 1e9L,
target riscv64, so IEEE-754 binary128).

The mathematically expected binary128 image of 1e9:
  sign 0, exponent 16383+29 = 0x401C, mantissa 1e9/2^29 - 1 -> 0xDCD650...0
  big-endian    401CDCD65000...00
  little-endian 000000000000000000000050D6DC1C40

The pre-fix cross tcc instead wrote the HOST x86_64 x87 80-bit image of 1e9
(LE 00000000 00286BEE 1C40, i.e. mantissa 0xEE6B280000000000 + exponent
0x401C) into the low 10 bytes of the slot.
"""
import struct
import sys

data = open(sys.argv[1], "rb").read()
mode = sys.argv[2]
assert len(data) >= 16, "expected 16 bytes of .data, got %d" % len(data)
got = data[:16]

# compute binary128(1e9) from integer arithmetic (no host FP)
val = 10**9
e = val.bit_length() - 1                    # 29
frac = (val - (1 << e)) << (112 - e)        # 112-bit mantissa field
quad_be = ((16383 + e) << 112 | frac).to_bytes(16, "big")
quad_le = quad_be[::-1]

x87_le = struct.pack("<QH", (val << (63 - e)), 16383 + e)  # 80-bit x87 image
prefix_expect = x87_le + bytes(16 - len(x87_le))

print("  got .data (LE)              = %s" % got.hex())
print("  correct binary128(1e9) (LE) = %s" % quad_le.hex())
print("  host x87 image, padded (LE) = %s" % prefix_expect.hex())

if mode == "prefix":
    assert got != quad_le, "pre-fix tcc emitted the CORRECT quad -- bug gone?"
    assert got == prefix_expect, (
        "pre-fix tcc emitted neither the correct quad nor the expected "
        "host-x87 image: " + got.hex())
    print("  -> BUG REPRODUCED: the emitted bytes are the host's x87 80-bit")
    print("     image (padded), NOT the target's binary128 encoding")
elif mode == "fixed":
    assert got == quad_le, "post-fix tcc did not emit the correct binary128"
    print("  -> CONTROL OK: the fix emits the correct target binary128 image")
elif mode == "gcc":
    assert got == quad_le, "riscv64 gcc oracle disagrees with computed binary128?!"
    print("  -> ORACLE OK: riscv64-linux-gnu-gcc emits the same binary128 image")
else:
    sys.exit("mode must be prefix|fixed|gcc")
