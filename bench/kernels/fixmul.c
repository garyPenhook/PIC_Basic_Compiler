#include <xc.h>
#include <stdint.h>
#pragma config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
__attribute__((noinline)) void mark_a(void) { __asm("nop"); }
__attribute__((noinline)) void mark_b(void) { __asm("nop"); }
volatile uint16_t sink;
void main(void) {
    mark_a();
    uint16_t acc = 0; for (uint16_t x = 0; x <= 1000; x += 7) acc += (uint16_t)(x * 10) >> 8;
    sink = acc;
    mark_b();
    for (;;) {}
}
