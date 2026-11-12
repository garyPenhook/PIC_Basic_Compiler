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
static void ser_word(uint16_t v){
  uint16_t d = 10000; uint8_t started = 0, digit;
  while(d){
    digit = 0; while(v >= d){ v -= d; digit++; }
    if(digit || started || d == 1){ ser_byte((uint8_t)(48 + digit)); started = 1; }
    d = (d == 10000) ? 1000 : (d == 1000) ? 100 : (d == 100) ? 10 : (d == 10) ? 1 : 0;
  }
}

static uint8_t last_ch = 255;
static void adc_init(void){
  ADCON0 = 0; ADCON1 = 0; ADCON2 = 0; ADCON3 = 0; ADCAP = 0; ADPRE = 0; ADACT = 0; ADREF = 0;
  ADCLK = 32; ADACQ = 5; last_ch = 255; ADCON0 = 132;
}
static void adc_pin(uint8_t ch){
  uint8_t m = (uint8_t)(1u << (ch & 7));
  if(ch < 8){ TRISA |= m; ANSELA |= m; }
  else if(ch < 16){ TRISB |= m; ANSELB |= m; }
  else if(ch < 24){ TRISC |= m; ANSELC |= m; }
}
static uint16_t convert(void){
  ADCON0bits.GO = 1; while(ADCON0bits.GO){}
  return (uint16_t)(ADRESL | ((uint16_t)ADRESH << 8));
}
static uint16_t adc_read(uint8_t ch){
  ch &= 63;
  if(ch != last_ch){ ADPCH = ch; (void)convert(); last_ch = ch; }
  return convert();
}
static uint16_t adc_avg(uint8_t ch, uint8_t count){
  uint16_t sum = 0; uint8_t i;
  for(i = 0; i < count; i++) sum += adc_read(ch);
  return count ? (uint16_t)(sum / count) : 0;
}
static uint16_t adc_mv(uint16_t raw, uint16_t vref){ return (uint16_t)((uint32_t)raw * vref / 1023); }

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
static uint8_t ee_write_word(uint16_t addr, uint16_t v){
  uint8_t r = ee_write(addr, (uint8_t)v);
  if(addr < 65535) r &= ee_write((uint16_t)(addr + 1), (uint8_t)(v >> 8)); else r = 0;
  return r;
}

static void report(uint8_t c, uint16_t v){
  ser_str("CH"); ser_word(c); ser_str("="); ser_word(v); ser_nl();
}

void main(void){
  uint8_t slot, ch, ok = 0; uint16_t mv, hi = 0, lo = 65535, addr;
  ANSELA = 0; ANSELB = 0; ANSELC = 0; TRISB = 0;
  ser_init(); adc_init();
  for(ch = 0; ch <= 2; ch++) adc_pin(ch);
  slot = ee_read(1000); if(slot >= 100) slot = 0;
  T0CON0 = 0; T0CON1 = (15 & 15) | 64; TMR0H = 249; TMR0L = 0; PIR0bits.TMR0IF = 0; T0CON0 = 128;
  for(;;){
    if(PIR0bits.TMR0IF){
      PIR0bits.TMR0IF = 0;
      for(ch = 0; ch <= 2; ch++){
        mv = adc_mv(adc_avg(ch, 8), 3300);
        report(ch, mv);
        if(mv > hi) hi = mv;
        if(mv < lo) lo = mv;
        addr = slot; addr = (uint16_t)(addr * 6 + ch * 2);
        ok = ee_write_word(addr, mv);
      }
      slot++; if(slot >= 100) slot = 0;
      ok = ee_write(1000, slot);
      LATB = (uint8_t)(hi >> 4);
      LATC = (uint8_t)((uint8_t)(lo >> 4) | ok);
    }
  }
}
