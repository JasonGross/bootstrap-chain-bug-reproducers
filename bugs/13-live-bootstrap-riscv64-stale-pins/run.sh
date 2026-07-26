#!/usr/bin/env bash
# live-bootstrap-riscv64-stale-pins: live-bootstrap's riscv64 checksum set
# describes a chain that cannot be built as pinned.  `steps/tcc-0.9.26/sources`
# pins tcc-0.9.26-1147-gee75a10c, whose EI/ES 12-bit-immediate assertion MesCC
# miscompiles (see bug 9 in this repo) -- so the MesCC-built tcc-mes asserts out
# on the first function epilogue it emits.  Commit 865b9aea bumped only the
# tcc-mes hash when moving to mes-0.27.1, leaving the downstream artifacts
# (crt1.o, libc.a) at values the 1157-era lineage produces.
# GREEN == master still pins 1147 with the 865b9aea-era checksums, the pinned
# 1147 source lacks the (uint32_t) cast that 1157 carries, and the guard lifted
# verbatim from 1147 FIRES under MesCC for the first-epilogue immediate while
# 1157's does not (host gcc: both fine).
cd "$(dirname "$0")"
. ../common.sh
BUGDIR=$PWD

command -v guile >/dev/null || die "need guile 3.x (apt: guile-3.0)"
command -v qemu-riscv64-static >/dev/null || die "need qemu-user-static"

LB_RAW=https://raw.githubusercontent.com/fosslinux/live-bootstrap
LB_API=https://api.github.com/repos/fosslinux/live-bootstrap
TCC1147_URL=https://lilypond.org/janneke/tcc/tcc-0.9.26-1147-gee75a10c.tar.gz
TCC1147_SHA=6b8cbd0a5fed0636d4f0f763a603247bc1935e206e1cc5bda6a2818bab6e819f
TCC1157_URL=https://lilypond.org/janneke/tcc/tcc-0.9.26-1157-gdd46e018.tar.gz
TCC1157_SHA=3748c0aacd1e7b3805de09f28a4ef396392b2c838f78c59d23bfd9d68312232e
MESCC_TOOLS_URL=https://download.savannah.nongnu.org/releases/mescc-tools/mescc-tools-1.7.0.tar.gz
MESCC_TOOLS_SHA=b682f7bf576f89e55d0b1c638d9de2d9beb285572268f58fabf4ed14d9b6575c
BUMP_COMMIT=865b9aeae17dfa4e82fda799462b4316bf1c5b24   # "Update mes to 0.27.1"

mkdir -p work

banner "1/4 -- WHAT UPSTREAM MASTER PINS TODAY"
HEAD_SHA=$(curl -fsSL --retry 3 "$LB_API/branches/master" \
             | python3 -c 'import json,sys; print(json.load(sys.stdin)["commit"]["sha"])')
loud "fosslinux/live-bootstrap master = $HEAD_SHA"
curl -fsSL --retry 3 -o work/sources "$LB_RAW/$HEAD_SHA/steps/tcc-0.9.26/sources"
curl -fsSL --retry 3 -o work/riscv64.checksums \
     "$LB_RAW/$HEAD_SHA/steps/tcc-0.9.26/tcc-0.9.26.riscv64.checksums"
echo "  steps/tcc-0.9.26/sources:"
sed 's/^/    /' work/sources
grep -q 'tcc-0.9.26-1147-gee75a10c.tar.gz' work/sources \
  || die "master no longer pins tcc-1147 -- upstream may have fixed this; re-read the report"
grep -q "$TCC1147_SHA" work/sources \
  || die "master pins 1147 under a DIFFERENT sha256 than this reproducer expects"
loud "master still pins tcc-0.9.26-1147-gee75a10c (sha256 ${TCC1147_SHA:0:16}...)"

echo "  steps/tcc-0.9.26/tcc-0.9.26.riscv64.checksums:"
sed 's/^/    /' work/riscv64.checksums
last_touch=$(curl -fsSL --retry 3 \
  "$LB_API/commits?path=steps/tcc-0.9.26/tcc-0.9.26.riscv64.checksums&per_page=1" \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d[0]["sha"], d[0]["commit"]["committer"]["date"][:10], d[0]["commit"]["message"].splitlines()[0])')
loud "riscv64 checksums last touched: $last_touch"
case "$last_touch" in
  "$BUMP_COMMIT"*) loud "...which is 865b9aea, the mes-0.27.1 bump -- unchanged since." ;;
  *) die "the riscv64 checksums moved since 865b9aea -- upstream may have regenerated them" ;;
esac

banner "2/4 -- THE PINNED SOURCE vs THE NEXT REVISION, AT THE ASSERT"
fetch "$TCC1147_URL" "$TCC1147_SHA" work/tcc-1147.tar.gz
fetch "$TCC1157_URL" "$TCC1157_SHA" work/tcc-1157.tar.gz
[ -d work/tcc-0.9.26-1147-gee75a10c ] || tar -xzf work/tcc-1147.tar.gz -C work
[ -d work/tcc-0.9.26-1157-gdd46e018 ] || tar -xzf work/tcc-1157.tar.gz -C work
S1147=work/tcc-0.9.26-1147-gee75a10c/riscv64-gen.c
S1157=work/tcc-0.9.26-1157-gdd46e018/riscv64-gen.c
loud "the EI()/ES() guards in each revision:"
grep -n 'assert(!' "$S1147" | sed 's/^/    1147: /'
grep -n 'assert(!' "$S1157" | sed 's/^/    1157: /'
grep -q 'assert(! ((imm + (1 << 11)) >> 12));' "$S1147" \
  || die "1147's uncast guard is not where we expect it"
grep -q 'assert(! ((uint32_t)(imm + (1 << 11)) >> 12));' "$S1157" \
  || die "1157's cast guard is not where we expect it"
loud "1147 has NO cast; 1157 adds an explicit (uint32_t) -- a no-op in C, but"
loud "the thing that makes MesCC emit the mod-2^32 re-mask (bug 9 in this repo)."

banner "3/4 -- BUILD: MesCC (mes-0.27.1) + stage0 M1/hex2/blood-elf"
fetch_mes work
fetch_nyacc work
MES=$PWD/work/mes-0.27.1
printf '#undef SYSTEM_LIBC\n#define MES_VERSION "0.27.1"\n' > "$MES/include/mes/config.h"
fetch "$MESCC_TOOLS_URL" "$MESCC_TOOLS_SHA" work/mescc-tools-1.7.0.tar.gz
[ -d work/mescc-tools-1.7.0 ] || tar -xzf work/mescc-tools-1.7.0.tar.gz -C work
make -C work/mescc-tools-1.7.0 --quiet M1 hex2 blood-elf
export M1=$PWD/work/mescc-tools-1.7.0/bin/M1
export HEX2=$PWD/work/mescc-tools-1.7.0/bin/hex2
export BLOOD_ELF=$PWD/work/mescc-tools-1.7.0/bin/blood-elf
export GUILE_LOAD_PATH="$MES/module:$PWD/work/nyacc-1.00.2/module"
export MES_PREFIX="$MES"
mescc () { guile --no-auto-compile -e main -s "$BUGDIR/mescc-guile.scm" "$@"; }

banner "4/4 -- DOES THE PINNED COMPILER SURVIVE ITS OWN FIRST EPILOGUE?"
loud "lifting each revision's guard verbatim into a probe:"
python3 extract-guard.py "$S1147" work/guard-1147.c "pinned 1147"
python3 extract-guard.py "$S1157" work/guard-1157.c "next  1157"
cp "$MES/lib/linux/riscv64-mes-mescc/crt1.c" work/start.c
cp "$MES/lib/mes/globals.c"                  work/globals.c
cp "$MES/lib/mes/__init_io.c"                work/initio.c
( cd work &&
  for f in start globals initio guard-1147 guard-1157; do
    mescc --arch riscv64 -c -o $f.o $f.c
  done &&
  mescc --arch riscv64 -nostdlib -o probe-1147 start.o globals.o initio.o guard-1147.o &&
  mescc --arch riscv64 -nostdlib -o probe-1157 start.o globals.o initio.o guard-1157.o &&
  chmod +x probe-1147 probe-1157 )

set +e
qemu-riscv64-static work/probe-1147; rc_1147=$?
qemu-riscv64-static work/probe-1157; rc_1157=$?
set -e
echo "  MesCC-built, guard from the PINNED 1147 : exit $rc_1147   (42 = assertion fires)"
echo "  MesCC-built, guard from 1157            : exit $rc_1157   (0  = assertion passes)"

loud "host-gcc control (a conforming compiler -- both guards are correct C):"
gcc -O0 -o work/host-1147 work/guard-1147.c
gcc -O0 -o work/host-1157 work/guard-1157.c
set +e
./work/host-1147; h1147=$?
./work/host-1157; h1157=$?
set -e
echo "  host gcc, 1147 guard : exit $h1147"
echo "  host gcc, 1157 guard : exit $h1157"

banner "VERDICT"
[ "$rc_1147" = 42 ] || die "the pinned 1147 guard did NOT fire under MesCC (exit $rc_1147)"
[ "$rc_1157" = 0 ]  || die "1157's guard should pass under MesCC (exit $rc_1157)"
[ "$h1147" = 0 ] || die "host-gcc control failed on the 1147 guard (exit $h1147)"
[ "$h1157" = 0 ] || die "host-gcc control failed on the 1157 guard (exit $h1157)"
loud "REPRODUCED: fosslinux/live-bootstrap master still pins tcc-0.9.26-1147"
loud "for riscv64, with a riscv64 checksum set untouched since 865b9aea."
loud "That pinned source's own EI/ES assertion, compiled by the MesCC that"
loud "live-bootstrap uses to build it, FIRES on the immediate of the first"
loud "epilogue instruction any tcc emits (addi sp,sp,-16) -- so the pinned"
loud "tcc-mes cannot compile anything.  Revision 1157 dodges it with an"
loud "explicit (uint32_t) cast.  Both guards are correct C: host gcc accepts"
loud "each.  The defect is MesCC's (bug 9 here); the consequence is that this"
loud "pin cannot build through."
echo
loud "NOT SHOWN HERE (local evidence only, too slow for CI): that the 1157"
loud "lineage's generation-2 self-build reproduces the PINNED crt1.o"
loud "cc417e9d50f0... byte-exactly, which is what makes the checksum set"
loud "'mixed-era' rather than merely stale.  See the report for that."
echo "PASS: live-bootstrap-riscv64-stale-pins reproduced"
