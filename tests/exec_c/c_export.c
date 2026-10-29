/* C calling back into Basic: integers, Float, a String and a Word passed ByRef. */
extern unsigned int Square(unsigned char x);
extern void Accum(unsigned int v);
extern float Half(float f);
extern unsigned long Mix(unsigned char a, unsigned int b, unsigned long c);
extern void Fill(char *s);
extern void AddTo(unsigned int *p, unsigned char k);

/* Locals, an array and pointers live across the calls into Basic. */
unsigned int run(unsigned char n) {
    unsigned char i;
    unsigned int s = 0;
    unsigned char arr[8];
    unsigned char *p = arr;
    for (i = 0; i < 8; i++) arr[i] = 0;
    for (i = 0; i < n; i++) {
        *p++ = i + 1;
        s += Square(i);
        Accum(s);
    }
    return s + arr[0] + arr[n - 1];
}
float fl(float x) { return Half(x) * 3; }
unsigned long mixit(void) { return Mix(7, 1000, 100000); }
unsigned int strc(void) {
    char buf[17];
    Fill(buf);
    return buf[0] + (unsigned int)buf[1] * 256;
}
unsigned int addto(void) {
    unsigned int v = 1000;
    AddTo(&v, 5);
    AddTo(&v, 6);
    return v;
}
