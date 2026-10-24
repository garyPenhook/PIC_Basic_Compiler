#include <xc.h>
#include <stdint.h>
#pragma config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
__attribute__((noinline)) void mark_a(void) { __asm("nop"); }
__attribute__((noinline)) void mark_b(void) { __asm("nop"); }
volatile uint32_t sink;
void main(void) {
    mark_a();
    uint32_t acc = 0; for (uint8_t i = 1; i <= 100; i++) acc += (uint32_t)i * 1000;
    sink = acc;
    mark_b();
    for (;;) {}
}
