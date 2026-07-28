# bootstrap-chain-bug-reproducers

Self-contained CI reproducers for upstream-reportable bugs found by a
full-source-bootstrap measurement project while driving the hex0 → Mes/MesCC →
tcc → musl → GCC chain on x86, ARM, and RISC-V.

**Staleness guard.** A pinned reproducer proves the bug existed at the pin; it
cannot notice that upstream has since *fixed* it, so a report can quietly go
stale while its badge stays green. Where the accused construct is a file on a
public default branch, the job **re-reads it from upstream on every run** and
fails loudly if it has gone (entries 6, 11, 13; entry 7, now fixed upstream,
inverts the same mechanism into a regression guard that fires if the *fix* is
reverted). That failure means "a human must re-read this report", not "re-pin
until it's quiet". Unreachable hosts are
treated differently from missing code: if the fetch itself fails the job warns
and continues, because a host being down is not evidence about the bug — and
over this project every git host we depend on has been unreachable at least
once.

**CI philosophy: a workflow is GREEN when the bug REPRODUCES.** Every job
asserts the *buggy* behavior byte-for-byte (with loud, human-readable evidence
in the log) and, where cheap, also runs a control demonstrating the *correct*
behavior (a reference implementation, or the same code with a one-line fix).
A red workflow therefore means either the environment broke or the bug no
longer exists at the pinned version.

Nothing here files a report anywhere; this repository only *demonstrates*.
All sources are fetched fresh in CI from upstream mirrors at pinned
versions/commits (sha256/commit-hash verified). Run any reproducer locally
with `bash bugs/<dir>/run.sh` (dependencies are listed in the matching
workflow file).

## The bugs

| # | Bug | Status | Intended upstream | Local evidence in the bootstrap project |
|---|-----|--------|-------------------|--------------------------------------|
| 1 | [`mes-ldexp-stub`](bugs/01-mes-ldexp-stub/) | [![mes-ldexp-stub](../../actions/workflows/mes-ldexp-stub.yml/badge.svg)](../../actions/workflows/mes-ldexp-stub.yml) | GNU Mes (`bug-mes@gnu.org`) | `data/mescc-bugs/bug17-musl-strtod-miscompile/` (`mes-ldexp-stub.c`) |
| 2 | [`mes-abtod-fraction`](bugs/02-mes-abtod-fraction/) | [![mes-abtod-fraction](../../actions/workflows/mes-abtod-fraction.yml/badge.svg)](../../actions/workflows/mes-abtod-fraction.yml) | GNU Mes (`bug-mes@gnu.org`) | `data/mescc-bugs/bug18-mes-strtod-mantissa/` |
| 3 | [`mes-arm-getdents64`](bugs/03-mes-arm-getdents64/) | [![mes-arm-getdents64](../../actions/workflows/mes-arm-getdents64.yml/badge.svg)](../../actions/workflows/mes-arm-getdents64.yml) | GNU Mes (`bug-mes@gnu.org`) | bug21; `bootstrap-work/arm-commencement/getdents-fix-chain-build.log` |
| 4 | [`tcc-mes-arm-ldouble-zero`](bugs/04-tcc-mes-arm-ldouble-zero/) | [![tcc-mes-arm-ldouble-zero](../../actions/workflows/tcc-mes-arm-ldouble-zero.yml/badge.svg)](../../actions/workflows/tcc-mes-arm-ldouble-zero.yml) | janneke tinycc fork ([gitlab.com/janneke/tinycc](https://gitlab.com/janneke/tinycc)) | `data/mescc-bugs/bug20-tcc-arm-real-miscompile/` (+ `bug15-double-zero-materialization/`) |
| 5 | [`tcc-fp-parse-libc-poison`](bugs/05-tcc-fp-parse-libc-poison/) | [![tcc-fp-parse-libc-poison](../../actions/workflows/tcc-fp-parse-libc-poison.yml/badge.svg)](../../actions/workflows/tcc-fp-parse-libc-poison.yml) | janneke tinycc fork (context for an integer-only FP-literal parser) | `data/mescc-bugs/bug17-musl-strtod-miscompile/` |
| 6 | [`gash-exit-success-gate`](bugs/06-gash-exit-success-gate/) | [![gash-exit-success-gate](../../actions/workflows/gash-exit-success-gate.yml/badge.svg)](../../actions/workflows/gash-exit-success-gate.yml) | Gash (Timothy Sample; `bug-gash@nongnu.org`), possibly also guix-devel | arm-commencement `gash-utils-boot-fixed` packaging (commencement.scm branch) |
| 7 | [`fiwix-nr-buf-hash-lp64`](bugs/07-fiwix-nr-buf-hash-lp64/) | [![fiwix-nr-buf-hash-lp64](../../actions/workflows/fiwix-nr-buf-hash-lp64.yml/badge.svg)](../../actions/workflows/fiwix-nr-buf-hash-lp64.yml) — **FIXED UPSTREAM** | Fiwix (Mikel Izal; [github.com/mikaku/Fiwix](https://github.com/mikaku/Fiwix)) — reported (issue [#113](https://github.com/mikaku/Fiwix/issues/113)) and fixed by PR [#114](https://github.com/mikaku/Fiwix/pull/114), merged `799e42c4` | fiwix-riscv64 port (draft PR #6) |
| 8 | [`tcc-riscv64-ldouble-cross`](bugs/08-tcc-riscv64-ldouble-cross/) | [![tcc-riscv64-ldouble-cross](../../actions/workflows/tcc-riscv64-ldouble-cross.yml/badge.svg)](../../actions/workflows/tcc-riscv64-ldouble-cross.yml) — **ALREADY REPORTED** | [codeberg.org/ekaitz-zarraga/tcc#1](https://codeberg.org/ekaitz-zarraga/tcc/issues/1); fixed upstream in tinycc mob `923fba83` ("general: long double issues") | riscv64 tcc/flex chain (`JasonGross/test-debugging-riscv64-tcc-flex`) |
| 9 | [`mescc-riscv64-uint32-add`](bugs/09-mescc-riscv64-uint32-add/) | [![mescc-riscv64-uint32-add](../../actions/workflows/mescc-riscv64-uint32-add.yml/badge.svg)](../../actions/workflows/mescc-riscv64-uint32-add.yml) | GNU Mes (`bug-mes@gnu.org`) | tinyemu-retarget `scripts/tinyemu-riscv/drivers/qemu-user-ref/mescc-u32-repro/` (branch `tinyemu-riscv-mes-tcc`) |
| 10 | [`tcc-mes-riscv64-fp-literal`](bugs/10-tcc-mes-riscv64-fp-literal/) | [![tcc-mes-riscv64-fp-literal](../../actions/workflows/tcc-mes-riscv64-fp-literal.yml/badge.svg)](../../actions/workflows/tcc-mes-riscv64-fp-literal.yml) | GNU Mes (`bug-mes@gnu.org`); context for the janneke tinycc fork (integer-only FP-literal parser, cf. bug 5) | riscv64 tcc-mes fixpoint forensics (branch `tinyemu-riscv-mes-tcc`, `qemu-user-ref/fixpoint-probes/`) |
| 11 | [`gash-utils-find-expressions`](bugs/11-gash-utils-find-expressions/) | [![gash-utils-find-expressions](../../actions/workflows/gash-utils-find-expressions.yml/badge.svg)](../../actions/workflows/gash-utils-find-expressions.yml) | Gash-Utils (Timothy Sample; `gash-devel@nongnu.org` — gash-utils lives on Savannah cgit, NOT the Codeberg gash repo) | arm-commencement gcc-4.7.4 C++ rung (truncated `libstdc++.a`) |
| 12 | [`bootar-xz-multiblock`](bugs/12-bootar-xz-multiblock/) | [![bootar-xz-multiblock](../../actions/workflows/bootar-xz-multiblock.yml/badge.svg)](../../actions/workflows/bootar-xz-multiblock.yml) | Bootar + r6rs-compression (Timothy Sample, `samplet@ngyro.com`; no issue tracker — cgit); possibly also [weinholt/compression](https://github.com/weinholt/compression) | arm-commencement gcc-10.5.0.tar.xz unpack failure (STATUS.md 2849-2896) |
| 13 | [`live-bootstrap-riscv64-stale-pins`](bugs/13-live-bootstrap-riscv64-stale-pins/) | [![live-bootstrap-riscv64-stale-pins](../../actions/workflows/live-bootstrap-riscv64-stale-pins.yml/badge.svg)](../../actions/workflows/live-bootstrap-riscv64-stale-pins.yml) | [fosslinux/live-bootstrap](https://github.com/fosslinux/live-bootstrap) — GitHub issue | riscv64 tcc-mes chain (branch `tinyemu-riscv-mes-tcc`) |
| 14 | [`mes-dtoab-leading-zeros`](bugs/14-mes-dtoab-leading-zeros/) | [![mes-dtoab-leading-zeros](../../actions/workflows/mes-dtoab-leading-zeros.yml/badge.svg)](../../actions/workflows/mes-dtoab-leading-zeros.yml) | GNU Mes (`bug-mes@gnu.org`) | arm gmp-6.2.1 `mpn/perfsqr.h` blowup (2.4 GB) |
| 15 | [`builder-hex0-riscv64-seed`](bugs/15-builder-hex0-riscv64-seed/) | [![builder-hex0-riscv64-seed](../../actions/workflows/builder-hex0-riscv64-seed.yml/badge.svg)](../../actions/workflows/builder-hex0-riscv64-seed.yml) | **Not a bug** — demonstration for a contribution offer to [builder-hex0](https://github.com/ironmeld/builder-hex0) | riscv64 seed port (`JasonGross/builder-hex0` branch `riscv64-port`) |
| 16 | [`tcc-riscv64-absolute-relocs`](bugs/16-tcc-riscv64-absolute-relocs/) | [![tcc-riscv64-absolute-relocs](../../actions/workflows/tcc-riscv64-absolute-relocs.yml/badge.svg)](../../actions/workflows/tcc-riscv64-absolute-relocs.yml) | upstream **tinycc** — `tinycc-devel@nongnu.org` (repo.or.cz `mob`); the silent-failure half (link `rc=0`, binary prints nothing) is **fork-only** and must not be reported upstream — mob already errors hard | riscv64 tcc link of a GCC-built musl (branch `tinyemu-riscv-mes-tcc`) |
| 17 | [`linux-riscv-plic-unmapped-claim`](bugs/17-linux-riscv-plic-unmapped-claim/) | [![linux-riscv-plic-unmapped-claim](../../actions/workflows/linux-riscv-plic-unmapped-claim.yml/badge.svg)](../../actions/workflows/linux-riscv-plic-unmapped-claim.yml) | Linux — `linux-riscv@lists.infradead.org` (`drivers/irqchip/irq-sifive-plic.c`) | fiwix-riscv64 / tinyemu-retarget Gate P3 (Linux 6.1 freeze after `[vda]`) |
| 18 | [`tinyemu-builtin-clz`](bugs/18-tinyemu-builtin-clz/) | [![tinyemu-builtin-clz](../../actions/workflows/tinyemu-builtin-clz.yml/badge.svg)](../../actions/workflows/tinyemu-builtin-clz.yml) | TinyEMU (Fabrice Bellard; <https://bellard.org/tinyemu/> — no tracker, email the author) | building TinyEMU with a bootstrap-chain tcc (branch `tinyemu-riscv-mes-tcc`) |
| 19 | [`tinyemu-plic-not-enable-gated`](bugs/19-tinyemu-plic-not-enable-gated/) | [![tinyemu-plic-not-enable-gated](../../actions/workflows/tinyemu-plic-not-enable-gated.yml/badge.svg)](../../actions/workflows/tinyemu-plic-not-enable-gated.yml) | TinyEMU (Fabrice Bellard; <https://bellard.org/tinyemu/> — no tracker, email the author) | fiwix-riscv64 / tinyemu-retarget Gate P (the manufactured Linux 6.1 boot hang) |
| 20 | [`tcc-fp-literal-integer-parser`](bugs/20-tcc-fp-literal-integer-parser/) | [![tcc-fp-literal-integer-parser](../../actions/workflows/tcc-fp-literal-integer-parser.yml/badge.svg)](../../actions/workflows/tcc-fp-literal-integer-parser.yml) | janneke tinycc fork — the integer-only FP-literal parser (patch 0013) that cures bug 5's mechanism | arm-pivot milestone-3 tcc (patch 0013; cf. bug 5) |
| 21 | [`tcc-arm-double-arg-caller`](bugs/21-tcc-arm-double-arg-caller/) | [![tcc-arm-double-arg-caller](../../actions/workflows/tcc-arm-double-arg-caller.yml/badge.svg)](../../actions/workflows/tcc-arm-double-arg-caller.yml) | Internal — validates our patch 0014; the defect is a regression in our own patches 4/5, **not** an upstream tcc bug | arm-pivot tinycc patches 0004/0005/0014 |
| 22 | [`builder-hex0-riscv64-unified-seed`](bugs/22-builder-hex0-riscv64-unified-seed/) | [![builder-hex0-riscv64-unified-seed](../../actions/workflows/builder-hex0-riscv64-unified-seed.yml/badge.svg)](../../actions/workflows/builder-hex0-riscv64-unified-seed.yml) | **Not a bug** — the UNIFIED-seed sibling of the row 15 demonstration; contribution offer to [builder-hex0](https://github.com/ironmeld/builder-hex0) | one probing seed for both machines (`JasonGross/builder-hex0` branch `riscv64-probing-seed-capabilities`) |
| 23 | [`mes-abtod-negative-exponent`](bugs/23-mes-abtod-negative-exponent/) | [![mes-abtod-negative-exponent](../../actions/workflows/mes-abtod-negative-exponent.yml/badge.svg)](../../actions/workflows/mes-abtod-negative-exponent.yml) | GNU Mes (`bug-mes@gnu.org`); context for the riscv64 bootstrap chain ([codeberg.org/ekaitz-zarraga/commencement.scm](https://codeberg.org/ekaitz-zarraga/commencement.scm)) -- completes the mes-abtod story of rows 1/2 | riscv64 flex/log10 root cause (branch `flex-tcc-rootcause`, `data/riscv64-flex-log10/`) |
| 24 | [`fiwix-syscall-off-by-one`](bugs/24-fiwix-syscall-off-by-one/) | [![fiwix-syscall-off-by-one](../../actions/workflows/fiwix-syscall-off-by-one.yml/badge.svg)](../../actions/workflows/fiwix-syscall-off-by-one.yml) | Fiwix (Mikel Izal; [github.com/mikaku/Fiwix](https://github.com/mikaku/Fiwix)) — separate from the LP64 count fix (bug 7); report pending | the `num > NR_SYSCALLS` off-by-one deliberately left out of reproducer 7's count fix — a correct-count kernel still admits `num == NR_SYSCALLS` and dispatches one past the syscall table |
| 25 | [`m2libc-armv7l-unlink-arg`](bugs/25-m2libc-armv7l-unlink-arg/) | [![m2libc-armv7l-unlink-arg](../../actions/workflows/m2libc-armv7l-unlink-arg.yml/badge.svg)](../../actions/workflows/m2libc-armv7l-unlink-arg.yml) | M2libc (Jeremiah Orians; [github.com/oriansj/M2libc](https://github.com/oriansj/M2libc)) | native armv7l stage0 ladder (`scripts/s7-gate.sh`, branch `stage0-armv7l`) — a chain-built `rm` cannot delete |
| 26 | [`armv7l-stage0-from-seed`](bugs/26-armv7l-stage0-from-seed/) | [![armv7l-stage0-from-seed](../../actions/workflows/armv7l-stage0-from-seed.yml/badge.svg)](../../actions/workflows/armv7l-stage0-from-seed.yml) | **Not a bug** — demonstration that a native armv7l stage0 ladder works from the seed; upstream [stage0-posix](https://github.com/oriansj/stage0-posix) has no armv7l ladder (GAS references only) | 460-byte armv7l hex0 seed → 20 binaries → `armv7l.answers` |


### 1. `mes-ldexp-stub` — GNU Mes' ldexp is a `return 0;` stub

GNU Mes 0.27.1 ships `lib/stub/ldexp.c` whose entire body is `return 0;`, so
`ldexp(1.0, 10)` yields `0.0` instead of `1024.0`. Anything that scales a
mantissa by a power of two through mes libc — including **tcc's own hex-float
literal parser**, which ends in `d = ldexp(d, exp)` — collapses to zero. The
workflow compiles the unmodified file from the GNU mirror tarball with host
gcc, asserts `ldexp(1.0, 10) == 0.0`, and runs the same driver against libm
(control: `1024.0`).

### 2. `mes-abtod-fraction` — Mes' strtod backend misscales fractions and wraps at 32 bits

`lib/mes/abtod.c` computes `d = i + f / dbase`: the whole fractional digit
string (parsed as one integer `f`) is divided by the base (10) exactly once
instead of by 10^(number of fractional digits), so
`strtod("123456.75") == 123456 + 75/10 == 123463.5`. Separately, the integer
part comes from `abtol`, which accumulates into a 32-bit `int`, so
`"4294967296.0"` (2^32) wraps to `0.0`. Small round values (`2.5`, `1e6`)
happen to come out right, which is why it looks fine at a glance. The
workflow compiles `abtod.c`/`abtol.c`/`isnumber.c` verbatim from the tarball
and asserts both wrong values exactly, with host `strtod` as the control.

### 3. `mes-arm-getdents64` — Mes' ARM syscall table uses the x86 number for getdents64

`include/linux/arm/syscall.h` in mes-0.27.1 defines `SYS_getdents64` as
`0xdc` (220) — the **x86** number. On ARM EABI, 220 is `madvise`;
`getdents64` is 217 (`0xd9`), per the very `arch/arm/tools/syscall.tbl` the
header cites as its authority. Every mes-libc `readdir` on ARM therefore
invokes `madvise` on a directory fd. The workflow (A) extracts the header
value and diffs it against the kernel's own v4.19 arm syscall table, and (B)
builds a static arm binary that force-includes the mes header and shows
`syscall(SYS_getdents64, dirfd, buf, n)` returning no directory entries
(madvise semantics) while `syscall(217, ...)` returns real dirents, under
qemu-user.

### 4. `tcc-mes-arm-ldouble-zero` — the mes tinycc fork's empty VT_LDOUBLE store zeroes every long double constant on ARM

In the janneke tinycc fork (the compiler the mes/tcc bootstrap actually
builds; snapshot `ee75a10c` on branch `mes-0.25.0`), `init_putv` in `tccgen.c`
has, under `#if defined BOOTSTRAP && defined __arm__`, an **empty** block for
`VT_LDOUBLE` — the real store is commented out with "XXX TODO: breaks on
mescc/tcc-mes based build" (guard structure introduced in commit
`50b5eaeda92d75984d56de4a12af8d4aa192a853`). On ARM EABI
`long double == double == 8 bytes`, so `sizeof(long double) == LDOUBLE_SIZE`
routes control into the empty block and the `.data` slot stays zero-filled:
**every long double constant materializes as 0.0** (in the bootstrap this
zeroes e.g. musl `floatscan.c`'s `1000000000.0L`). The sibling `VT_DOUBLE`/
`VT_FLOAT` cases under the same guard store the *converted integer value*
instead of the bit pattern (`2.5 → 2`). The workflow cross-builds the fork's
tcc with its own arm bootstrap defines (`-DBOOTSTRAP=1 -DTCC_TARGET_ARM=1
-DTCC_ARM_EABI=1 -DTCC_ARM_VFP=1 -DHAVE_FLOAT=1`), compiles
`long double big = 1000000000.0L; double frac = 2.5;` under qemu-arm, and
asserts the `.data` bytes are `0000000000000000` / `0200000000000000`, vs the
arm-gcc control `0x41CDCD6500000000` / `0x4004000000000000`. Two valid-C
shims disjoint from the bug are applied to make the BOOTSTRAP configuration
compile under gcc (see `mescc-era-shims.py`).

### 5. `tcc-fp-parse-libc-poison` — tcc parses FP literals through the C library its own binary links

Mainline-lineage tcc (since Bellard, 2001; still current) finishes its
hex-float literal parse with `d = ldexp(d, exp)` and parses decimal literals
via `strtod`/`strtold` — i.e. **the values of the constants a tcc emits depend
on the C library the running tcc binary links**. In a bootstrap the libc is
*downstream* of the compiler, so a broken-FP libc self-propagates: in the
bootstrap's arm chain, the MesCC-built tcc links mes libc (bug 1's
`return 0;` ldexp) → parses every `0x1pN` in musl's `floatscan.c`/`scalbn.c`
as `0.0` while compiling musl → tcc-musl's runtime `strtod` is poisoned → the
next compiler generation mis-parses *its own source constants* (gcc `real.c`'s
`M_LOG10_2` → `cc1` ICEs on startup). No compiler in the cycle has a working
FP libc to break it; an FP-literal parser that builds IEEE-754 bits with pure
integer arithmetic does. The workflow builds tcc 0.9.27 natively with gcc,
compiles `double x = 0x1p3;` twice — once normally (control: `8.0`), once
under an `LD_PRELOAD` shim whose `ldexp` is `return 0;` — and asserts the
emitted constant becomes `0.0`.

### 6. `gash-exit-success-gate` — gash 0.2.0's guile-version gate strands guile 2.0.10–2.0.12, killing autoconf under Guix's armhf bootstrap seed

`gash/compat.scm` (gash 0.2.0; used by gash-utils 0.2.0's commands) defines
`EXIT_SUCCESS`/`EXIT_FAILURE` only under `(if-guile-version-below (2 0 10)
...)`, assuming guile ≥ 2.0.10 binds them natively — but guile only started
binding them in **2.0.13**. Guix's armhf `%bootstrap-guile` static seed is
exactly guile **2.0.11**, so in an armhf full-source bootstrap the gash-utils
`rm`/`expr`/`test`/`grep` all crash with `Unbound variable: EXIT_SUCCESS`.
That is fatal at the first autoconf'd package: `config.status` runs `rm -f`
load-bearingly while generating every Makefile — so this plausibly breaks
Guix's armhf full-source bootstrap generally, not just this project's ladder.
The workflow builds guile 2.0.11 from source (cached), shows
`(defined? 'EXIT_SUCCESS) => #f`, runs gash-utils' `rm -f` with stock gash
(asserts the crash), and re-runs it with the gate widened one line to
`(2 2 0)` (control: works, file deleted).

### 7. `fiwix-nr-buf-hash-lp64` — Fiwix 1.5.0 buffer hash: sized in `unsigned int` units, indexed as a pointer array — 2× out of bounds on LP64 (FIXED UPSTREAM)

`fs/buffer.c` defines `NR_BUF_HASH` as `buffer_hash_table_size /
sizeof(unsigned int)` and `mm/memory.c` also *sizes* the table region in
`sizeof(unsigned int)` units — but `buffer_hash_table` is a
`struct buffer **` (an array of pointers). On i386 (ILP32, Fiwix's home
target) pointer == unsigned int == 4 bytes and everything lines up; on any
LP64 port the hash index range is **twice** the number of pointer slots that
fit in the allocation, so the upper half of the hash space writes out of
bounds. The workflow lifts the exact expressions from the pinned v1.5.0
tarball into a user-space harness and shows the LP64 overflow arithmetically
and as an AddressSanitizer heap-buffer-overflow on the exact hash-insert
write, with a `-m32` control staying in bounds.

Reported to Fiwix from this project as issue
[#113](https://github.com/mikaku/Fiwix/issues/113) and fixed by PR
[#114](https://github.com/mikaku/Fiwix/pull/114)
("pointer-tables-by-pointer-size"), merged by mikaku on 2026-07-27 as
`799e42c4`; both sites now size by `sizeof(struct buffer *)`. The reproducer
is retained as a historical record and as a **regression guard** — its live
re-check now asserts the pointer-sized fix is still present on `master` and
goes red only if it is ever reverted.

### 8. `tcc-riscv64-ldouble-cross` — cross tcc materializes riscv64 long doubles as the host's x87 image (ALREADY REPORTED upstream)

A cross tcc targeting riscv64 (`long double` == IEEE binary128, 16 bytes)
built on x86_64 (`long double` == x87 80-bit) materialized long double
constants by copying the *host's* x87 image into the target slot: pre-fix,
`long double x = 1000000000.0L;` emits LE
`0000000000286bee1c40000000000000` (x87 mantissa `0xEE6B2800…` + exponent
`0x401C`, zero-padded) instead of the correct binary128
`000000000000000000000050d6dc1c40`. Reported as
[ekaitz-zarraga/tcc#1](https://codeberg.org/ekaitz-zarraga/tcc/issues/1) (the
chain-vintage riscv64 fork) and fixed upstream in tinycc mob commit
`923fba83` ("general: long double issues") — the workflow builds the mob
snapshot immediately before the fix (bug) and the fix commit itself
(control), plus a `riscv64-linux-gnu-gcc` oracle, and is kept only as a
demonstration; **do not re-report**. It is the riscv64 sibling of bugs 4/5's
init_putv/FP-constant family.

### 9. `mescc-riscv64-uint32-add` — MesCC's riscv64 backend does unsigned 32-bit arithmetic in 64 bits, with no mod-2^32 truncation

For `unsigned imm = (unsigned) -16;` (= `0xfffffff0`), C requires
`(imm + (1 << 11)) >> 12` to wrap mod 2^32: `0x7f0 >> 12 == 0`. MesCC
(mes-0.27.1, riscv64) performs the add in a full 64-bit register and feeds
the untruncated `0x1000007f0` straight into the shift, yielding `0x100000`.
A semantically no-op `(unsigned)` cast on the sum makes MesCC emit the
missing `and 0xffffffff` re-mask and restores correctness. The workflow runs
the **unmodified MesCC from the tarball on host Guile**, shows the emitted
`.s` discriminator (no re-mask between the `add` and the `sra` in the uncast
function; re-mask present in the cast one), then MesCC-compiles mes' own
riscv64 crt1 + minimal libc TUs and links two static riscv64 probes with
stage0's own `M1`/`hex2`/`blood-elf` (mescc-tools 1.7.0, built from source):
under `qemu-riscv64` the uncast probe exits 42 (miscompiled), the cast probe
0; host gcc and `riscv64-linux-gnu-gcc` controls both yield 0. In-chain
consequence: tcc 0.9.26-1147 (the mes-lineage riscv64 tcc) guards 12-bit
immediates with `assert(!((imm + (1 << 11)) >> 12))` — exactly the uncast
shape — so the MesCC-built tcc-mes false-positives on **every negative
immediate** and dies on the first function epilogue (`addi sp,sp,-16`) it
generates; tcc rev 1157 dodges it with an explicit `(uint32_t)` cast.

### 10. `tcc-mes-riscv64-fp-literal` — the riscv64 tcc-mes lineage parses FP literals through the broken mes FP stack (and MesCC has none at all)

The riscv64 sibling of bugs 4/5, exhibited on the mes lineage's own victim
constant. tcc's `parse_number` ends in `strtod`/`strtold` from the libc the
running tcc links (bug 5); in the bootstrap that is mes libc, whose
`strtod → abtod` computes `d = i + f / dbase` (bug 2). The cleanest victim
is mes libc's **own** `ceil()` (`lib/math/ceil.c`: `long i = number +
0.9999;`): mes strtod parses `"0.9999"` as `0 + 9999/10` = **exactly 999.9**
(`0x408F3F3333333333`), bit-identical to its parse of `"999.9"` — two
different source constants collapse to the same double — instead of
`0x3FEFFF2E48E8A71E`. In the riscv64 fixpoint forensics
this is visible in-chain: the **entire binary delta** between the MesCC-built
tcc-mes and its self-rebuilt successor is that one 8-byte `ceil()` constant
(the MesCC-built generation emits garbage bits for it; the tcc-rebuilt one
emits exactly 999.9). The workflow demonstrates the class at component level
(like bugs 1/2): it compiles the verbatim mes strtod stack with host gcc and
asserts both parses bit-for-bit against the host-libc control, quotes the
pinned janneke-fork `tccpp.c` parse path, and adds the MesCC leg (unmodified
MesCC on host Guile, riscv64 target): a function-local `double d = 0.9999;`
is emitted as the *integer* immediate `!0.9999 addi`, and a file-scope one is
a hard `init->data: not supported` error — no stage upstream of tcc-musl can
even materialize the IEEE constant. (The full in-chain gen2/gen3 exhibit
needs the whole mes/tcc riscv64 chain and is not run in CI.)

### 11. `gash-utils-find-expressions` — gash-utils' `find` supports no expression predicates, and the empty output silently guts libtool archives

`gash/commands/find.scm` (gash-utils 0.2.0, and unchanged on master) declares
a getopt-long `option-spec` of exactly `((help) (version))`, so `-name` is
parsed as a **cluster of short options** (`-n -a -m -e`) and rejected with
`find: no such option: -n`; `-print` fails on `-p`. Every POSIX find
expression is rejected the same way, while bare `find DIR` works — which is
why a bootstrap runs a long way before anything looks wrong. The damage is
in the failure *mode*: find writes the diagnostic to stderr, exits 1, and
writes **nothing to stdout** — and the universal caller idiom is command
substitution, which reads stdout and ignores the status. GNU libtool's
`func_extract_archives` (gcc-4.7.4 `ltmain.sh` line 2935) does exactly
that: ``find $my_xdir -name \*.$objext -print -o -name \*.lo -print``. The
gather comes back empty, the following `ar rc` **succeeds**, and the
convenience archive is silently empty. The workflow runs the minimal case,
shows `-print` failing identically, shows bare `find` working, then runs the
verbatim libtool gather into a real `ar rc`: 0 members / 8 bytes with
gash-utils find versus 2 members / 128 bytes with GNU find as control. In
the arm bootstrap ladder the same mechanism produced a `libstdc++.a`
with 8 members (~67 KB) instead of 124, and nothing failed until the first
C++ link much later. Same silent-degradation class as bug 6.

### 12. `bootar-xz-multiblock` — Bootar's XZ decoder cannot read a stream with more than one block

Bootar is "a thin wrapper around the 'compression' R6RS library", and that
library — [git.ngyro.com/r6rs-compression](https://git.ngyro.com/r6rs-compression),
pinned by bootar v1b's `make-ses.scm` at `a2d01f24` — crashes on any XZ
stream containing **more than one block**. In `xz.scm`, `next-chunk` does
`(set! lzma2-state (lzma2-decode-chunk ...))`; `lzma2-decode-chunk` signals
end-of-block by **returning the eof-object**, and the end-of-block handler
clears `block-start` but never resets `lzma2-state`. When another block
follows, that stale eof-object is passed back in as state — and because the
eof-object is *truthy* in Scheme, `(or state (empty-state))` keeps it rather
than making a fresh state vector, so `(vector-ref state 0)` fails with
`Wrong type argument (expecting vector): #<eof>`. A single-block stream never
re-enters, which is why this went unnoticed. **Size is a red herring**: it
was found on a 77.8 MB `gcc-10.5.0.tar.xz` that took ~54 minutes to fail
(under an interpreted guile-bootstrap-2.0), but large inputs merely *tend* to
be multi-block — the workflow reproduces it in seconds on a 4 MB payload.
The job compresses one payload two ways (62 blocks vs 1), shows the
single-block decode is byte-identical (control), shows the multi-block decode
crashing at the same source line the original failure reported
(`lzma2.scm:51`), then applies a two-line per-block state reset and shows the
multi-block stream decoding byte-identically with no single-block regression.
Resetting `lzma2-state` alone is *not* sufficient — the next block then fails
its integrity check because the per-block checksum state is not reinitialized
either, which is why we say the multi-block path was never exercised at all.

### 13. `live-bootstrap-riscv64-stale-pins` — the pinned riscv64 tcc cannot build through, and the checksum set mixes eras

`steps/tcc-0.9.26/sources` on live-bootstrap master pins
**tcc-0.9.26-1147-gee75a10c**, and `tcc-0.9.26.riscv64.checksums` has not been
touched since `865b9aea` ("Update mes to 0.27.1", 2025-09-19) — a commit that
bumped only the `tcc-mes` hash. The problem is that the pinned source cannot
be built by the MesCC that live-bootstrap uses to build it. tcc's `EI()`/`ES()`
guard their 12-bit immediates with `assert(! ((imm + (1 << 11)) >> 12));`
(riscv64-gen.c:124/131). That is correct C — `imm` is `uint32_t`, so the add
wraps mod 2^32 — but MesCC's riscv64 backend evaluates it in 64 bits without
re-truncating (bug 9 here), so the assertion fires for **every negative
immediate**, starting with the `addi sp,sp,-16` that opens every function
epilogue tcc emits. Revision 1157 dodges it with an explicit `(uint32_t)`
cast. The workflow checks what master pins *today* (failing loudly if upstream
moves), lifts each revision's guard **verbatim** out of the pinned tarballs,
and evaluates it for that first-epilogue immediate: the 1147 guard fires under
MesCC (exit 42), 1157's does not, and host gcc accepts both — so the defect is
MesCC's while the *consequence* is that this pin cannot build through. What
the job deliberately does **not** do (too slow for CI, and stated in the log)
is rebuild tcc to show that the 1157 lineage reproduces the pinned `crt1.o`
`cc417e9d…` byte-exactly — the fact that makes the set "mixed-era" rather than
merely stale; that remains local evidence.

### 14. `mes-dtoab-leading-zeros` — mes libc's float→decimal drops the fraction's leading zeros (the *output* half of the FP problem)

`lib/mes/dtoab.c` is what mes libc's `printf("%f")` calls
(`vfprintf.c` case `'f'` is literally `char *s = dtoab (d, 10, 1);`). It
computes the fraction as `long f = (d - (double) i) * (double) 100000000;`
and then prints `f` **as an integer**, with no zero padding — so every
*leading* zero of the fraction is lost and the decimal point moves one place
per dropped zero. `1.0625` renders as `"1.625"` (10× off), `3.0009` as
`"3.9"` (**1000× off**), and `0.005`, `0.05` and `0.5` **all render as
`"0.5"`** — output that cannot be read back as the value it had. Trailing
zeros are then stripped, so `2.00000001` renders as `"2"`, losing the
fraction entirely. This is the exact mirror of bug 2 (`abtod`, the *input*
side): both lose the position of the decimal point. It matters because
build-time **generators** print floats: in the arm bootstrap ladder
the same class of defect (there through the boot musl rather than mes) made
GMP's `gen-psqr` write a **2.4 GB** `mpn/perfsqr.h` whose header comment read
`0+00%` instead of `82.81%`, failing the build with "perfsqr.h is too large".
Bugs 5 and 10 are the input half of the same disease; a bootstrap has neither
half in working order.

### 15. `builder-hex0-riscv64-seed` — DEMONSTRATION: one hex0 seed, two riscv64 machines, byte-identical chain output

**This entry is not a bug.** It is the evidence attached to a contribution
offer, and it inverts the repo's convention: **green means the demonstration
succeeded.** builder-hex0 is an auditable hex0 machine-code seed; this is a
riscv64 port of it, targeted at two different machines. The workflow builds
both checked-in seeds from their hex0, builds one srcfs disk image carrying
the real (pinned, unmodified) stage0-posix riscv64 sources, gives each machine
its own identical copy of that image, and runs the chain to M2-Planet twice:
once on **QEMU virt** with the baseline seed, once on **TinyEMU** with the
retargeted seed. It then asserts the two M2-Planet artifacts are
**byte-identical**. That equality is the whole claim — retargeting changed how
the builder performs console and disk I/O and nothing about what the chain
computes, which is the property that makes a second machine target reviewable.
Each machine needs its own copy of the image because the chain's last step
writes M2 over `/dev/hda` from sector 0, destroying the control block it
booted from. TinyEMU is built from Bellard's last release (pinned); `-rw` is
required or the builder's flushed output goes to a COW overlay and never
reaches the file. The stage0-posix inputs are fetched as four pinned
submodules straight from GitHub rather than through the superproject, because
its `mescc-tools` submodule lives on `git.savannah.nongnu.org`, which the
riscv64 chain does not need and which was unreachable while this was written.

### 16. `tcc-riscv64-absolute-relocs` — tinycc's riscv64 linker implements the PC-relative HI20/LO12 relocations but not their absolute siblings

One musl 1.2.5, built here from pinned source by riscv64 GCC, linked four ways
by a single four-line `printf`-only trigger: unpatched tinycc `mob` fails hard
(`Unknown relocation type for got: 26/27/28`, no binary at all); the same tree
plus a 20-line patch links clean and runs; the chain-vintage fork
`0.9.26-1157` unpatched links `rc=0` with only `FIXME: handle reloc type
1a/1b/1c` notes and its binary prints nothing; and that fork plus the patch
links clean and runs. A `-fPIC` leg bounds the claim to exactly these three
relocations, and the job re-reads live `mob` on every run and fails loudly if
`riscv64-link.c` grows a `case R_RISCV_HI20:`. Full writeup, all legs, and the
load-bearing script details are in
[`bugs/16-tcc-riscv64-absolute-relocs/`](bugs/16-tcc-riscv64-absolute-relocs/).

**Caveat that must not travel wrong:** only the hard-error half is for
upstream (`tinycc-devel@nongnu.org`, repo.or.cz `mob`). The silent-failure
half — link `rc=0`, binary prints nothing — is **fork-only** and must not be
reported upstream; mob already turns the unhandled relocation into a hard
error.

### 17. `linux-riscv-plic-unmapped-claim` — a claimed-but-unmapped PLIC source is never completed, and is masked for the rest of the boot

`drivers/irqchip/irq-sifive-plic.c`'s `plic_handle_irq()` claims an interrupt
by reading the claim register, and on the `generic_handle_domain_irq()` error
branch — the hwirq has no Linux irqdomain mapping — it warns and moves on
**without writing the ID back**. The PLIC's per-source gateway will not forward
that source again until the outstanding claim is completed, so hitting that
branch once masks the source for the rest of the boot. In the worst case (a
boot-critical device on that line) the boot hangs, which is how we met it.

The reachable-on-conformant-hardware path is a source numbered **above** the
device tree's `riscv,ndev`: `__plic_init()` clears the per-context enable bits
only for `hwirq 1..ndev` and sizes the irqdomain to the same range, so a source
above `ndev` that a prior stage left enabled and asserted survives Linux's init,
can never be mapped, and is claimed on the first external interrupt Linux takes.
(For sources *within* `1..ndev` Linux is safe: it clears their enables at init
and maps a source before enabling it.)

The workflow runs entirely on **stock `qemu-system-riscv64 -M virt`**, whose
PLIC is spec-compliant and enable-gated (`hw/intc/sifive_plic.c` claims only
`pending & ~claimed & enable`, above the context threshold) — nothing here
leans on an emulator shortcut. It builds a pinned Linux 6.12.1, dumps qemu's own
device tree and lowers `riscv,ndev` to 9 so that PLIC source 10 (the virt
machine's UART0) is out of range, and boots through a tiny pre-kernel S-mode
stub standing in for a prior boot stage. Four configurations × two kernels,
everything else identical:

| leg | stock kernel | one-line fix |
|---|---|---|
| poison, **above** `ndev=9` — source 10 given priority, enabled for the S-context, asserted | **1** warning | **10** warnings |
| poison, **in range** — the identical stub against qemu's own unmodified `riscv,ndev` | 0 | 0 |
| control, above `ndev` — source 10 prioritised + enabled, *not* asserted | 0 | 0 |
| none, above `ndev` — stub touches nothing | 0 | 0 |

(counting `can't find mapping for hwirq 10`; all eight boots reach a userspace
marker and power off.)

Row 1 vs **row 2** answers the maintainer's first question — *why didn't
`__plic_init()` clear it?* — by measurement rather than by reading the source:
the identical stub against qemu's own device tree is completely neutralised,
because the clear-enables loop covers `hwirq 1..ndev`. Only above `ndev` does
the prior stage's enable survive into Linux.

The **1-vs-many** cell in row 1 is the bug itself. The poison source keeps
re-asserting — the console UART's THRE line goes high again after every
character OpenSBI prints, and the fixed column is delivered it ten times off
that same line — yet the stock kernel is delivered it exactly **once**, because
the leaked claim latches the gateway shut. Rows 3 and 4 fix the interpretation:
enabled but never asserted claims nothing, and asserted without the prior
stage's enable is not deliverable at all.

Every leg asserts Linux's own `mapped N interrupts` line, i.e. that it really
sized its irqdomain from the device tree that leg intended — without which a
failed DTB edit would leave source 10 *in* range, still produce the warning
(an in-range source with no driver is unmapped too), and quietly unsupport the
report's central claim. The job also re-reads `plic_handle_irq()` from
`torvalds/linux` master on every run and fails loudly if a completion appears
there, so the report cannot rot into a false claim about mainline.

*Ablated 2026-07-26* (`ABLATE=1 bash bugs/17-linux-riscv-plic-unmapped-claim/run.sh`,
run by hand, not in CI): applying the fix before the "stock" build points the bug
legs at a kernel where the defect is absent, and the run dies at the named
assertion `expected EXACTLY 1 unmapped-claim warning on the stock kernel, got 10`.

Honest limits, stated in the job's own output: this variant demonstrates
*reachability and recovery*, not a hang — an above-`ndev` source has no Linux
driver waiting on it. And because the poison source here is the console UART,
the fixed kernel's own warning output re-asserts the line, which is also a fair
caution about the fix itself: completing a still-asserted, permanently-unmapped
level source means re-delivery until something quiesces it (here bounded by the
printk rate limiter, and the boot finishes normally).

### 18. `tinyemu-builtin-clz` — TinyEMU's softfp.c needs GCC's clz builtins, so a non-GCC compiler cannot build it

`softfp.c`'s `clz32()`/`clz64()` (and `clz128()` under `HAVE_INT128`) call
`__builtin_clz()`/`__builtin_clzll()` unconditionally — no `#if`, no
`__has_builtin`, no fallback. A compiler that does not implement those GCC
extensions compiles the file anyway (they look like ordinary implicit function
declarations) and emits references to functions that exist nowhere, so the
failure surfaces only at link time as ``undefined symbol `__builtin_clz'`` —
a diagnostic that does not say "your compiler lacks a GCC extension".

This is a portability gap rather than a correctness bug, and it matters for a
specific reason: TinyEMU's appeal in a bootstrap is trust-minimality (~12k
readable SLOC against qemu-i386's ~424k), but that argument is about source
size, not provenance, for as long as the binary is produced by an unaudited
host GCC. Building TinyEMU with a bootstrap-chain compiler closes the gap, and
in this project's experiment this single construct was the only compiler-scope
obstacle — with a shim supplied externally, the minimal riscv64 configuration
built cleanly with a chain `tcc` and booted a full RISC-V guest.

The workflow takes the verbatim pinned TinyEMU release and mainline tcc 0.9.27,
shows tcc's complete builtin table (`tcctok.h`) has no clz family, and then:
tcc compiles `softfp.c` into an object carrying `U __builtin_clz` /
`U __builtin_clzll` and the link fails; **gcc** compiles and links the same file
and computes correct IEEE-754 conversions (control); with a 6-line guarded
fallback tcc's object has no undefined builtins, links, and produces results
**byte-identical** to the gcc control on all 10 conversions; and gcc's generated
`.text` for `softfp.c` is **byte-identical before and after the patch**, so the
fallback costs GCC and Clang builds nothing. Because TinyEMU ships as a tarball
from one host with no VCS and no tracker, the staleness guard is "is the release
at that URL still the one we pinned, and does its `softfp.c` still carry the
construct?".

*Ablated 2026-07-26* (`ABLATE=1 bash bugs/18-tinyemu-builtin-clz/run.sh`, run by
hand, not in CI): pointing the bug leg at the patched source makes the run die at
the named assertion `expected tcc to treat __builtin_clz as an implicit
declaration`.

### 19. `tinyemu-plic-not-enable-gated` — TinyEMU's RISC-V PLIC has no per-context enable, per-source priority, or per-context threshold registers

On the verbatim pinned TinyEMU release, an M-mode probe writes a known pattern
to the PLIC `priority[5]`, `enable[ctx0]` and `threshold[ctx0]` registers and
reads back 0 from every one — those gating registers do not exist; temu's
per-source state is two words (pending, served) and its claim is
`ctz32(pending & ~served)` with no enable term. The control runs the identical
probe on stock `qemu-system-riscv64 -M virt`, whose spec-compliant SiFive PLIC
reads back exactly what was written — which is also what proves the writes are
a real stimulus and not a vacuous read of a register that was 0 anyway. The
`ABLATE=1` run points the "registers absent" assertion at qemu's output and
must go red on the enable register (ablation recorded in the `run.sh` header,
2026-07-26). Harness in
[`bugs/19-tinyemu-plic-not-enable-gated/`](bugs/19-tinyemu-plic-not-enable-gated/).

TinyEMU has no tracker; the intended route is email to Fabrice Bellard. The
report this backs is the manufactured Linux 6.1 boot hang (the bootstrap's
fiwix-riscv64 / tinyemu-retarget Gate P).

### 20. `tcc-fp-literal-integer-parser` — the patch-verifying leg for tinycc patch 0013 (the integer-only IEEE-754 literal parser)

Bug 5 shows the mechanism — the janneke fork parses every FP literal through
the C library its own binary links, so a broken-FP libc poisons the constants
it emits. This entry shows patch 0013 curing it. `run.sh` builds the fork as a
host→arm cross tcc and compiles a float/double battery four ways, {without
0013, with 0013} × {clean host FP, an interposed broken `ldexp`/`strtod`}: the
unpatched parser goes all-zero under poison, the patched one stays byte-exact,
and both are exact with a healthy libc. Because a cross tcc inherits the host's
80-bit `long double`, the companion `run-arm.sh` builds the fork **arm-native**
(`long double == double == 8 bytes`, statically asserted) and runs the same
2×2 over a battery that **includes `L` literals** — the poisoned column there
is what shows 0013 delivers exact long doubles when the libc is broken. Both
legs carry a `buggy+poison` all-zero control and an on-demand ablation
(recorded in each header). Harness in
[`bugs/20-tcc-fp-literal-integer-parser/`](bugs/20-tcc-fp-literal-integer-parser/);
the mechanism it verifies against is [bug 5](bugs/05-tcc-fp-parse-libc-poison/)
above. Intended upstream: the janneke tinycc fork (the parser 0013 replaces).

### 21. `tcc-arm-double-arg-caller` — the patch-verifying leg for tinycc patch 0014 (the softfp double-argument caller regression)

Builds the fork's arm cross tcc three ways — stock (pristine upstream, the
control), buggy (our patches 0004+0005), and fixed (0004+0005+0014). At byte
level, stock emits `pop {r0,r1,r2,r3}` for the softfp double calls, buggy drops
it, and fixed both restores it and produces an object byte-identical to
stock's. At runtime, a gcc-built softfp receiver (an independent ABI reference)
dumps the doubles it actually received: with the buggy compiler they arrive
wrong, with fixed and with an arm-gcc-built caller they arrive exact. Harness
in [`bugs/21-tcc-arm-double-arg-caller/`](bugs/21-tcc-arm-double-arg-caller/).

**Caveat that must not travel wrong:** this is **not** an upstream tcc bug. The
defect is a regression in our own patches 0004/0005; the entry exists to
validate our patch 0014. Stock upstream carries the register-restore bitmap
through untouched and is correct, so there is nothing to report here — this is
internal validation only.

### 22. `builder-hex0-riscv64-unified-seed` — DEMONSTRATION: ONE hex0 seed, two riscv64 machines, byte-identical chain output

**This entry is not a bug** and, like row 15, it inverts the repo's convention:
**green means the demonstration succeeded.** It is the *unified-seed* sibling of
row 15. Row 15 shows two independently-targeted seeds — one built for QEMU
`virt`, one for TinyEMU — agree; this shows a **single** seed that detects its
machine at runtime and agrees with itself across both. The workflow asserts four
things. **Round-trip:** the seed's `.S` regenerates the checked-in `.hex0` (the
fork's own oracle), so the hand-auditable hex is provably the machine code that
boots. **One seed, both machines, 128 MiB:** the same binary boots on QEMU
`virt` and on TinyEMU, each at 128 MiB — the seed carries an additive capability
layer (an M-mode kexec service) that imposes nothing on the bootstrap path, so
the stage0 chain still runs on a small machine. **Probe discriminated:** the
same binary prints the qemu-virt banner on QEMU and the TinyEMU banner on
TinyEMU, each on that machine's own console. **Byte-identical output:** the real
pinned stage0-posix chain runs to M2-Planet on both, both outputs are non-empty,
and the two are byte-identical to each other. Equality is the whole claim — no
fixed hash is cited, so it reproduces for anyone cloning this. A recorded
red-for-the-right-reason (`ABLATE=1`/`ABLATE=2`, run once at authoring time, not
on every CI invocation) confirms the discrimination and equality assertions each
go red on their own named failure rather than on a build error. Harness in
[`bugs/22-builder-hex0-riscv64-unified-seed/`](bugs/22-builder-hex0-riscv64-unified-seed/).

### 23. `mes-abtod-negative-exponent` — Mes' abtod applies negative exponents one decade short (the riscv64 flex/log10 mechanism)

`lib/mes/abtod.c` applies the decimal exponent with
`if (e < 0) while (e++) d = d / dbase;` followed by `while (e--) d = d * dbase;`.
The post-increment fires on the loop-exiting test too, so the divide loop ends
with `e == 1` and the multiply loop then scales back up once: a negative
exponent `-n` is applied as 10^(1-n), and `e-01` is a no-op — `"5e-1"` parses
as `5.0`. Composed with the two defects of reproducer #2 (whole fraction
divided by 10 once; 32-bit wrap), musl-1.1.24's own `log10.c` constants —
grepped out of the pinned musl tarball before the run, so the stimulus is
provably real — parse to exact garbage: `log10_2hi` (`3.01029995663611771306e-01`)
becomes `137191264.8` (bits `41a05abec199999a`). Any compiler whose FP-literal
parsing defers to the runtime strtod of the libc it links (TinyCC's
`parse_number` does exactly that) bakes these values into everything it
compiles. In the riscv64 full-source bootstrap this is what broke flex 2.5.39
on GCC's `gengtype-lex.l`: flex sizes a per-start-condition allocation with
`(int)(1 + log10(i))`, and the workflow asserts that arithmetic lands on
exactly `137191265` — the failing ~137 MB allocation behind
`flex: fatal internal error, allocation of macro definition failed`.
The workflow compiles `abtod.c`/`abtol.c`/`isnumber.c` verbatim from the
mes-0.27.1 tarball with host gcc, asserts every buggy value bit-for-bit
against host `strtod` controls, and runs an ablation leg on every CI run:
with the mes parser swapped for the correct one, exactly the six buggy-value
predictions must fail — proving the harness notices the bug's absence.
(The chain-side consequence — the identical bit patterns in the riscv64
chain's compiled `musl-boot0` `log10.o` and its flex failing — is internal
evidence in the bootstrap project, branch `flex-tcc-rootcause`; this
workflow demonstrates the mes defect and the arithmetic bridge from public
sources only.)

### 25. `m2libc-armv7l-unlink-arg` — M2libc's armv7l `unlink()` passes the kernel `&filename` instead of `filename`

In `M2libc/armv7l/linux/unistd.c` every syscall wrapper fetches a stack-passed
argument with a two-line idiom: `!4 R0 SUB R12 ARITH_ALWAYS` puts the *address*
of the argument slot in `R0`, then `!0 R0 LOAD32 R0 MEMORY` loads the *value*
from it. `unlink()` has the first line but not the second, so it hands the
kernel the address of the pointer rather than the pointer. The kernel reads a
bogus path, `unlink` returns nonzero (ENOENT), and the file is never removed —
in the native armv7l stage0 ladder a chain-built `rm` silently cannot delete.
The defect is armv7l-only: the char\* siblings `access()`/`chdir()`/`symlink()`
in the same file all carry the `LOAD32`, and every other backend dereferences
too (x86/amd64/riscv32/riscv64 load the value; aarch64 receives its argument in
a register and needs no load).

The workflow builds a real C program through the actual `M2-Planet → M1 → hex2`
chain (all three gcc-built from pinned upstream sources) against pinned M2libc.
The program calls `access()` and `unlink()` on the same path. Under
`qemu-arm`, `access()` finds the file (its pointer is dereferenced correctly)
but `unlink()` fails and the file **survives** (exit 2). The **identical
program built for amd64** and run natively **removes** the file (exit 0) — the
control that isolates the defect to the missing armv7l dereference rather than
the program. Finally the fix leg inserts the single missing
`!0 R0 LOAD32 R0 MEMORY` line into `unlink()` — and nothing else, asserted by a
one-site count — rebuilds for armv7l, and the file is then removed. PART A
re-reads the live M2libc default branch on every run and fails loudly if
`unlink()` grows the dereference (or a sibling loses it), so a silent upstream
fix surfaces as a red rather than a stale green.

### 26. `armv7l-stage0-from-seed` — DEMONSTRATION: a 460-byte armv7l hex0 seed builds the whole stage0 ladder

**This entry is not a bug** and, like rows 15 and 22, it inverts the repo's
convention: **green means the demonstration succeeded.** Upstream
[stage0-posix](https://github.com/oriansj/stage0-posix) has no armv7l ladder —
the armv7l port ships GAS reference sources only, with no hex0 seed, no kaem
scripts and no stage0-cc support layer — so an armv7l stage0 has never been
runnable from a seed. This job is the evidence that one now is.

The workflow asserts, in order. **Seed reconstructed from text:** rendering the
checked-in commented listing yields exactly the 460-byte seed at a pinned
sha256, so the bytes that execute are provably the bytes a human can audit —
nothing opaque is shipped (the whole checked-in payload is text: listings, M1
and hex2 sources, and kaem scripts). **Ladder edge:** that seed run on its own
source reproduces itself byte-identically, and builds the 1,162-byte kaem seed.
**From-seed enforced, not asserted:** the tree is scanned and must hold exactly
those two ELF binaries; a third anywhere fails the job. **The ladder runs:**
`kaem.armv7l` drives the seed, mini and full kaem stages plus mescc-tools-extra
entirely under binaries it built itself, with all upstream sources fetched
fresh at commit-verified pins. **Answers reproduce:** all 20 built binaries
match the checked-in `armv7l.answers`, checked twice — once by the ladder's own
chain-built `sha256sum` and once by the runner's GNU coreutils. Those two share
no code, and that is the *only* independence claim the job makes; it is
labelled as such in the job output. Four intermediate binaries are additionally
checked against sha256 values fixed on a different machine, so the build is
shown to be bit-reproducible across hosts.

Two **red legs run on every invocation** rather than only at authoring time:
flipping one byte of a built binary must make the answers check name that
binary `FAILED`, and planting a third ELF must make the from-seed scan refuse
the tree. Each fails with its own named assertion, so a vacuous harness would
be caught. (A third, costlier red — perturbing one `--base-address` flag so
that exactly `armv7l/bin/M1` fails and nothing else does — was verified at
authoring time and is not re-run, as it doubles the build.)

**Scope, stated so nothing is inferred:** this job runs **one** lineage, so it
demonstrates from-seed reproducibility, **not** cross-lineage diversity; and it
takes no position on whether any of this should be adopted upstream. Harness in
[`bugs/26-armv7l-stage0-from-seed/`](bugs/26-armv7l-stage0-from-seed/).

## Pinned sources

| Source | Pin |
|--------|-----|
| GNU Mes | `mes-0.27.1.tar.gz` from ftp.gnu.org, sha256 `183a40ea…f25d` |
| Linux | `linux-6.12.1.tar.xz` from cdn.kernel.org, sha256 `0193b1d8…c619` |
| janneke tinycc fork | gitlab.com/janneke/tinycc @ `ee75a10cd71bebf23cb23598a49ee3c160ef0fe8` (branch `mes-0.25.0`) |
| mainline tinycc | repo.or.cz/tinycc.git @ `release_0_9_27` = `d348a9a51d32cece842b7885d27a411436d7887b` (fallback when repo.or.cz is down: the official github.com/TinyCC/tinycc mirror; the commit-hash pin is the integrity check either way) |
| GNU Guile | `guile-2.0.11.tar.xz` from ftp.gnu.org, sha256 `aed0a4a6…03e2` |
| Gash | `gash-0.2.0.tar.gz` + `gash-utils-0.2.0.tar.gz` from download.savannah.gnu.org, sha256 `ee415804…7a08e` / `e6aae5a6…59d4a3` |
| Fiwix | github.com/mikaku/Fiwix tag `v1.5.0` archive, sha256 `e1d5ce53…c4fe0` |
| Linux (reference syscall table) | raw.githubusercontent.com torvalds/linux `v4.19` `arch/arm/tools/syscall.tbl` (the file mes' header cites) |
| NYACC | `nyacc-1.00.2.tar.gz` from download.savannah.nongnu.org, sha256 `f36e4fb7…b318` |
| mescc-tools | `mescc-tools-1.7.0.tar.gz` from download.savannah.nongnu.org, sha256 `b682f7bf…575c` |
| builder-hex0 (riscv64 port) | github.com/JasonGross/builder-hex0 @ `dfc103e6…f205bb` (branch `riscv64-port`) |
| builder-hex0 (unified probing seed) | github.com/JasonGross/builder-hex0 @ `9589b9be…804aff` (branch `riscv64-probing-seed-capabilities`) |
| stage0-posix (riscv64 chain) | oriansj submodules, pinned: `stage0-posix-riscv64` `4688bc66…f72e`, `M2libc` `95e90061…160e`, `M2-Planet` `cadf52af…209a`, `bootstrap-seeds` `cedec6b8…80ed` |
| TinyEMU | `tinyemu-2019-12-21.tar.gz` from bellard.org, sha256 `be8351f2…5555` |
| tcc (mes lineage) | lilypond.org/janneke/tcc `tcc-0.9.26-1147-gee75a10c.tar.gz` sha256 `6b8cbd0a…e819f` (= live-bootstrap's own pin) and `tcc-0.9.26-1157-gdd46e018.tar.gz` sha256 `3748c0aa…2232e` |
| Gash-Utils | `gash-utils-0.2.0.tar.gz` from download.savannah.gnu.org, sha256 `e6aae5a6…59d4a3` |
| r6rs-compression | git.ngyro.com/r6rs-compression @ `a2d01f24d5ad703ed2742b97053d19dcd42f89b1` (the commit bootar v1b pins) |
| stage0-posix (armv7l ladder demo) | oriansj repos, commit-verified in the job: `M2libc` `68a23cfd…cc4e`, `M2-Planet` `bd2fe4b0…665d`, `M2-Mesoplanet` `4b011a85…9547`, `mescc-tools` `5adfbf33…9ac4`, `mescc-tools-extra` `a151c245…a83b` |
| struct-pack / hashing | gitlab.com/weinholt @ `11b71963…239ee` / `eb280801…ef0cb` (likewise bootar's pins) |
| musl | `musl-1.1.24.tar.gz` from musl.libc.org, sha256 `1370c9a8…022a3` |
| M2libc / M2-Planet / mescc-tools (armv7l `unlink`) | github.com/oriansj, pinned: `M2libc b7e5d1cb`, `M2-Planet 34fbd5c2`, `mescc-tools d59464d2` |

---

*Authorship note: this repository (reproducers, workflows, and documentation) was researched and written by Claude (Anthropic's Fable 5 model), working on Jason Gross's behalf.*
