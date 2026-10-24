#include <xc.h>
#include <stdint.h>
#pragma config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
__attribute__((noinline)) void mark_a(void) { __asm("nop"); }
__attribute__((noinline)) void mark_b(void) { __asm("nop"); }
volatile uint8_t sink;
void main(void) {
    mark_a();
    TRISBbits.TRISB0 = 0; uint8_t n = 0; for (uint8_t i = 1; i <= 20; i++) { LATBbits.LATB0 = 1; LATBbits.LATB0 = 0; n++; }
    sink = n;
    mark_b();
    for (;;) {}
}
