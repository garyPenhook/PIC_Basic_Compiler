#include "harness.h"

static void workload(void) {
    uint8_t stable = 0, count = 0, previous = 0, led = 0;
    uint8_t fast_timer = 10, slow_timer = 100;
    uint16_t presses = 0, fast_runs = 0, slow_runs = 0;
    for (uint16_t tick = 0; tick < 1000; ++tick) {
        uint8_t raw = ((tick >= 100 && tick < 300) || (tick >= 500 && tick < 800)) ? 1 : 0;
        if ((tick >= 100 && tick < 106) || (tick >= 300 && tick < 306) ||
            (tick >= 500 && tick < 506) || (tick >= 800 && tick < 806)) raw = (uint8_t)(tick & 1);
        if (raw == previous) { if (count < 5) ++count; }
        else { previous = raw; count = 1; }
        if (count == 5 && stable != raw) {
            stable = raw;
            if (stable) { ++presses; led ^= 1; }
        }
        if (--fast_timer == 0) { fast_timer = 10; ++fast_runs; sink += (uint32_t)stable + led; }
        if (--slow_timer == 0) { slow_timer = 100; ++slow_runs; sink += fast_runs; }
    }
    sink += (uint32_t)presses * 1000u + slow_runs;
}

BENCH_MAIN(workload)
