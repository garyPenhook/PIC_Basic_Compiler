#include <xc.h>
#include <stdint.h>
#pragma config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
__attribute__((noinline)) void mark_a(void) { __asm("nop"); }
__attribute__((noinline)) void mark_b(void) { __asm("nop"); }
volatile uint16_t sink; volatile uint8_t vk = 37;
void main(void) {
    mark_a();
    uint8_t k = vk; uint16_t w = 0; for (uint8_t i = 1; i <= 100; i++) w += (uint16_t)(i * k);
    sink = w;
    mark_b();
    for (;;) {}
}
