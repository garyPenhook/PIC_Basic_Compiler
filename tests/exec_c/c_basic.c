unsigned char cnt;
unsigned char bump(void) { return ++cnt; }
unsigned int add(unsigned char a, unsigned int b) { return b + a; }
long mix(int a, long b, unsigned char c) { return b - a + c; }
void setit(unsigned char v) { cnt = v; }
unsigned char seed = 7;
unsigned char table[20];
unsigned int fill(unsigned char n) {
    unsigned char i;
    unsigned int s = 0;
    for (i = 0; i < n; i++) { table[i] = i * 3 + seed; s += table[i]; }
    return s;
}
