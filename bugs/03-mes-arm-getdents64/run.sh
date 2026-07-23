#!/usr/bin/env bash
# mes-arm-getdents64: GNU Mes 0.27.1 include/linux/arm/syscall.h defines
# SYS_getdents64 as 0xdc (220) -- the x86 number.  On arm EABI, 220 is
# madvise; getdents64 is 217 (0xd9).
# GREEN == (A) the header value mismatches the kernel's own arm syscall table,
# and (B) behaviorally, syscall(220) on a directory fd does not read dirents
# while syscall(217) does (static arm binary under qemu-user).
cd "$(dirname "$0")"
. ../common.sh

mkdir -p work
fetch_mes work
MES=work/mes-0.27.1
HDR=$MES/include/linux/arm/syscall.h

banner "PART A -- the header vs. the kernel's arm syscall table"
loud "mes-0.27.1/include/linux/arm/syscall.h:"
grep -n 'SYS_getdents' "$HDR"
mes_val=$(( $(grep -E '#define[[:space:]]+SYS_getdents64' "$HDR" | awk '{print $3}') ))
loud "mes SYS_getdents64 = $mes_val"

loud "the header's OWN cited authority (see its Commentary block):"
grep -n 'syscall.tbl' "$HDR" | head -2
TBL_URL=https://raw.githubusercontent.com/torvalds/linux/v4.19/arch/arm/tools/syscall.tbl
curl -fsSL --retry 5 -o work/syscall.tbl "$TBL_URL"
loud "linux v4.19 arch/arm/tools/syscall.tbl:"
grep -E '^(217|220)[[:space:]]' work/syscall.tbl
true_getdents64=$(awk '$3 == "getdents64" && $2 == "common" {print $1}' work/syscall.tbl)
arm_madvise=$(awk '$3 == "madvise" && $2 == "common" {print $1}' work/syscall.tbl)

[ "$true_getdents64" = 217 ] || die "sanity: kernel table getdents64 != 217?"
[ "$arm_madvise" = 220 ] || die "sanity: kernel table madvise != 220?"
[ "$mes_val" = 220 ] || die "mes header no longer says 220 -- bug gone?"
loud "MISMATCH CONFIRMED: mes says getdents64=$mes_val; the arm kernel says"
loud "getdents64=$true_getdents64 and $arm_madvise=madvise.  (220 is getdents64 on x86/i386 --"
loud "the arm header inherited the x86 number.)"

if [ -f /usr/arm-linux-gnueabihf/include/asm/unistd-common.h ]; then
  loud "corroboration from the arm glibc kernel headers on this machine:"
  grep -E '__NR_(getdents64|madvise) ' /usr/arm-linux-gnueabihf/include/asm/unistd-common.h || true
fi

banner "PART B -- behavioral: run both numbers on a directory fd (arm, qemu-user)"
command -v arm-linux-gnueabihf-gcc >/dev/null || die "need gcc-arm-linux-gnueabihf"
command -v qemu-arm-static >/dev/null || die "need qemu-user-static"
arm-linux-gnueabihf-gcc -O2 -static -include "$HDR" getdents-demo.c -o work/getdents-demo
cd work && qemu-arm-static ./getdents-demo
cd ..

banner "VERDICT"
loud "BUG REPRODUCED: mes' arm SYS_getdents64 (0xdc=220) is the x86 number and"
loud "lands on arm madvise; the correct arm number is 217 (0xd9).  Any mes-libc"
loud "readdir on arm EABI fails (this is nix-bootstrapping bug21; it bit the arm"
loud "bootstrap the first time a mes-linked tool listed a directory)."
echo "PASS: mes-arm-getdents64 reproduced"
