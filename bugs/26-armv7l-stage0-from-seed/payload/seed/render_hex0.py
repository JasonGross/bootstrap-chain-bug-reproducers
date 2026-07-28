#!/usr/bin/env python3
"""Minimal host-lineage hex0 renderer (independent check on the seed lineage).

Implements the hex0 language exactly as the stage0 seeds do: '#' and ';'
start a comment that runs to end-of-line; hex digits (0-9 a-f A-F) pair up
into bytes; every other character is ignored.  Usage:

    render_hex0.py <input.hex0> <output-binary>
"""
import sys


def render(text: bytes) -> bytes:
    out = bytearray()
    hi = None
    i = 0
    n = len(text)
    while i < n:
        c = text[i]
        if c in (0x23, 0x3B):  # '#' or ';'
            while i < n and text[i] != 0x0A:
                i += 1
            continue
        v = None
        if 0x30 <= c <= 0x39:
            v = c - 0x30
        elif 0x61 <= c <= 0x66:
            v = c - 0x57
        elif 0x41 <= c <= 0x46:
            v = c - 0x37
        if v is not None:
            if hi is None:
                hi = v
            else:
                out.append((hi << 4) | v)
                hi = None
        i += 1
    return bytes(out)


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit("usage: render_hex0.py <input.hex0> <output-binary>")
    with open(sys.argv[1], "rb") as f:
        data = f.read()
    with open(sys.argv[2], "wb") as f:
        f.write(render(data))


if __name__ == "__main__":
    main()
