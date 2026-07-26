#!/usr/bin/env python3
"""Lay the R6RS library sources out where Guile's loader will find them.

These are R6RS libraries distributed as .sls files (the Akku convention);
Guile looks for .scm on GUILE_LOAD_PATH.  Where a library ships an
implementation-specific variant (foo.guile.sls) that one wins, exactly as
Akku/R6RS implementations select it.  Nothing is modified -- files are
copied verbatim, only renamed.

usage: build-libtree.py <destdir> <srcdir>:<library-prefix> ...
"""
import pathlib
import re
import shutil
import sys

OTHER_IMPLS = re.compile(
    r"\.(ikarus|loko|chez|racket|mzscheme|ypsilon|larceny|sagittarius|chibi)$")

dest = pathlib.Path(sys.argv[1])

for spec in sys.argv[2:]:
    srcdir, prefix = spec.rsplit(":", 1)
    root = pathlib.Path(srcdir)
    for f in sorted(list(root.rglob("*.sls")) + list(root.rglob("*.scm"))):
        if "tests" in f.parts:
            continue
        rel = f.relative_to(root)
        name = rel.name
        guile_specific = name.endswith(".guile.sls")
        if guile_specific:
            base = name[: -len(".guile.sls")]
        elif name.endswith(".sls"):
            base = name[: -len(".sls")]
        else:
            base = name[: -len(".scm")]
        if OTHER_IMPLS.search(base):
            continue
        out = dest / prefix / rel.parent / (base + ".scm")
        out.parent.mkdir(parents=True, exist_ok=True)
        if out.exists() and not guile_specific:
            continue
        shutil.copy(f, out)

print("library tree:")
for p in sorted(dest.rglob("*.scm")):
    print("   ", p.relative_to(dest))
