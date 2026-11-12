#include <xc.h>
#include <stdint.h>
#pragma config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON

static void ser_init(void){
  ANSELC &= (uint8_t)~0x80; TRISC7 = 1; TRISC6 = 0;
  RC6PPS = 9; RX1PPS = 23;
  SP1BRG = 138; BAUD1CON = 8; TX1STA = 36; RC1STA = 144;
}
static void ser_byte(uint8_t b){ while(!PIR3bits.TX1IF){} TX1REG = b; }
static void ser_str(const char *s){ while(*s) ser_byte((uint8_t)*s++); }
static void ser_nl(void){ ser_byte(13); ser_byte(10); }
static void ser_hex(uint8_t v){
  uint8_t h = v >> 4; if(h > 9) h += 7; ser_byte((uint8_t)(48 + h));
  h = v & 15; if(h > 9) h += 7; ser_byte((uint8_t)(48 + h));
}
static void ser_word(uint16_t v){
  uint16_t d = 10000; uint8_t started = 0, digit;
  while(d){
    digit = 0; while(v >= d){ v -= d; digit++; }
    if(digit || started || d == 1){ ser_byte((uint8_t)(48 + digit)); started = 1; }
    d = (d == 10000) ? 1000 : (d == 1000) ? 100 : (d == 100) ? 10 : (d == 10) ? 1 : 0;
  }
}

static uint8_t spi_ready, spi_status;
static uint8_t spi_init(void){
  SSP1CON1 = 0;
  TRISC3 = 0; ANSELC &= (uint8_t)~0x08;
  TRISC4 = 1; ANSELC &= (uint8_t)~0x10;
  SSP1CLKPPS = 19; SSP1DATPPS = 20; RC3PPS = 15;
  TRISC5 = 0; ANSELC &= (uint8_t)~0x20; RC5PPS = 16;
  SSP1ADD = 1; SSP1STAT = 64; SSP1CON3 = 0;
  SSP1CON1 = 10; SSP1CON1 = 10 | 32;
  spi_ready = 1; spi_status = 0; return 1;
}
static void spi_off(void){
  SSP1CON1 = 0; RC3PPS = 0; RC5PPS = 0; spi_ready = 0;
}
static uint8_t spi_xfer(uint8_t b){
  uint16_t n; uint8_t r = 0;
  spi_status = 4;
  if(!spi_ready) return 0;
  SSP1CON1bits.WCOL = 0; SSP1BUF = b; spi_status = 1;
  for(n = 0; n < 60000; n++){
    if(SSP1STAT & 1){ r = SSP1BUF; spi_status = 0; break; }
  }
  return r;
}

static uint8_t ee_read(uint16_t addr){
  if(addr >= 1024) return 255;
  NVMADRU = 49; NVMADRH = (uint8_t)(addr >> 8); NVMADRL = (uint8_t)addr;
  NVMCON1bits.RD = 1; while(NVMCON1bits.RD){}
  return NVMDATL;
}
static uint8_t ee_write(uint16_t addr, uint8_t v){
  uint8_t ie, ok = 1;
  if(addr >= 1024) return 0;
  if(ee_read(addr) != v){
    NVMDATL = v; ie = INTCONbits.GIE;
    INTCONbits.GIE = 0; NVMCON0bits.NVMEN = 1;
    NVMCON2 = 0x55; NVMCON2 = 0xAA; NVMCON1bits.WR = 1;
    if(ie) INTCONbits.GIE = 1;
    while(NVMCON1bits.WR){}
    NVMCON0bits.NVMEN = 0; PIR7bits.NVMIF = 0;
    if(ee_read(addr) != v) ok = 0;
  }
  NVMCON0bits.NVMERR = 0;
  return ok;
}

static uint8_t id[3], i, v;
static uint16_t sum;

static void read_id(void){
  LATB0 = 0; (void)spi_xfer(0x9F);
  id[0] = spi_xfer(255); id[1] = spi_xfer(255); id[2] = spi_xfer(255);
  LATB0 = 1;
}
static void dump(uint16_t addr){
  LATB0 = 0;
  (void)spi_xfer(3); (void)spi_xfer((uint8_t)(addr >> 8)); (void)spi_xfer((uint8_t)addr); (void)spi_xfer(0);
  sum = 0;
  for(i = 0; i <= 31; i++){
    v = spi_xfer(255); sum = (uint16_t)(sum + v); ser_hex(v); ser_str(" ");
  }
  LATB0 = 1; ser_nl();
}

void main(void){
  uint16_t t0, t1; uint8_t ok;
  ANSELA = 0; ANSELB = 0; ANSELC = 0;
  ser_init();
  TRISB0 = 0; LATB0 = 1;
  ok = spi_init();
  T1CON = 0; T1CLK = 1; T1GCON = 0; TMR1L = 0; TMR1H = 0; PIR4bits.TMR1IF = 0; T1CON = (0 & 3) * 16 + 3;
  read_id();
  for(i = 0; i <= 2; i++) ser_hex(id[i]);
  ser_nl();
  for(i = 0; i <= 2; i++) ok = ee_write((uint16_t)(16 + i), id[i]);
  t0 = TMR1L; t0 |= (uint16_t)TMR1H << 8;
  dump(0);
  t1 = TMR1L; t1 |= (uint16_t)TMR1H << 8;
  ser_str("SUM="); ser_word(sum); ser_str(" CLK="); ser_word((uint16_t)(t1 - t0)); ser_nl();
  spi_off();
  (void)ok;
  for(;;){}
}
