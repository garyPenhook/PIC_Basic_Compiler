#include <xc.h>
#include <stdint.h>
#pragma config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
__attribute__((noinline)) void mark_a(void) { __asm("nop"); }
__attribute__((noinline)) void mark_b(void) { __asm("nop"); }
volatile uint8_t sink;
void main(void) {
    mark_a();
    uint8_t crc = 0; for (uint8_t i = 0; i <= 63; i++) { crc ^= i; for (uint8_t j = 1; j <= 8; j++) { if (crc & 0x80) crc = (uint8_t)((crc << 1) ^ 7); else crc = (uint8_t)(crc << 1); } }
    sink = crc;
    mark_b();
    for (;;) {}
}
