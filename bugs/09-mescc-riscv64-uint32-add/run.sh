#!/usr/bin/env bash
# mescc-riscv64-uint32-add: MesCC's riscv64 backend evaluates 32-bit unsigned
# arithmetic in full 64-bit registers with no mod-2^32 truncation, so
# ((imm + (1<<11)) >> 12) != 0 for imm = (unsigned)-16.
# GREEN == the bug reproduces BOTH statically (emitted .s lacks the re-mask)
# and at runtime (MesCC-built riscv64 binary exits 42 under qemu-user), while
# the controls (host gcc, riscv64-linux-gnu-gcc under qemu, and MesCC's own
# explicit-cast leg) all yield the wrapped-correct 0.
cd "$(dirname "$0")"
. ../common.sh
BUGDIR=$PWD

command -v guile >/dev/null || die "need guile 3.x (apt: guile-3.0)"
command -v qemu-riscv64-static >/dev/null || die "need qemu-user-static"
command -v riscv64-linux-gnu-gcc >/dev/null || die "need gcc-riscv64-linux-gnu"

MESCC_TOOLS_URL=https://download.savannah.nongnu.org/releases/mescc-tools/mescc-tools-1.7.0.tar.gz
MESCC_TOOLS_SHA=b682f7bf576f89e55d0b1c638d9de2d9beb285572268f58fabf4ed14d9b6575c

mkdir -p work
fetch_mes work
fetch_nyacc work
MES=$PWD/work/mes-0.27.1

# The 2-line config.h the bootstrap's mes build step generates (live-bootstrap
# steps/mes-0.27.1/files/config.h minus comments).
printf '#undef SYSTEM_LIBC\n#define MES_VERSION "0.27.1"\n' > "$MES/include/mes/config.h"

banner "BUILD: stage0 assembler/linker (M1, hex2, blood-elf) from mescc-tools-1.7.0"
fetch "$MESCC_TOOLS_URL" "$MESCC_TOOLS_SHA" work/mescc-tools-1.7.0.tar.gz
[ -d work/mescc-tools-1.7.0 ] || tar -xzf work/mescc-tools-1.7.0.tar.gz -C work
make -C work/mescc-tools-1.7.0 --quiet M1 hex2 blood-elf
export M1=$PWD/work/mescc-tools-1.7.0/bin/M1
export HEX2=$PWD/work/mescc-tools-1.7.0/bin/hex2
export BLOOD_ELF=$PWD/work/mescc-tools-1.7.0/bin/blood-elf

# MesCC itself: the UNMODIFIED Scheme compiler from the mes-0.27.1 tarball,
# hosted on Guile (mescc-guile.scm only replicates configure's env baking).
export GUILE_LOAD_PATH="$MES/module:$PWD/work/nyacc-1.00.2/module"
export MES_PREFIX="$MES"
mescc () { guile --no-auto-compile -e main -s "$BUGDIR/mescc-guile.scm" "$@"; }

banner "THE ACCUSED CODEGEN: mescc --arch riscv64 -S on the 2-function probe"
sed -n '/^unsigned/,$p' repro.c
cp repro.c runtime-f.c runtime-g.c work/
( cd work && mescc --arch riscv64 -S -o repro.s repro.c )
python3 check-s.py work/repro.s

banner "RUNTIME (bug): MesCC-built static riscv64 binaries under qemu-riscv64"
loud "compiling mes' own riscv64 crt1 + minimal libc TUs with MesCC, then the probes"
cp "$MES/lib/linux/riscv64-mes-mescc/crt1.c" work/start.c
cp "$MES/lib/mes/globals.c"                  work/globals.c
cp "$MES/lib/mes/__init_io.c"                work/initio.c
( cd work &&
  for f in start globals initio runtime-f runtime-g; do
    mescc --arch riscv64 -c -o $f.o $f.c
  done &&
  mescc --arch riscv64 -nostdlib -o probe-f start.o globals.o initio.o runtime-f.o &&
  mescc --arch riscv64 -nostdlib -o probe-g start.o globals.o initio.o runtime-g.o &&
  chmod +x probe-f probe-g )
file work/probe-f

set +e
qemu-riscv64-static work/probe-f; rc_f=$?
qemu-riscv64-static work/probe-g; rc_g=$?
set -e
loud "MesCC-built probe-f (uncast, the tcc-1147 assert shape) exit: $rc_f  (42 = miscompiled)"
loud "MesCC-built probe-g (explicit-cast leg, the tcc-1157 dodge) exit: $rc_g  (0 = correct)"

banner "CONTROL 1: host gcc, same expressions"
gcc -O0 -o work/host-control host-control.c
./work/host-control

banner "CONTROL 2: riscv64-linux-gnu-gcc -static -O0, same probe sources, same qemu"
riscv64-linux-gnu-gcc -static -O0 -o work/probe-f-gcc work/runtime-f.c
riscv64-linux-gnu-gcc -static -O0 -o work/probe-g-gcc work/runtime-g.c
set +e
qemu-riscv64-static work/probe-f-gcc; rc_fg=$?
qemu-riscv64-static work/probe-g-gcc; rc_gg=$?
set -e
loud "riscv64-gcc-built probe-f exit: $rc_fg   probe-g exit: $rc_gg   (both 0 = correct)"

banner "VERDICT"
[ "$rc_f" = 42 ] || die "bug did NOT reproduce: MesCC-built probe-f exited $rc_f, not 42"
[ "$rc_g" = 0 ]  || die "cast-leg control failed: MesCC-built probe-g exited $rc_g"
[ "$rc_fg" = 0 ] || die "riscv64-gcc control failed: probe-f exited $rc_fg"
[ "$rc_gg" = 0 ] || die "riscv64-gcc control failed: probe-g exited $rc_gg"
loud "BUG REPRODUCED: MesCC (mes-0.27.1, riscv64) evaluates (imm + (1<<11)) >> 12"
loud "as a full 64-bit operation: 0xfffffff0 + 0x800 = 0x1000007f0, >>12 = 0x100000,"
loud "instead of the C-mandated mod-2^32 wrap to 0.  A semantically no-op"
loud "(unsigned) cast on the sum restores correctness (probe-g)."
loud "Consequence in a bootstrap: tcc-0.9.26-1147's riscv64 12-bit-immediate guard"
loud "assert(!((imm + (1 << 11)) >> 12)) false-positives on EVERY negative"
loud "immediate, so the MesCC-built tcc-mes dies on the first function epilogue"
loud "(addi sp,sp,-16) it generates; tcc rev 1157 dodges it with an explicit"
loud "(uint32_t) cast."
echo "PASS: mescc-riscv64-uint32-add reproduced"
