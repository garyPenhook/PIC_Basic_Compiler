#include <xc.h>
#include <stdint.h>
#pragma config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
#define _XTAL_FREQ 64000000UL

static uint8_t last_ch = 255;
static void adc_init(void){
  ADCON0 = 0; ADCON1 = 0; ADCON2 = 0; ADCON3 = 0; ADCAP = 0; ADPRE = 0; ADACT = 0; ADREF = 0;
  ADCLK = 32; ADACQ = 5; last_ch = 255; ADCON0 = 132;
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

static uint16_t pwm_steps; static uint8_t pwm_period, pwm_ckps, pwm_ready, pwm_active;
static uint8_t pwm_init(uint32_t hz){
  uint32_t n, d; uint8_t e = 0, found = 0;
  if(pwm_active || hz == 0 || hz > 1000000UL) return 0;
  while(e < 8 && !found){
    d = (4UL * hz) << e; n = (64000000UL + d / 2) / d;
    if(n >= 1 && n <= 256) found = 1; else e++;
  }
  if(!found) return 0;
  pwm_ckps = e; pwm_period = (uint8_t)(n - 1); pwm_steps = (uint16_t)(n * 4); pwm_ready = 1;
  return 1;
}
static void pwm_duty_reg(uint8_t ch, uint16_t d){
  uint8_t hi, lo;
  if(d > 1023) d = 1023;
  hi = (uint8_t)(d >> 2); lo = (uint8_t)((d & 3) << 6);
  if(ch == 1){ CCPR1L = lo; CCPR1H = hi; } else { CCPR2L = lo; CCPR2H = hi; }
}
static uint8_t pwm_start(uint8_t ch, uint8_t pin, uint16_t duty){
  uint8_t sh;
  if(!pwm_ready) return 0;
  /* pin is RC1 / RC2 (ch 2 / 1): digital output */
  TRISC |= (uint8_t)(1u << (pin & 7)); ANSELC &= (uint8_t)~(1u << (pin & 7));
  if(ch == 1) RC2PPS = 5; else RC1PPS = 6;
  sh = (uint8_t)((ch - 1) * 2);
  CCPTMRS = (uint8_t)((CCPTMRS & ~(3u << sh)) | (1u << sh));
  if(ch == 1) CCP1CON = 156; else CCP2CON = 156;
  pwm_duty_reg(ch, duty);
  if(pwm_active == 0){
    T2CON = 0; T2CLKCON = 1; T2HLT = 0; T2RST = 0; T2PR = pwm_period; T2TMR = 0;
    PIR4bits.TMR2IF = 0; T2CON = (uint8_t)(128 + pwm_ckps * 16);
  } else PIR4bits.TMR2IF = 0;
  while(!PIR4bits.TMR2IF){}
  PIR4bits.TMR2IF = 0;
  pwm_active |= (uint8_t)(1u << (ch - 1));
  TRISC &= (uint8_t)~(1u << (pin & 7));
  return 1;
}
static void pwm_percent(uint8_t ch, uint8_t pct){
  if(pct > 100) pct = 100;
  if(pwm_active & (1u << (ch - 1))) pwm_duty_reg(ch, (uint16_t)((uint32_t)pct * pwm_steps / 100));
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

static void shift_out(uint8_t data){
  uint8_t i;
  LATB1 = 0; TRISB1 = 0; TRISB0 = 0;
  for(i = 1; i <= 8; i++){
    LATB0 = (data & 128) != 0; data <<= 1;
    __delay_us(1); LATB1 = 1; __delay_us(1); LATB1 = 0;
  }
}
static void show(uint8_t v){ LATB2 = 0; shift_out(v); LATB2 = 1; }

void main(void){
  uint16_t raw; uint8_t target, cur = 0, saved, ok;
  ANSELA = 0; ANSELB = 0; ANSELC = 0; WPUB = 8;
  TRISB2 = 0; TRISB3 = 1;
  adc_init(); TRISA0 = 1; ANSELA0 = 1;
  ok = pwm_init(20000);
  ok = pwm_start(1, 18, 0);
  ok = pwm_start(2, 17, 0);
  saved = ee_read(0); if(saved <= 100) cur = saved;
  T0CON0 = 0; T0CON1 = (9 & 15) | 64; TMR0H = 124; TMR0L = 0; PIR0bits.TMR0IF = 0; T0CON0 = 128;
  for(;;){
    if(PIR0bits.TMR0IF){
      PIR0bits.TMR0IF = 0;
      raw = adc_read(0);
      target = (uint8_t)(raw / 10); if(target > 100) target = 100;
      if(cur < target) cur++; else if(cur > target) cur--;
      pwm_percent(1, cur); pwm_percent(2, (uint8_t)(100 - cur));
      show(cur);
      if(!PORTBbits.RB3){ if(cur != saved){ ok = ee_write(0, cur); saved = cur; } }
    }
  }
  (void)ok;
}
