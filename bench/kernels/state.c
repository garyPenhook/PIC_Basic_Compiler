#include <xc.h>
#include <stdint.h>
#pragma config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
__attribute__((noinline)) void mark_a(void) { __asm("nop"); }
__attribute__((noinline)) void mark_b(void) { __asm("nop"); }
volatile uint8_t sink;
void main(void) {
    mark_a();
    uint8_t s = 0, n = 0; for (uint8_t i = 1; i <= 100; i++) { switch (s) { case 0: s = 1; break; case 1: s = 2; n++; break; case 2: s = 3; break; default: s = 0; } }
    sink = n;
    mark_b();
    for (;;) {}
}
