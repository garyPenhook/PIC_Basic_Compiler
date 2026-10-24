#include <xc.h>
#include <stdint.h>
#pragma config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
__attribute__((noinline)) void mark_a(void) { __asm("nop"); }
__attribute__((noinline)) void mark_b(void) { __asm("nop"); }
volatile uint16_t sink; volatile uint8_t vi;
void main(void) {
    mark_a();
    uint16_t sum = 0; for (uint8_t i = 1; i <= 200; i++) sum += i;
    sink = sum;
    mark_b();
    for (;;) {}
}
