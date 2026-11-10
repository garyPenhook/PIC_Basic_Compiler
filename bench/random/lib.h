/* C port of the basil library routines the random programs use: lib/adc.bas, lib/serial.bas,
 * lib/eeprom.bas and lib/bits.bas, branch for branch for the PIC18F27Q10 and the PIC16F18346.
 * The library's Const values (folded by basil) are #defines here; the register writes and the
 * order of operations are the library's. */
#define FOSC_HZ _XTAL_FREQ
#define BAUD 115200UL
#define BRG ((FOSC_HZ + BAUD * 2) / (BAUD * 4) - 1)

/* ---- adc */
static uint8_t lastCh;
#if defined(_18F27Q10)
#define EE_SIZE 1024u
/* AdcM = 32, AdcAcq = 5 at 64 MHz (lib/adc.bas SetClock). */
static void SetClock(void) { ADCLK = 31; ADACQ = 5; }
static void AdcInit(void) {
    ADCON0 = 0; ADCON1 = 0; ADCON2 = 0; ADCON3 = 0; ADCAP = 0; ADPRE = 0; ADACT = 0; ADREF = 0;
    SetClock();
    lastCh = 255;
    ADCON0 = 132;
}
static uint16_t Convert(void) {
    ADCON0 |= 1;
    while (ADCON0 & 1) {}
    return (uint16_t)(ADRESL | ((uint16_t)ADRESH << 8));
}
static uint16_t AdcRead(uint8_t ch) {
    ch &= 63;
    if (ch != lastCh) {
        ADPCH = ch;
        Convert();          /* first conversion after a channel change dropped (erratum 1.4.4) */
        lastCh = ch;
    }
    return Convert();
}
#else
#define EE_SIZE 256u
/* AdcN = 32 at 32 MHz: ADCS code 2. */
static void SetClock(void) { ADCON1 = (uint8_t)((ADCON1 & 143) | (2 << 4)); }
static void AdcInit(void) {
    ADCON0 = 0; ADCON1 = 128; ADACT = 0;
    SetClock();
    lastCh = 255;
    ADCON0 = 1;
}
static uint16_t Convert(void) {
    ADCON0 |= 2;
    while (ADCON0 & 2) {}
    return (uint16_t)(ADRESL | ((uint16_t)ADRESH << 8));
}
static uint16_t AdcRead(uint8_t ch) {
    ch &= 63;
    if (ch != lastCh) {
        ADCON0 = (uint8_t)((ch << 2) | 1);
        __delay_us(5);
        lastCh = ch;
    }
    return Convert();
}
#endif
static uint16_t AdcReadAvg(uint8_t ch, uint8_t count) {
    uint16_t sum = 0;
    uint8_t i = 0;
    while (i < count) { sum += AdcRead(ch); i++; }
    if (count > 0) return sum / count;
    return 0;
}
static uint16_t AdcMillivolts(uint16_t raw, uint16_t vrefMv) {
    return (uint16_t)((uint32_t)raw * vrefMv / 1023);
}

/* ---- serial */
#if defined(_18F27Q10)
static void SerialInit(void) {
    ANSELC &= (uint8_t)~0x80; TRISC |= 0x80; TRISC &= (uint8_t)~0x40;
    RC6PPS = 9; RX1PPS = 23;
    SP1BRGL = (uint8_t)BRG; SP1BRGH = (uint8_t)(BRG >> 8);
    BAUD1CON = 8; TX1STA = 36; RC1STA = 144;
}
#define TX_READY (PIR3 & 0x10)
#define RX_READY (PIR3 & 0x20)
#else
static void SerialInit(void) {
    ANSELC &= (uint8_t)~0x20; TRISC |= 0x20; TRISC &= (uint8_t)~0x10;
    RC4PPS = 20; RXPPS = 21;
    SP1BRGL = (uint8_t)BRG; SP1BRGH = (uint8_t)(BRG >> 8);
    BAUD1CON = 8; TX1STA = 36; RC1STA = 144;
}
#define TX_READY (PIR1 & 0x10)
#define RX_READY (PIR1 & 0x20)
#endif
static void SerialWriteByte(uint8_t b) {
    while (!TX_READY) {}
    TX1REG = b;
}
static void SerialWrite(const char *s) {
    uint8_t i = 0, c;
    for (;;) {
        c = (uint8_t)s[i];
        if (c == 0) break;
        SerialWriteByte(c);
        i++;
    }
}
static void SerialNewLine(void) { SerialWriteByte(13); SerialWriteByte(10); }
static void SerialWriteWord(uint16_t v) {
    uint8_t started = 0, digit;
    uint16_t d = 10000;
    while (d > 0) {
        digit = 0;
        while (v >= d) { v -= d; digit++; }
        if (digit > 0 || started || d == 1) { SerialWriteByte((uint8_t)(48 + digit)); started = 1; }
        if (d == 10000) d = 1000;
        else if (d == 1000) d = 100;
        else if (d == 100) d = 10;
        else if (d == 10) d = 1;
        else d = 0;
    }
}
static void SerialWriteHex(uint8_t v) {
    uint8_t h = v >> 4;
    if (h > 9) h += 7;
    SerialWriteByte((uint8_t)(48 + h));
    h = v & 15;
    if (h > 9) h += 7;
    SerialWriteByte((uint8_t)(48 + h));
}
static uint8_t SerialRead(void) {
    while (!RX_READY) {
        if (RC1STA & 2) { RC1STA &= (uint8_t)~0x10; RC1STA |= 0x10; }
    }
    return RC1REG;
}

/* ---- eeprom */
#if defined(_18F27Q10)
static void SetAddr(uint16_t addr) { NVMADRU = 49; NVMADRH = (uint8_t)(addr >> 8); NVMADRL = (uint8_t)addr; }
static uint8_t EepromRead(uint16_t addr) {
    uint8_t r = 255;
    if (addr < EE_SIZE) {
        SetAddr(addr);
        NVMCON1 |= 1;
        while (NVMCON1 & 1) {}
        r = NVMDATL;
    }
    return r;
}
static uint8_t EepromWrite(uint16_t addr, uint8_t value) {
    uint8_t ie, r = 0;
    if (addr < EE_SIZE) {
        if (EepromRead(addr) != value) {
            NVMDATL = value;
            ie = INTCON & 0x80;
            INTCON &= (uint8_t)~0x80;
            NVMCON0 |= 0x80;
            NVMCON2 = 85; NVMCON2 = 170;
            NVMCON1 |= 0x10;
            if (ie) INTCON |= 0x80;
            while (NVMCON1 & 0x10) {}
            NVMCON0 &= (uint8_t)~0x80;
            PIR7 &= (uint8_t)~0x20;
        }
        if (EepromRead(addr) == value) r = 1;
        NVMCON0 &= (uint8_t)~0x10;
    }
    return r;
}
#else
static void SetAddr(uint16_t addr) { NVMADRH = 112; NVMADRL = (uint8_t)addr; }
static uint8_t EepromRead(uint16_t addr) {
    uint8_t r = 255;
    if (addr < EE_SIZE) {
        SetAddr(addr);
        NVMCON1 = 64;
        NVMCON1 |= 1;
        while (NVMCON1 & 1) {}
        NVMCON1 = 0;
        r = NVMDATL;
    }
    return r;
}
static uint8_t EepromWrite(uint16_t addr, uint8_t value) {
    uint8_t ie, r = 0;
    if (addr < EE_SIZE) {
        if (EepromRead(addr) != value) {
            NVMDATL = value;
            ie = INTCON & 0x80;
            NVMCON1 = 68;
            INTCON &= (uint8_t)~0x80;
            NVMCON2 = 85; NVMCON2 = 170;
            NVMCON1 |= 2;
            if (ie) INTCON |= 0x80;
            while (NVMCON1 & 2) {}
            NVMCON1 = 0;
            PIR2 &= (uint8_t)~0x10;
        }
        if (EepromRead(addr) == value) r = 1;
    }
    return r;
}
#endif
static uint16_t EepromReadWord(uint16_t addr) {
    return (uint16_t)(EepromRead(addr) + EepromRead(addr + 1) * 256u);
}

/* ---- bits */
static uint8_t GetBit(uint32_t v, uint8_t n) { return ((uint8_t)(v >> n) & 1) != 0; }
static uint8_t SetBit(uint8_t v, uint8_t n) { if (n < 8) v |= (uint8_t)(1 << n); return v; }
static uint8_t Rol(uint8_t v) { return (uint8_t)((v << 1) | (v >> 7)); }
