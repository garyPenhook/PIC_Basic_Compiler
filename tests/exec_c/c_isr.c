/* Uses FSR0/FSR1, PROD, TBLPTR and TABLAT (a const table, an array, 16x16 multiplies), so an interrupt
   that did not save what it touches would corrupt the result. */
static const unsigned char rom[16] = {3, 141, 59, 26, 53, 58, 97, 93, 23, 84, 62, 64, 33, 83, 27, 95};
static unsigned char ram[16];
unsigned long scramble(unsigned int x, unsigned char n) {
    unsigned long acc = x;
    unsigned char i, j;
    for (i = 0; i < n; i++) {
        for (j = 0; j < 16; j++) ram[j] = rom[(j + i) & 15] ^ (unsigned char)(acc >> (j & 7));
        for (j = 0; j < 16; j += 2) acc += (unsigned int)ram[j] * ram[j + 1] + ((unsigned long)ram[j] << 8);
        acc ^= acc >> 5;
    }
    return acc;
}
