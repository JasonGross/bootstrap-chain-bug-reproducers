#!/usr/bin/env python3
"""check-data.py <data.bin> buggy|control

data.bin = the raw .data section of ldconst.o:
  bytes 0..7  : long double big  = 1000000000.0L (on ARM EABI, == double)
  bytes 8..15 : double      frac = 2.5

buggy   : assert big is ALL ZERO (empty VT_LDOUBLE store) and frac is the
          converting-store integer 2 (0x0000000000000002).
control : assert big == IEEE-754 1e9 (0x41CDCD6500000000) and frac == 2.5
          (0x4004000000000000).
"""
import struct
import sys

data = open(sys.argv[1], "rb").read()
mode = sys.argv[2]
assert len(data) >= 16, "expected >= 16 bytes of .data, got %d" % len(data)
big, frac = data[0:8], data[8:16]


def show(name, b):
    (as_double,) = struct.unpack("<d", b)
    print("  %-4s bytes (LE) = %s   as double = %.17g" % (name, b.hex(), as_double))


show("big", big)
show("frac", frac)

if mode == "buggy":
    assert big == bytes(8), (
        "expected the EMPTY VT_LDOUBLE store to leave 1000000000.0L all-zero, got " + big.hex())
    assert frac == struct.pack("<q", 2), (
        "expected the converting VT_DOUBLE store to turn 2.5 into integer 2, got " + frac.hex())
    print("  -> BUG REPRODUCED: long double constant materialized as 0.0 "
          "(and double 2.5 as the integer 2)")
elif mode == "control":
    assert big == struct.pack("<d", 1e9), big.hex()
    assert frac == struct.pack("<d", 2.5), frac.hex()
    print("  -> CONTROL OK: gcc materializes 0x41CDCD6500000000 (1e9) and "
          "0x4004000000000000 (2.5)")
else:
    sys.exit("mode must be buggy|control")
