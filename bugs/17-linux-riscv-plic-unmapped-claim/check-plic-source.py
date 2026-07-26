#!/usr/bin/env python3
"""Assert the accused shape of `plic_handle_irq()` in irq-sifive-plic.c.

Two modes:

  unfixed <file>   the claim/complete leak is PRESENT: the function claims with
                   readl(claim), warns about the unmapped hwirq, and contains
                   NO write back to the claim register anywhere.
  fixed <file>     our one-line fix is in: same function, but it now writes the
                   hwirq back.

Mode `unfixed` is the reproducer's premise guard.  It is run against BOTH the
pinned tarball we build and (when reachable) upstream's live default branch: if
someone lands the completion upstream, this fails loudly rather than letting the
report rot into a false claim about current mainline.
"""
import re
import sys

WARN = "can't find mapping for hwirq"


def extract(path):
    src = open(path, encoding='utf-8', errors='replace').read()
    m = re.search(r'^static void plic_handle_irq\(.*?^\}', src, re.S | re.M)
    if not m:
        sys.exit('FAIL: no plic_handle_irq() found in %s -- the driver has been '
                 'restructured; a human must re-read the report' % path)
    return m.group(0)


def main(mode, path):
    body = extract(path)
    print('--- plic_handle_irq() as found in %s ---' % path)
    print(body)
    print('--- end ---')

    if 'readl(claim)' not in body:
        sys.exit('FAIL: plic_handle_irq() no longer claims with readl(claim); '
                 'the mechanism has changed -- re-read the report')
    if WARN not in body:
        sys.exit('FAIL: the unmapped-hwirq warning is gone from '
                 'plic_handle_irq(); upstream has restructured or fixed this '
                 '-- a human must re-read the report before it is sent')

    writes_back = re.search(r'writel\s*\(\s*hwirq\s*,\s*claim\s*\)', body)
    if mode == 'unfixed':
        if writes_back:
            sys.exit('FAIL: plic_handle_irq() ALREADY completes the claim on '
                     'the unmapped branch (writel(hwirq, claim) present).\n'
                     '      Upstream appears to have FIXED this. The report is '
                     'no longer true of this source -- do not re-pin to silence '
                     'this; a human must re-read it.')
        print('OK: claims with readl(claim), warns on the unmapped hwirq, and '
              'never writes the ID back -> the claim is leaked.')
    elif mode == 'fixed':
        if not writes_back:
            sys.exit('FAIL: the fix patch did not take effect -- '
                     'writel(hwirq, claim) is absent from plic_handle_irq()')
        print('OK: the fixed build completes the claim on the unmapped branch.')
    else:
        sys.exit('usage: check-plic-source.py <unfixed|fixed> <file>')


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit('usage: check-plic-source.py <unfixed|fixed> <file>')
    main(sys.argv[1], sys.argv[2])
