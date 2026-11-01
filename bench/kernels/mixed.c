#include <xc.h>
#include <stdint.h>
#pragma config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
__attribute__((noinline)) void mark_a(void) { __asm("nop"); }
__attribute__((noinline)) void mark_b(void) { __asm("nop"); }
volatile uint16_t sink;
void main(void) {
    mark_a();
    uint8_t buf[32], s = 7, st = 0, hi = 0;
    uint16_t crc, ds = 0, q = 0;
    int16_t y = 0;
    uint32_t acc = 0;
    for (uint8_t i = 0; i < 32; i++) { s = (uint8_t)(s * 5 + 3); buf[i] = s; }
    crc = 0xFFFF;
    for (uint8_t i = 0; i < 32; i++) {
        crc ^= (uint16_t)((uint16_t)buf[i] << 8);
        for (uint8_t j = 1; j <= 8; j++) crc = (crc & 0x8000) ? (uint16_t)((crc << 1) ^ 0x1021) : (uint16_t)(crc << 1);
    }
    for (uint8_t i = 0; i < 32; i++) {
        int16_t x = (int16_t)(buf[i] * 37), d = (int16_t)(x - y);
        y = (int16_t)(y + (d >> 2));
        acc = acc + (acc >> 3) + buf[i];
        switch (st) {
            case 0: if (buf[i] > 128) st = 1; break;
            case 1: hi++; st = 2; break;
            default: st = 0; break;
        }
    }
    for (uint8_t i = 1; i <= 8; i++) {
        uint16_t v = (uint16_t)(crc + i * 977);
        while (v > 0) { ds += v % 10; v /= 10; }
        uint16_t dv = buf[i] | 1;
        q += crc / dv;
    }
    sink = (uint16_t)(crc ^ ds ^ q ^ (uint16_t)y ^ hi);
    sink ^= (uint16_t)acc;
    mark_b();
    for (;;) {}
}
