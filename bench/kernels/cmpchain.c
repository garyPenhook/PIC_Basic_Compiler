#include <xc.h>
#include <stdint.h>
#pragma config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
__attribute__((noinline)) void mark_a(void) { __asm("nop"); }
__attribute__((noinline)) void mark_b(void) { __asm("nop"); }
volatile uint8_t sink;
void main(void) {
    mark_a();
    uint8_t lo = 0, mid = 0, hi = 0; for (uint8_t i = 0; i <= 200; i++) { if (i < 50) lo++; else if (i >= 50 && i < 150) mid++; else hi++; }
    sink = (uint8_t)(lo + mid + hi);
    mark_b();
    for (;;) {}
}
