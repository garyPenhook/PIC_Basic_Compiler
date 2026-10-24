#include <xc.h>
#include <stdint.h>
#pragma config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
__attribute__((noinline)) void mark_a(void) { __asm("nop"); }
__attribute__((noinline)) void mark_b(void) { __asm("nop"); }
volatile uint16_t sink; volatile uint16_t vn = 54321;
void main(void) {
    mark_a();
    uint16_t n = vn, q = 0, m = 0; for (uint8_t i = 1; i <= 50; i++) { q += n / i; m += n % i; }
    sink = q ^ m;
    mark_b();
    for (;;) {}
}
