/* The XC-DSC call convention from Basic: register holes filled by later arguments, a long that finds no even pair going on the stack,
   a float, a pointer, a byte result, and C calling back into Basic through a chain of Reentrant routines. */
volatile unsigned int ticks;

/* a W0, b W2:W3, c W1, d W4:W5, p W6, e stack (no even pair left), h W7, i and j stack */
long mixed(unsigned char a, long b, int c, float d, int *p, long e, int h, int i, int j) {
    *p = (int)(a + c + h + i + j);
    return b + e + (long)d;
}
signed char sbyt(signed char v, unsigned char w) { return v - w; }
unsigned long sevenlong(unsigned long a, unsigned long b, unsigned long c, unsigned long d) { return a + b + c + d; }
float fmix(float a, int n, float b) { return a * n + b; }

unsigned int tick_c(unsigned int stp) { ticks += stp; return ticks; }

/* C calling Basic with a long and an int on the stack: a W0, b W2:W3, c W4:W5, d W6:W7, f W1, e and g stack */
extern long Sum7(int a, long b, long c, long d, long e, int f, int g);
long call_sum7(void) { return Sum7(1, 100000L, 20000L, 3000L, 70000L, 5, 7); }
