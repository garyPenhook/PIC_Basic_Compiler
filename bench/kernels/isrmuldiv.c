#include <xc.h>
#include <stdint.h>
#pragma config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
__attribute__((noinline)) void mark_a(void) { __asm("nop"); }
__attribute__((noinline)) void mark_b(void) { __asm("nop"); }
volatile uint16_t sink;
volatile uint16_t hits, acc, q;
void __interrupt() isr(void) {
    if (PIR0bits.TMR0IF) {
        PIR0bits.TMR0IF = 0;
        uint16_t h = hits + 1, a = acc, t = q;
        hits = h;
        a = a * 5 + h;
        t = t + a / 7 + a % 13;
        acc = a;
        q = t;
    }
}
void main(void) {
    uint16_t m = 0, d = 0;
    PIE0bits.TMR0IE = 1;
    INTCONbits.PEIE = 1;   // the datasheet says PIR0 flags ignore PEIE, but the MDB simulator needs it
    INTCONbits.GIE = 1;
    mark_a();
    for (uint16_t i = 1; i <= 50; i++) {
        m += i * 37;
        d += 54321u / (i + 3);
        PIR0bits.TMR0IF = 1;
        while (hits < i) {}
    }
    sink = (m ^ d) + (acc ^ q);
    mark_b();
    for (;;) {}
}
