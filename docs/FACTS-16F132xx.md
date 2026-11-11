# Facts: PIC16F13214 / 13215 / 13224 / 13225 / 13244 / 13245 (enhanced mid-range core)

Read from DS40002686B (PIC16F13214/15/24/25/44/45 data sheet, PDF page numbers) and the silicon errata DS80001213B through the pic-docs server. The core, the instruction set,
the interrupt and the stack are those of the PIC16F17126/46 (`docs/FACTS-16F1714x.md`); the code generator is the same one (`pic16e`). The peripheral set is closer to the
PIC16F17126/46 than to the PIC16F13145 family (`docs/FACTS-16F1314x.md`): 16-bit PWM, two EUSART, Timer3/Timer4, secondary oscillator, data EEPROM; and it adds the CLB, HLVD and ACT.
The data sheet's own heading calls the family "PIC16F13276" in places (the larger parts, 13226/13246/13254..13276, are listed in its Table 2 as not included and are not described here).

## Parts (Table 1 p.1, Table 9-1 p.41, DS80001213B Table 1 p.1)

| Part | Pins | I/O | Program flash | SRAM | Data EEPROM | Ports | ADC channels (ext/int) | Device ID |
|---|---|---|---|---|---|---|---|---|
| PIC16F13214 | 8 | 6 | 4K words | 512 | 256 | A (RA0-RA2, RA4, RA5; RA3 is MCLR, input only) | 5/5 | 3130h |
| PIC16F13215 | 8 | 6 | 8K words | 1024 | 256 | A | 5/5 | 3135h |
| PIC16F13224 | 14 | 12 | 4K words | 512 | 256 | A, C (RC0-RC5) | 5/5 | 3131h |
| PIC16F13225 | 14 | 12 | 8K words | 1024 | 256 | A, C | 11/5 | 3136h |
| PIC16F13244 | 20 | 18 | 4K words | 512 | 256 | A, B (RB4-RB7), C (RC0-RC7) | 11/5 | 3132h |
| PIC16F13245 | 20 | 18 | 8K words | 1024 | 256 | A, B, C | 17/5 | 3137h |

- Table 1 gives the flash as 7K and 14K bytes: 4096 and 8192 words of 14 bits.
- Reset vector 0000h, interrupt vector 0004h (9.1 p.41), 16-level stack (Fig. 9-1 p.42). User IDs 8000h-8003h, revision ID 8005h, device ID 8006h (8.3, 8.4 p.25). **Seven** configuration
  words at 8007h-800Dh (8.1 p.23; 8.5.1-8.5.7 p.26-36). The data sheet disagrees with itself: 8.1 says "eight Configuration Words" and Table 15-2 p.171 says "Configuration Words 1-5,
  8007h-800Bh"; the pack and the register chapters agree on seven, which is what the device files use (`devices/16F132xx.expect.toml` says so).
- Data EEPROM 256 bytes, programmer address F000h-F0FFh (Table 9-2 p.45, Table 15-2 p.171). **Software reaches it through NVMREGS = 1 and NVMADRH:NVMADRL = 70h:address** (15.2.2, Examples 15-5..15-7
  p.173-177), or read-only through the FSRs at 7000h-70FFh (9.6.4 p.65): the same scheme as the PIC16F17126/46, so the `eeprom` module is the PIC16F171xx one.
- NVMCON1 (p.180): RD bit 0, WR 1, WREN 2, WRERR 3, FREE 4, LWLO 5, NVMREGS 6. Unlock 55h, AAh to NVMCON2 then WR (15.2.2.2 p.174). Program flash rows are 32 words (FREE description p.180).
- RAM is up to 80 bytes of GPR in each bank plus 16 bytes of common RAM (9.2.4 p.48-50).
- `_ram` and `_eeprom` in `#if` give 512 or 1024 and 256.

## Peripherals as the library uses them

- PPS (Table 18-1 p.206, Table 18-2 p.207): output codes TX1/CK1 13h, DT1 15h, TX2/CK2 16h, DT2 18h, C1OUT 19h, C2OUT 1Ah, SCL1/SCK1 1Bh, SDA1/SDO1 1Ch, CCP1 09h, CCP2 0Ah,
  PWM1S1P1 0Bh, PWM1S1P2 0Ch, PWM2S1P1 0Dh, PWM2S1P2 0Eh. Input registers take `PORT[5:3] | PIN[2:0]` (A = 000, B = 001, C = 010). Parts of 20 leads or fewer route any pin (18.2 p.205).
  Reset selections on an 8-pin part: RX1PPS = RA1, CK1PPS = RA0, RX2PPS = RA1 ('b000 001), SSP1CLKPPS = RA1, SSP1DATPPS = RA2.
- OSC (chapter 11): OSCFRQ.FRQ 0..5 = 1, 2, 4, 8, 16, 32 MHz (p.112); NOSC 110 = HFINTOSC, NDIV 0000..1001 = 1:1 .. 1:512 (Tables 11-2, 11-3 p.99); OSCCON3.ORDY bit 4 (p.110);
  OSCSTAT.HFOR bit 6 (p.113). A secondary oscillator exists (NOSC 100). Config RSTOSC 110 = HFINTOSC at 1 MHz (p.26).
- PCON0 (p.86): STKOVF 7, STKUNF 6, WDTWV 5, RWDT 4, RMCLR 3, RI 2, POR 1, BOR 0: as the PIC16F17126/46. WDTCON0 SEN bit 0, PS bits 5:1 (pack).
- Interrupt flags (pack, matches the PIC16F17146 layout): PIR0 TMR0IF bit 5; PIR1 TMR1IF 6, TMR1GIF 7; PIR2 TMR2IF 2; PIR4 TX1IF 6, RC1IF 7; PIR5 TX2IF 0, RC2IF 1, SSP1IF 2, BCL1IF 3.
- Timer1 clock sources (Table 23-4 p.271): pin 0, FOSC/4 1, FOSC 2, HFINTOSC 3, LFINTOSC 4, SFINTOSC 5, MFINTOSC 500 kHz 6, MFINTOSC 32 kHz 7, SOSC 8, EXTOSC 9, CLKR 10, Timer0 11,
  Timer1/3 overflow 12/13, CLC 14-17, CLB 18-21. Gate sources (Table 23-5 p.272): pin 0, Timer0 1, Timer2 3, Timer4 5, CCP1 7, CCP2 8, PWM1S1P1 9, PWM1S1P2 10, PWM2S1P1 11, PWM2S1P2 12,
  C1 18, C2 19. Timer2 reset sources (Table 24-4 p.294): pin 0, Timer4 2, CCP1 4, CCP2 5, PWM1S1P1 6, PWM1S1P2 7, PWM2S1P1 8, PWM2S1P2 9, C1 14, C2 15.
- ADC (chapter 32): 10 bits. ADPCH (Table 32-6 p.508): RA0-RA2 0-2, ADCG1 3, RA4 and RA5 4-5, RB4-RB7 12-15 (20-pin), RC0-RC7 16-23 (RC0-RC5 not on 8-pin; RC6, RC7 20-pin), VSS 58,
  temperature indicator 59, DAC1 60, FVR buffer 1 62, buffer 2 63. ADCLK.CS 6 bits, FOSC/(2 (n + 1)) (p.506); ADREF.PREF 00 VDD, 10 VREF+, 11 FVR (p.507); ADACQ and ADPRE 13 bits in clocks
  of FOSC or ADCRC (p.509-510). **TAD 0.5-9 us** with FOSC as the clock (AD20 p.610), 2 us typical for ADCRC (AD20A). The errata list nothing for the ADC, so the PIC16F13145 family's 2 us floor
  (its erratum 1.1.1) does not apply. CPON resets to 01 (CPCON p.565).
- PWM (chapter 27): two 16-bit PWM modules, two outputs each (slice S1: P1, P2). PWMxCLK.CLK 0010 = FOSC (p.325); PWMxPR 16 bits, PWMxCPRE prescale n + 1 (p.327-328); PWMxCON EN bit 7, LD bit 2 (p.332);
  PWMxS1CFG POL2 bit 7, POL1 bit 6, MODE 000 = left aligned (p.333); PWMxS1P1/P2 16 bits (p.334-335); PWMLOAD / PWMEN mirror bits 1:0 (p.336-337). The `pwm` module's 16-bit branch applies as on the PIC16F17126/46.
- CCP1 and CCP2 (chapter 25, 10-bit PWM mode too) exist but the `pwm` module does not use them on this family (as on the PIC16F17126/46).
- Pins (Table 3-1 p.12ff): RA0-RA2, RA4, RA5 on every part; RC0-RC5 on the 14- and 20-pin parts; RB4-RB7, RC6, RC7 on the 20-pin parts only.
- One MSSP (SCL1/SCK1, SDA1/SDI1, SS1 in Table 18-1) and two EUSART (TX1/RX1/CK1, TX2/RX2/CK2) on every part.

## Errata (DS80001213B, revision A0 silicon)

- **1.1.1 CCP compare toggle mode (MODE = 0001) does not work** (the output may toggle randomly or not at all); no work around. The library never uses compare mode, so nothing to apply;
  a program that sets `CCPxCON` to compare-toggle itself gets this behaviour.
- There is **no fetch erratum** (the PIC16F13145 family's 1.3.1): no NOP is added at 0000h or 0004h and no NOPs follow `sleep`. The compiler's rule (`codegen16`) names the PIC16F131xx parts only.
- No data sheet clarifications (2.1).

## Not confirmed

- Nothing was run on a real part; the simulator (MDB) models the part from the pack, and has no ADC conversion or bus traffic.
- The CLB, HLVD, ACT and CLKR have no library support.
