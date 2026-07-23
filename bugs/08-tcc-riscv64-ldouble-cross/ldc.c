/* One long double constant.  Target riscv64: long double == IEEE-754
   binary128 (16 bytes).  Host x86_64: long double == x87 80-bit.  A cross
   tcc must CONVERT when materializing the constant; the pre-fix mob instead
   memcpy'd the host's x87 image into the 16-byte target slot.  */
long double x = 1000000000.0L; /* == 1e9 */
