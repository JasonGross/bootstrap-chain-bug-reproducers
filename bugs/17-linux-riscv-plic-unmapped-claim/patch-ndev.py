#!/usr/bin/env python3
"""Rewrite the PLIC's `riscv,ndev` property in a flattened device tree.

Same-length in-place edit of one u32 cell, so no FDT offsets need fixing.

Asserts loudly.  The whole point of the contrivance is that the poison source
(qemu virt's UART0 = PLIC source 10) must be numbered ABOVE `riscv,ndev`; if
qemu ever shipped a virt machine whose ndev was already <= 10, the "contrived"
DTB would be indistinguishable from the stock one and the reproducer would
silently stop demonstrating anything.  So we require the value we are lowering
to be comfortably above the source we use, and we require exactly one such
property to exist.
(AGENTS.md: "a substitution that matches nothing succeeds silently".)
"""
import struct
import sys

FDT_BEGIN_NODE, FDT_END_NODE, FDT_PROP, FDT_NOP, FDT_END = 1, 2, 3, 4, 9


def main(path, min_old, new, out):
    blob = bytearray(open(path, 'rb').read())
    magic, _totalsize, off_struct, off_strings = struct.unpack_from('>4I', blob, 0)
    if magic != 0xd00dfeed:
        sys.exit('not an FDT: magic %#x' % magic)
    size_struct = struct.unpack_from('>I', blob, 0x24)[0]

    hits = []
    off = off_struct
    end = off_struct + size_struct
    while off < end:
        (tok,) = struct.unpack_from('>I', blob, off)
        off += 4
        if tok == FDT_BEGIN_NODE:
            z = blob.index(b'\0', off)
            off = (z + 4) & ~3
        elif tok in (FDT_END_NODE, FDT_NOP):
            pass
        elif tok == FDT_END:
            break
        elif tok == FDT_PROP:
            plen, nameoff = struct.unpack_from('>II', blob, off)
            off += 8
            z = blob.index(b'\0', off_strings + nameoff)
            name = blob[off_strings + nameoff:z].decode()
            if name == 'riscv,ndev':
                hits.append((off, plen))
            off = (off + plen + 3) & ~3
        else:
            sys.exit('bad FDT token %d at %#x' % (tok, off - 4))

    if len(hits) != 1:
        sys.exit('expected exactly 1 riscv,ndev property in the dumped DTB, '
                 'found %d -- qemu changed its virt machine' % len(hits))
    poff, plen = hits[0]
    if plen != 4:
        sys.exit('riscv,ndev is %d bytes, expected a single u32 cell' % plen)
    (old,) = struct.unpack_from('>I', blob, poff)
    if old <= min_old:
        sys.exit('qemu virt already advertises riscv,ndev = %d (<= %d).  The '
                 'poison source would no longer be ABOVE ndev in the STOCK '
                 'DTB, so this reproducer would stop being contrived -- '
                 're-derive it before trusting the result.' % (old, min_old))
    struct.pack_into('>I', blob, poff, new)
    open(out, 'wb').write(blob)
    print('riscv,ndev: %d (qemu stock) -> %d (contrived)   '
          '[FDT offset %#x, written to %s]' % (old, new, poff, out))


if __name__ == '__main__':
    if len(sys.argv) != 5:
        sys.exit('usage: patch-ndev.py <in.dtb> <min-stock-ndev> <new> <out.dtb>')
    main(sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4])
