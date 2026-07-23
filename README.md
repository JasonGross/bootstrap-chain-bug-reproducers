# bootstrap-chain-bug-reproducers

Self-contained CI reproducers for upstream-reportable bugs found by the
[nix-bootstrapping](https://github.com/JasonGross) full-source-bootstrap
measurement project while driving the hex0 → Mes/MesCC → tcc → musl → GCC
chain on x86, ARM, and RISC-V.

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

| # | Bug | Status | Intended upstream | Local evidence in nix-bootstrapping |
|---|-----|--------|-------------------|--------------------------------------|
| 1 | [`mes-ldexp-stub`](bugs/01-mes-ldexp-stub/) | [![mes-ldexp-stub](../../actions/workflows/mes-ldexp-stub.yml/badge.svg)](../../actions/workflows/mes-ldexp-stub.yml) | GNU Mes (`bug-mes@gnu.org`) | `data/mescc-bugs/bug17-musl-strtod-miscompile/` (`mes-ldexp-stub.c`) |
| 2 | [`mes-abtod-fraction`](bugs/02-mes-abtod-fraction/) | [![mes-abtod-fraction](../../actions/workflows/mes-abtod-fraction.yml/badge.svg)](../../actions/workflows/mes-abtod-fraction.yml) | GNU Mes (`bug-mes@gnu.org`) | `data/mescc-bugs/bug18-mes-strtod-mantissa/` |
| 3 | [`mes-arm-getdents64`](bugs/03-mes-arm-getdents64/) | [![mes-arm-getdents64](../../actions/workflows/mes-arm-getdents64.yml/badge.svg)](../../actions/workflows/mes-arm-getdents64.yml) | GNU Mes (`bug-mes@gnu.org`) | bug21; `bootstrap-work/arm-commencement/getdents-fix-chain-build.log` |
| 4 | [`tcc-mes-arm-ldouble-zero`](bugs/04-tcc-mes-arm-ldouble-zero/) | [![tcc-mes-arm-ldouble-zero](../../actions/workflows/tcc-mes-arm-ldouble-zero.yml/badge.svg)](../../actions/workflows/tcc-mes-arm-ldouble-zero.yml) | janneke tinycc fork ([gitlab.com/janneke/tinycc](https://gitlab.com/janneke/tinycc)) | `data/mescc-bugs/bug20-tcc-arm-real-miscompile/` (+ `bug15-double-zero-materialization/`) |
| 5 | [`tcc-fp-parse-libc-poison`](bugs/05-tcc-fp-parse-libc-poison/) | [![tcc-fp-parse-libc-poison](../../actions/workflows/tcc-fp-parse-libc-poison.yml/badge.svg)](../../actions/workflows/tcc-fp-parse-libc-poison.yml) | janneke tinycc fork (context for an integer-only FP-literal parser) | `data/mescc-bugs/bug17-musl-strtod-miscompile/` |
| 6 | [`gash-exit-success-gate`](bugs/06-gash-exit-success-gate/) | [![gash-exit-success-gate](../../actions/workflows/gash-exit-success-gate.yml/badge.svg)](../../actions/workflows/gash-exit-success-gate.yml) | Gash (Timothy Sample; `bug-gash@nongnu.org`), possibly also guix-devel | arm-commencement `gash-utils-boot-fixed` packaging (commencement.scm branch) |
| 7 | [`fiwix-nr-buf-hash-lp64`](bugs/07-fiwix-nr-buf-hash-lp64/) | [![fiwix-nr-buf-hash-lp64](../../actions/workflows/fiwix-nr-buf-hash-lp64.yml/badge.svg)](../../actions/workflows/fiwix-nr-buf-hash-lp64.yml) | Fiwix (Mikel Izal; [github.com/mikaku/Fiwix](https://github.com/mikaku/Fiwix)) | fiwix-riscv64 port (draft PR #6, worktree `nix-bootstrapping-fiwix-rv64`) |
| 8 | [`tcc-riscv64-ldouble-cross`](bugs/08-tcc-riscv64-ldouble-cross/) | [![tcc-riscv64-ldouble-cross](../../actions/workflows/tcc-riscv64-ldouble-cross.yml/badge.svg)](../../actions/workflows/tcc-riscv64-ldouble-cross.yml) — **ALREADY REPORTED** | [codeberg.org/ekaitz-zarraga/tcc#1](https://codeberg.org/ekaitz-zarraga/tcc/issues/1); fixed upstream in tinycc mob `923fba83` ("general: long double issues") | riscv64 tcc/flex chain (`JasonGross/test-debugging-riscv64-tcc-flex`) |
| 9 | [`mescc-riscv64-uint32-add`](bugs/09-mescc-riscv64-uint32-add/) | [![mescc-riscv64-uint32-add](../../actions/workflows/mescc-riscv64-uint32-add.yml/badge.svg)](../../actions/workflows/mescc-riscv64-uint32-add.yml) | GNU Mes (`bug-mes@gnu.org`) | tinyemu-retarget `scripts/tinyemu-riscv/drivers/qemu-user-ref/mescc-u32-repro/` (branch `tinyemu-riscv-mes-tcc`) |
| 10 | [`tcc-mes-riscv64-fp-literal`](bugs/10-tcc-mes-riscv64-fp-literal/) | [![tcc-mes-riscv64-fp-literal](../../actions/workflows/tcc-mes-riscv64-fp-literal.yml/badge.svg)](../../actions/workflows/tcc-mes-riscv64-fp-literal.yml) | GNU Mes (`bug-mes@gnu.org`); context for the janneke tinycc fork (integer-only FP-literal parser, cf. bug 5) | riscv64 tcc-mes fixpoint forensics (branch `tinyemu-riscv-mes-tcc`, `qemu-user-ref/fixpoint-probes/`) |

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
nix-bootstrapping arm chain, the MesCC-built tcc links mes libc (bug 1's
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

### 7. `fiwix-nr-buf-hash-lp64` — Fiwix 1.5.0 buffer hash: sized in `unsigned int` units, indexed as a pointer array — 2× out of bounds on LP64

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
`0x3FEFFF2E48E8A71E`. In the nix-bootstrapping riscv64 fixpoint forensics
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
needs the whole mes/tcc riscv64 chain and is not run in CI; see the
nix-bootstrapping `tinyemu-riscv-mes-tcc` fixpoint forensics for it.)

## Pinned sources

| Source | Pin |
|--------|-----|
| GNU Mes | `mes-0.27.1.tar.gz` from ftp.gnu.org, sha256 `183a40ea…f25d` |
| janneke tinycc fork | gitlab.com/janneke/tinycc @ `ee75a10cd71bebf23cb23598a49ee3c160ef0fe8` (branch `mes-0.25.0`) |
| mainline tinycc | repo.or.cz/tinycc.git @ `release_0_9_27` = `d348a9a51d32cece842b7885d27a411436d7887b` (fallback when repo.or.cz is down: the official github.com/TinyCC/tinycc mirror; the commit-hash pin is the integrity check either way) |
| GNU Guile | `guile-2.0.11.tar.xz` from ftp.gnu.org, sha256 `aed0a4a6…03e2` |
| Gash | `gash-0.2.0.tar.gz` + `gash-utils-0.2.0.tar.gz` from download.savannah.gnu.org, sha256 `ee415804…7a08e` / `e6aae5a6…59d4a3` |
| Fiwix | github.com/mikaku/Fiwix tag `v1.5.0` archive, sha256 `e1d5ce53…c4fe0` |
| Linux (reference syscall table) | raw.githubusercontent.com torvalds/linux `v4.19` `arch/arm/tools/syscall.tbl` (the file mes' header cites) |
| NYACC | `nyacc-1.00.2.tar.gz` from download.savannah.nongnu.org, sha256 `f36e4fb7…b318` |
| mescc-tools | `mescc-tools-1.7.0.tar.gz` from download.savannah.nongnu.org, sha256 `b682f7bf…575c` |

---

*Authorship note: this repository (reproducers, workflows, and documentation) was researched and written by Claude (Anthropic's Fable 5 model), working on Jason Gross's behalf.*
