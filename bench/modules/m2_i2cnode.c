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

static uint8_t ready, last_status;
static uint8_t i2c_buf[8];

static void i2c_init(void){
  SSP1CON1 = 0;
  TRISC |= 0x18; ANSELC &= (uint8_t)~0x18;
  SSP1CLKPPS = 19; SSP1DATPPS = 20;
  RC3PPS = 15; RC4PPS = 16;
  SSP1ADD = 159; SSP1CON2 = 0; SSP1CON3 = 0; SSP1STAT = 128;
  PIR3bits.SSP1IF = 0; PIR3bits.BCL1IF = 0;
  SSP1CON1 = 40; ready = 1; last_status = 0;
}
static uint8_t wait_if(void){
  uint16_t n = 0;
  while(n < 60000){
    if(PIR3bits.BCL1IF){ PIR3bits.BCL1IF = 0; return 2; }
    if(PIR3bits.SSP1IF){ PIR3bits.SSP1IF = 0; return 0; }
    n++;
  }
  return 1;
}
static uint8_t wait_idle(uint8_t msk){
  uint16_t n = 0;
  while(n < 60000){
    if(PIR3bits.BCL1IF){ PIR3bits.BCL1IF = 0; return 2; }
    if((SSP1CON2 & msk) == 0) return 0;
    n++;
  }
  return 1;
}
static uint8_t condition(uint8_t msk){
  uint8_t r = wait_idle(31);
  if(r == 0){ PIR3bits.SSP1IF = 0; SSP1CON2 |= msk; r = wait_idle(msk); }
  return r;
}
static uint8_t i2c_start(void){ uint8_t r = 4; if(ready) r = condition(1); last_status = r; return r; }
static uint8_t i2c_restart(void){ uint8_t r = 4; if(ready) r = condition(2); last_status = r; return r; }
static uint8_t i2c_stop(void){ uint8_t r = 4; if(ready) r = condition(4); last_status = r; return r; }
static uint8_t i2c_send(uint8_t b){
  uint8_t r = 4;
  if(!ready){ last_status = r; return r; }
  r = wait_idle(31);
  if(r == 0){
    PIR3bits.SSP1IF = 0; SSP1CON1bits.WCOL = 0; SSP1BUF = b;
    if(SSP1CON1bits.WCOL){ SSP1CON1bits.WCOL = 0; r = 1; }
    else { r = wait_if(); if(r == 0 && SSP1CON2bits.ACKSTAT) r = 3; }
  }
  last_status = r; return r;
}
static uint8_t i2c_receive(uint8_t ack){
  uint8_t v = 0;
  last_status = 4;
  if(!ready) return 0;
  last_status = wait_idle(31);
  if(last_status == 0){ PIR3bits.SSP1IF = 0; SSP1CON2bits.RCEN = 1; last_status = wait_if(); }
  if(last_status == 0){
    v = SSP1BUF; SSP1CON2bits.ACKDT = ack ? 0 : 1; last_status = condition(16);
  }
  return v;
}
static uint8_t i2c_open(uint8_t ctl, uint8_t reg){
  uint8_t r = i2c_start();
  if(r == 0) r = i2c_send(ctl);
  if(r == 0) r = i2c_send(reg);
  return r;
}
static uint8_t i2c_read_regs(uint8_t addr, uint8_t reg, uint8_t n){
  uint8_t i, s, r = 5;
  if(n == 0 || n > 8){ last_status = r; return r; }
  r = i2c_open((uint8_t)(addr << 1), reg);
  if(r == 0) r = i2c_restart();
  if(r == 0) r = i2c_send((uint8_t)((addr << 1) | 1));
  i = 0;
  while(r == 0 && i < n){ i2c_buf[i] = i2c_receive(i < n - 1); r = last_status; i++; }
  s = i2c_stop(); if(r == 0) r = s;
  last_status = r; return r;
}
static uint8_t i2c_probe(uint8_t addr){
  uint8_t r = i2c_start();
  if(r == 0) r = i2c_send((uint8_t)(addr << 1));
  (void)i2c_stop();
  last_status = r; return r;
}

void main(void){
  uint8_t addr, found = 0, st = 0, i, good; uint16_t t, sum, avg, stamp;
  ANSELA = 0; ANSELB = 0; ANSELC = 0;
  ser_init();
  TRISB0 = 0;
  i2c_init();
  for(addr = 8; addr <= 119; addr++){
    if(i2c_probe(addr) == 0){
      ser_str("0x"); ser_hex(addr); ser_nl();
      if(found == 0) found = addr;
    }
  }
  T1CON = 0; T1CLK = 1; T1GCON = 0; TMR1L = 0; TMR1H = 0; PIR4bits.TMR1IF = 0; T1CON = (3 & 3) * 16 + 3;
  for(;;){
    if(PIR4bits.TMR1IF){
      PIR4bits.TMR1IF = 0;
      sum = 0; good = 0;
      for(i = 1; i <= 4; i++){
        st = i2c_read_regs(found, 0, 2);
        if(st == 0){ t = i2c_buf[0]; t = (uint16_t)(t * 256 + i2c_buf[1]); sum = (uint16_t)(sum + (t >> 4)); good++; }
      }
      stamp = TMR1L; stamp |= (uint16_t)TMR1H << 8;
      if(good > 0){
        avg = (uint16_t)(sum / good);
        ser_str("T="); ser_word(avg); ser_str(" @"); ser_word(stamp); ser_nl();
        LATB0 = (avg > 400);
      } else {
        ser_str("ERR"); ser_hex(st); ser_nl();
        LATB0 = 1;
      }
    }
  }
}
