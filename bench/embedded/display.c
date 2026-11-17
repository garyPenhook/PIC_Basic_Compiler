#include "harness.h"

static void workload(void) {
    uint8_t line[16];
    for (uint8_t update = 0; update < 64; ++update) {
        uint16_t adc = (uint16_t)(((uint16_t)update * 37u + 17u) & 1023u);
        uint16_t millivolts = (uint16_t)((uint32_t)adc * 5000u / 1023u);
        uint8_t relay = update & 1;
        for (uint8_t i = 0; i < 16; ++i) line[i] = 32;
        line[0] = 65; line[1] = 61;
        uint16_t value = adc;
        for (uint8_t i = 5; i >= 2; --i) { line[i] = (uint8_t)(value % 10u + 48u); value /= 10u; }
        line[7] = 86; line[8] = 61;
        value = millivolts;
        for (uint8_t i = 12; i >= 9; --i) { line[i] = (uint8_t)(value % 10u + 48u); value /= 10u; }
        line[14] = 82; line[15] = (uint8_t)(relay + 48);
        for (uint8_t i = 0; i < 16; ++i) sink += (uint16_t)line[i] * (i + 1u);
    }
}

BENCH_MAIN(workload)
