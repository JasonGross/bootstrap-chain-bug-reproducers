# `tcc-riscv64-absolute-relocs`

tinycc's riscv64 linker (`riscv64-link.c`) implements the **PC-relative**
`R_RISCV_PCREL_HI20` / `PCREL_LO12_I` / `PCREL_LO12_S` relocations, and the
TLS `TPREL_*` variants — but not the **absolute** forms:

| name | value | what emits it |
|---|---|---|
| `R_RISCV_HI20`   | 26 (`0x1a`) | the `lui` of a non-PIC `lui`+`addi` address materialisation |
| `R_RISCV_LO12_I` | 27 (`0x1b`) | the `addi`/load half of that pair |
| `R_RISCV_LO12_S` | 28 (`0x1c`) | the store half (`sw`/`sd`) |

All three are named in tcc's own `elf.h`; there is simply no `case` for them
in `code_reloc()`, `gotplt_entry_type()` or `relocate()`, so they fall into
the `default:` branch that prints `FIXME: handle reloc type %x`.

GCC emits these routinely for riscv64 — they are what an ordinary non-PIC
`lui`/`addi` pair uses — so **any** attempt to link a GCC-built riscv64
static libc with tcc runs into them. In the run this reproducer performs,
an unmodified musl 1.2.5 built by the distro's riscv64 GCC contains a few
thousand of them, spread over roughly a third of the archive's objects.

## What the job does

One musl, built here from pinned source by GCC. One trigger — four lines,
`printf` only. Four compilers:

| leg | compiler | link | binary | program output |
|---|---|---|---|---|
| **A**  | tinycc `mob` @ `85ba3ae8`, unpatched | **fails**, `Unknown relocation type for got: 26/27/28` | none | — |
| **A'** | the same tree **+ the 20-line patch** | clean, no diagnostics | yes | `HELLO from a tcc-linked musl binary` |
| **B**  | `tcc-0.9.26-1157-gdd46e018`, unpatched | **exits 0** with only `FIXME: handle reloc type 1a/1b/1c` notes | yes | *nothing at all* |
| **B'** | the same tree **+ the 20-line patch** | clean, no diagnostics | yes | `HELLO from a tcc-linked musl binary` |

**A/A' is the upstream-facing pair.** Mob turns the unhandled relocation
into a hard error — which is the right behaviour — so upstream's problem is
that the link is simply not possible, not that it is silently wrong.

**B/B' is the silent-failure mode, and it is fork-only.** `tcc-0.9.26-1157`
is janneke's mes-lineage fork, the riscv64 tcc the Guix/Mes riscv64 bootstrap
actually runs. Its `default:` branch prints a note and carries on, so a
toolchain gap becomes a plausible-looking executable that does nothing. B'
is what shows the silence is caused by these three relocations rather than
by the harness: same compiler, same link line, same libc, same trigger, plus
twenty lines.

The job **re-checks its own premise on every run**: it fetches live `mob`
and fails loudly if `riscv64-link.c` has grown a `case R_RISCV_HI20:`, so
this cannot rot into a false claim after upstream fixes it.

## The trigger is deliberately confound-free

```c
int printf(const char*,...);
int main(void){ printf("HELLO from a tcc-linked musl binary\n"); return 0; }
```

An earlier demonstration of this defect used a program that *also* tripped a
tcc struct-return codegen bug, and therefore proved nothing. This one has no
struct return, no floating point and no `#include`. `run.sh` asserts the
file's sha256 and greps its code for `struct`, so it cannot quietly drift
back into a confound.

## Two things that are *not* the bug (and why they are in the script)

- **`tf-stubs.c`.** riscv64 `long double` is IEEE binary128, and musl's
  `vfprintf` references the libgcc soft-float helpers (`__addtf3`,
  `__floatsitf`, …) for its `%Lf` path. We cannot hand tcc gcc's `libgcc.a`
  to satisfy them — it is itself full of the relocations under test — so the
  helpers are stubbed to `abort()`. They are unreachable for a `%s`-only
  `printf`. Without them the link would fail with *undefined symbols*, which
  is a completely different failure and would confound every leg.
- **No `-static`.** The chain-vintage fork's `-static` path NULL-derefs in
  `tidy_section_headers()` (`s1->dynsym` is null for a static link) — an
  unrelated, pre-existing fork bug that fires even with the patch applied.
  All four legs therefore link without `-static`, and the job copies musl's
  `libc.so` (which *is* the musl loader) to the `PT_INTERP` path tcc bakes
  in, for `qemu-user`. Every leg links `-nostdlib` against `libc.a` **by
  path**, so all of libc is statically linked in regardless.

## `-fno-pic` is load-bearing

Debian/Ubuntu GCC defaults to PIE. musl's `configure` detects that and sets
`AOBJS = $(LOBJS)`, so `libc.a` would be built from the **PIC** objects —
which use `GOT_HI20`/`PCREL_*` and carry *none* of the absolute relocations
this bug is about. The reproducer would then pass through and prove nothing.
`run.sh` passes `CFLAGS="-fno-pic -fno-pie"`, asserts that `config.mak` did
*not* take the PIC branch, and asserts the census of all three relocation
types is non-zero before it links anything.

## The patch

`apply-abs-relocs.py` adds the three relocations to both classifiers and
implements their field encodings in `relocate()` — 20 lines. Every edit is
asserted (anchor occurrence counts and post-conditions), because a scripted
edit that matches nothing succeeds silently and the "control" would then be
indistinguishable from the buggy build.

One detail the script handles: `relocate()`'s out-of-range diagnostic is
spelled `tcc_error()` in the chain-vintage tree but `tcc_error_noabort()` on
current mob, which poisons `tcc_error` inside that function. A patch written
against the fork does **not** compile on mob as-is. The script copies
whichever idiom the neighbouring `R_RISCV_PCREL_HI20` range check uses.

## Local run

```sh
sudo apt-get install -y gcc-riscv64-linux-gnu qemu-user-static
bash bugs/16-tcc-riscv64-absolute-relocs/run.sh
```

Intended upstream: **tinycc** (`tinycc-devel@nongnu.org`, repo.or.cz `mob`),
with a courtesy pointer to [`ekaitz-zarraga/tcc`](https://codeberg.org/ekaitz-zarraga/tcc).
The silent-failure half is a fork note, not part of the upstream ask.
