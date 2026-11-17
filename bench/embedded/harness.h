#ifndef EMBEDDED_BENCH_H
#define EMBEDDED_BENCH_H
#include <stdint.h>
#ifdef HOST_BENCH
#include <stdio.h>
#else
#include <xc.h>
#ifdef BENCH_PIC16
#pragma config FEXTOSC = OFF, RSTOSC = HFINT32, WDTE = OFF, LVP = ON
#else
#pragma config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
#endif
#endif

/* Volatile output keeps all updates observable in both languages. */
volatile uint32_t sink;
#ifdef HOST_BENCH
#define BENCH_MAIN(work) int main(void) { work(); printf("%lu\n", (unsigned long)sink); return 0; }
#else
#define BENCH_MAIN(work) void main(void) { work(); __asm("global bench_done"); __asm("bench_done:"); for (;;) {} }
#endif
#endif
