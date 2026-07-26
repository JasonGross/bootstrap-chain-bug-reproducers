/* Exercise TinyEMU's softfp normalisation, which is what clz32/clz64 exist
 * for: integer -> float conversion has to normalise the mantissa. */
#include <stdint.h>
#include <stdio.h>
#include "cutils.h"
#include "softfp.h"
int main(void)
{
    static const uint32_t v32[] = {1u, 3u, 255u, 0x12345u, 0x80000000u};
    static const uint64_t v64[] = {1ull, 3ull, 255ull, 0x12345ull,
                                   0x8000000000000000ull};
    uint32_t fflags;
    int i;
    for (i = 0; i < 5; i++) {
        fflags = 0;
        printf("cvt_u32_sf32(%08x) = %08x\n", v32[i],
               (uint32_t)cvt_u32_sf32(v32[i], RM_RNE, &fflags));
    }
    for (i = 0; i < 5; i++) {
        fflags = 0;
        printf("cvt_u64_sf64(%016llx) = %016llx\n",
               (unsigned long long)v64[i],
               (unsigned long long)cvt_u64_sf64(v64[i], RM_RNE, &fflags));
    }
    return 0;
}
