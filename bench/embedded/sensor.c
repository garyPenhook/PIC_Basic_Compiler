#include "harness.h"

static void workload(void) {
    static const uint16_t samples[32] = {0, 8, 16, 80, 200, 380, 399, 400, 401, 450, 599, 600, 601, 700, 849, 850, 851, 900, 901, 950, 1023, 1010, 920, 880, 800, 650, 550, 410, 390, 300, 100, 0};
    uint8_t heater = 0, alarm = 0;
    for (uint8_t batch = 0; batch < 64; ++batch) {
        uint16_t total = 0;
        for (uint8_t sample = 0; sample < 8; ++sample) {
            uint16_t adc = samples[(batch + sample) & 31u];
            total = (uint16_t)(total + adc);
        }
        uint16_t average = total >> 3;
        uint16_t millivolts = (uint16_t)((uint32_t)average * 5000u / 1023u);
        if (average < 400) heater = 1;
        else if (average > 600) heater = 0;
        if (average > 900) alarm = 1;
        else if (average < 850) alarm = 0;
        uint8_t outputs = (uint8_t)(heater | (alarm << 1));
        sink += (uint32_t)millivolts + outputs;
    }
}

BENCH_MAIN(workload)
