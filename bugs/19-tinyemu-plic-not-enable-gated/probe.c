/*
 * PLIC register-presence probe for the TinyEMU "not enable-gated" finding
 * (docs/upstream/tinyemu-plic-not-enable-gated.md, board row 20).
 *
 * Writes a known pattern to three PLIC registers that a spec-compliant PLIC
 * implements -- a per-source PRIORITY, a per-context ENABLE bitmask, and a
 * per-context THRESHOLD -- then reads each back.
 *
 *   - On a spec-compliant PLIC (qemu-system-riscv64 -M virt) the registers
 *     exist, so the readback returns the value just written.
 *   - On TinyEMU the registers do not exist: plic_write drops the write
 *     (default: break) and plic_read returns 0 (default: val = 0), so every
 *     readback is 0.
 *
 * The write is the stimulus: an unwritten qemu enable register is also 0, so a
 * read-only probe would be vacuous. It is the contrast between qemu (readback
 * == written, nonzero) and temu (readback == 0 despite the write) that
 * demonstrates the missing gating registers.
 *
 * Same source for both targets; -DTARGET_TEMU selects temu's PLIC base and
 * HTIF console, else qemu virt's PLIC base, ns16550 console and test-finisher.
 */

#include <stdint.h>

#ifdef TARGET_TEMU
#define PLIC_BASE 0x40100000UL      /* riscv_machine.c PLIC_BASE_ADDR */
#define HTIF_BASE 0x40008000UL      /* riscv_machine.c HTIF_BASE_ADDR */
#else
#define PLIC_BASE 0x0c000000UL      /* qemu hw/riscv/virt.c VIRT_PLIC */
#define UART_BASE 0x10000000UL      /* qemu virt ns16550a UART0 */
#define TEST_BASE 0x00100000UL      /* qemu virt sifive_test finisher */
#endif

/* PLIC register offsets (identical layout on any SiFive-style PLIC). */
#define PLIC_PRIORITY(src)   (PLIC_BASE + (uint64_t)(src) * 4)
#define PLIC_ENABLE(ctx)     (PLIC_BASE + 0x2000UL + (uint64_t)(ctx) * 0x80)
#define PLIC_THRESHOLD(ctx)  (PLIC_BASE + 0x200000UL + (uint64_t)(ctx) * 0x1000)

static inline void w32(uint64_t a, uint32_t v){ *(volatile uint32_t *)a = v; }
static inline uint32_t r32(uint64_t a){ return *(volatile uint32_t *)a; }

static void putc_(char c)
{
#ifdef TARGET_TEMU
    /* HTIF putchar: tohost = device 1, cmd 1, payload = char.
       low word (offset 0) = payload; high word (offset 4) = dev<<24|cmd<<16. */
    w32(HTIF_BASE + 0, (uint8_t)c);
    w32(HTIF_BASE + 4, 0x01010000);
#else
    volatile uint8_t *u = (volatile uint8_t *)UART_BASE;
    while (!(u[5] & 0x20)) { }   /* LSR THRE */
    u[0] = (uint8_t)c;
#endif
}

static void puts_(const char *s){ while (*s) putc_(*s++); }

static void puthex8(uint32_t v)
{
    static const char h[] = "0123456789abcdef";
    for (int i = 7; i >= 0; i--) putc_(h[(v >> (i * 4)) & 0xf]);
}

static void halt_(void)
{
#ifdef TARGET_TEMU
    w32(HTIF_BASE + 0, 1);      /* tohost bit0 set => exit, code (v>>1)=0 */
    w32(HTIF_BASE + 4, 0);
#else
    w32(TEST_BASE, 0x5555);     /* sifive_test FINISHER_PASS */
#endif
    for (;;) { }
}

void probe_main(void)
{
    uint32_t prio, en, thr;

    w32(PLIC_PRIORITY(5), 3);       en  = 0; /* keep ordering explicit */
    prio = r32(PLIC_PRIORITY(5));
    w32(PLIC_ENABLE(0), 0x20);              /* enable source 5 for context 0 */
    en   = r32(PLIC_ENABLE(0));
    w32(PLIC_THRESHOLD(0), 3);
    thr  = r32(PLIC_THRESHOLD(0));

    puts_("PRIO5 "); puthex8(prio); putc_('\n');
    puts_("EN0 ");   puthex8(en);   putc_('\n');
    puts_("THR0 ");  puthex8(thr);  putc_('\n');
    puts_("DONE\n");
    halt_();
}
