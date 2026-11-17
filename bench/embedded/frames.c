#include "harness.h"

static void workload(void) {
    static const uint8_t stream[32] = {0,165,1,42,142,165,2,99,196,165,1,7,0,85,165,3,12,170,165,2,18,181,165,9,77,225,165,1,0,164,165,0};
    uint8_t regs[4] = {0}, command = 0, payload = 0, checksum = 0;
    uint16_t accepted = 0, rejected = 0;
    for (uint8_t pass = 0; pass < 32; ++pass) {
        uint8_t state = 0;
        for (uint8_t i = 0; i < 32; ++i) {
            uint8_t value = stream[i];
            switch (state) {
            case 0: if (value == 165) { checksum = value; state = 1; } break;
            case 1: command = value; checksum ^= value; state = 2; break;
            case 2: payload = value; checksum ^= value; state = 3; break;
            default:
                if (checksum == value && command >= 1 && command <= 4) { regs[command - 1] = payload; ++accepted; sink += (uint32_t)payload + command; }
                else ++rejected;
                state = 0;
                break;
            }
        }
        for (uint8_t i = 0; i < 4; ++i) sink += regs[i];
    }
    sink += (uint32_t)accepted * 100u + rejected;
}

BENCH_MAIN(workload)
