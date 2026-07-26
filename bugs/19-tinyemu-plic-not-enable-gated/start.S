    /* Minimal M-mode entry for the PLIC register-presence probe.
       Loaded at 0x80000000 on both temu (as bios) and qemu virt (as -kernel,
       -bios none). a0=hartid, a1=FDT on entry; we ignore both. */
    .section .text.entry, "ax"
    .globl _start
_start:
    li   sp, 0x80100000        /* 1 MiB into RAM; image is tiny */
    call probe_main
halt:
    wfi
    j    halt
