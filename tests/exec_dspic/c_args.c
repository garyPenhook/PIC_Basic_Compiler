/* Float by value, and ByRef arguments: scalars, arrays, strings, structures. */
struct Pt { unsigned int x; unsigned char y; unsigned long z; };

float scale(float v, unsigned char k) { return v * k + 0.5f; }
float half(float v) { return v / 2; }
void swap16(unsigned int *a, unsigned int *b) { unsigned int t = *a; *a = *b; *b = t; }
void incr(unsigned char *p) { ++*p; }
void getf(float *out, float v) { *out = v * 4; }
unsigned int sum(unsigned char *a, unsigned char n) {
    unsigned int s = 0;
    unsigned char i;
    for (i = 0; i < n; i++) s += a[i];
    return s;
}
void fillw(unsigned int *a, unsigned char n) { unsigned char i; for (i = 0; i < n; i++) a[i] = i * 1000; }
unsigned char slen(char *s) { unsigned char n = 0; while (s[n]) n++; return n; }
void upper(char *s) { for (; *s; s++) if (*s >= 'a' && *s <= 'z') *s -= 32; }
void bump_pt(struct Pt *p) { p->x += 1; p->y += 2; p->z += 100000; }
unsigned long sumpt(struct Pt *p) { return p->x + (unsigned long)p->y + p->z; }
unsigned long sumarr(struct Pt *a, unsigned char n) {
    unsigned long s = 0;
    unsigned char i;
    for (i = 0; i < n; i++) s += a[i].x + (unsigned long)a[i].y + a[i].z;
    return s;
}
void fillarr(struct Pt *a, unsigned char n) { unsigned char i; for (i = 0; i < n; i++) { a[i].y = i + 40; a[i].z = 1000UL * i + a[i].y; } }
