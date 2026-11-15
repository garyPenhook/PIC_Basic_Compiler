# PIC18(L)F2x/4xK22 fact base (PIC18(L)F23/24/25/26/43/44/45/46K22)

Every fact below was read from a Microchip document and carries its source. Page numbers are PDF pages. Where a simulator was the
evidence, it says so.

* **DS** = PIC18(L)F2X/4XK22 Data Sheet, DS40001412H (539 pp.)
* **ES-25** = PIC18(L)F25/45K22 Rev. A2/A3/A4/A5 Silicon Errata and Data Sheet Clarification, DS80000498K
* **ES-23** = PIC18(L)F23/24/43/44K22 Silicon Errata and Data Sheet Clarification, DS80000512J
* **ES-26** = PIC18(L)F26/46K22 Rev. A2/A4 Silicon Errata and Data Sheet Clarification, DS80000514J
* **PACK** = Microchip device pack `PIC18F-K_DFP 1.17.312`, files `edc/PIC18(L)F<nn>K22.PIC`
* **MDB** = MPLAB X 6.35 simulator; **SIM** = basil-sim 0.2.10 (the picsim repository)

Status key: ✔ verified · ◐ verified, with a caveat in the text.

Parts: the 2x parts have 28 pins (ports A, B, C and RE3 as an input), the 4x parts 40/44 pins (ports A to E). x3 = 8 KB flash / 512 B
RAM, x4 = 16 KB / 768 B, x5 = 32 KB / 1536 B, x6 = 64 KB / 3896 B; 256 bytes of data EEPROM, 1024 on the x6 parts. The PIC18LF parts are listed
beside the PIC18F ones in every table of DS and their device files have the same registers.

## 1. Memory

| Fact | Value | Source |
|---|---|---|
| ✔ Program flash | 8 / 16 / 32 / 64 KB; 21-bit PC; reset vector 0000h, interrupt vectors 0008h and 0018h | DS 5.1 p.64, Fig. 5-1 p.65 |
| ✔ Stack | 31 levels, STKPTR 5 bits, STKFUL/STKUNF; reset on overflow/underflow with STVREN | DS 5.1.2 p.65-66, Register 5-1 p.67 |
| ✔ Data memory | 12-bit addresses, 16 banks; GPR from 000h; on the x6 parts GPR runs to F37h (3896 bytes) | DS 5.4 p.71, Figs. 5-5 to 5-8 p.72-75 |
| ✔ Access Bank | 000h-05Fh RAM, F60h-FFFh SFRs; **F38h-F5Fh are SFRs outside the Access Bank** (ANSELx, CCP3..5, Timer4..6, PMDx, VREFCONx ...) and need BSR | DS Figs. 5-5 to 5-8 note 1 |
| ✔ Configuration | CONFIG1L..CONFIG7H at 300000h-30000Dh (14 bytes); unprogrammed CONFIG1H = 25h (FOSC = ECHPIO6) | DS Table 24-1 p.344 |
| ✔ ID locations | eight bytes, 200000h-200007h | DS 24.6 p.359 |
| ✔ Extended instruction set | XINST (CONFIG4L bit 6): ON = 1 makes Access Bank operands below 60h FSR2-relative; the compiler refuses XINST = ON (E-CONFIG) | DS 5.7.1 p.87, Table 24-1 |
| ◐ Pack masks | the pack's `impl` masks are wrong for this family (PIR3, PIE3, WPUB 0; CCP3CON .. CTMUICON 07h); its `access` letters agree with Table 5-2 (p.79-83), so devgen takes the mask from them for this pack | PACK; checked with picsim `tools/audit/audit_summary.py` |
| ◐ Pack reset values | OSCCON reset is `0011 q000` (IRCF = 011, 1 MHz), the pack says `0110 q000`; TBLPTRU resets to `--00 0000` | DS Register 2-1 p.30, Table 5-2 |

## 2. Interrupts

| Fact | Value | Source |
|---|---|---|
| ✔ Controller | the legacy PIC18 one: GIE/GIEH bit 7, PEIE/GIEL bit 6 of INTCON; entry clears GIE (GIEH/GIEL); RETFIE sets it | DS 9.2, 9.3 p.106, Register 9-1 p.109 |
| ✔ IPEN | RCON bit 7, **not** INTCON bit 5 (that is TMR0IE here); the compiler sets RCON bit 7 for a program with two priorities | DS Register 4-1 p.56, Register 9-1 |
| ✔ Core sources | TMR0IF/IE bits 2/5 of INTCON, priority INTCON2 bit 2; INT0IF/IE bits 1/4 (always high priority); RBIF/IE bits 0/3, INTCON2 bit 0; INT1/INT2 in INTCON3 (IF 0/1, IE 3/4, IP 6/7); PEIE does not gate them | DS Registers 9-1 to 9-3 p.109-111, 9.1 p.106, Fig. 9-1 p.107 |
| ✔ Peripheral flags | PIR1..PIR5: TMR1IF PIR1.0, TMR2IF PIR1.1, CCP1IF PIR1.2, SSP1IF PIR1.3, TX1IF PIR1.4, RC1IF PIR1.5, ADIF PIR1.6; EEIF PIR2.4, BCL1IF PIR2.3; TMR1GIF PIR3.0, TX2IF PIR3.4, RC2IF PIR3.5 | DS Registers 9-4 to 9-8 p.112-116 |
| ✔ Fast register stack | one level; with both priorities the low-priority handler saves WREG/STATUS/BSR in software (as the compiler does) | DS 5.2.1 p.67 |

## 3. Clock, reset and watchdog

| Fact | Value | Source |
|---|---|---|
| ✔ Internal oscillator | HFINTOSC 16 MHz through IRCF: 111 = 16, 110 = 8, 101 = 4, 100 = 2, 011 = 1 MHz (reset), 010 = 500 kHz, 001 = 250 kHz, 000 = 31.25 kHz (INTSRC = 1, MFIOSEL = 0: from the HFINTOSC) | DS Register 2-1 p.30, Register 2-2 p.31, Register 2-3 p.35 |
| ✔ 4x PLL | on the primary clock path only; with FOSC = 100x (INTIO67/INTIO7) OSCTUNE.PLLEN multiplies the internal block (4..16 MHz in): 64 and 32 MHz need FOSC = INTIO67 and SCS = 00 | DS Fig. 2-1 p.26, Table 2-1 p.28, 2.8.2 p.37 |
| ✔ Status | OSTS (OSCCON 3), HFIOFS (OSCCON 2), PLLRDY (OSCCON2 7) | DS Registers 2-1, 2-2. MDB does not model them (they read as written); SIM does |
| ✔ Reset flags | RCON RI 4, TO 3, PD 2, POR 1, BOR 0 (active low); STKPTR STKFUL 7, STKUNF 6; a MCLR Reset sets none; POR and BOR both read 0 after power-on | DS Register 4-1 p.56, Table 4-3 p.62 |
| ✔ Watchdog | 4 ms nominal times WDTPS (CONFIG2H 5:2, 1:1..1:32768); WDTCON has only SWDTEN, effective with WDTEN = 10 (SWON) | DS 24.3 p.354, Register 24-14 p.355 |

## 4. Peripherals the library uses

| Fact | Source |
|---|---|
| Timer0: T0CON = TMR0ON, T08BIT, T0CS, T0SE, PSA, T0PS<2:0> (1:2..1:256); no period register in 8-bit mode; TMR0H buffered in 16-bit mode; shut down in Sleep | DS Register 11-1 p.154, 11.2-11.5 p.155-156 |
| Timer1/3/5: TxCON = TMRxCS<1:0> (00 FOSC/4, 01 FOSC, 10 pin or SOSC), TxCKPS, TxSOSCEN, TxSYNC, TxRD16, TMRxON; TxGCON gate source TxGSS<1:0> (pin, Timer2/4/6 match, C1, C2); T1CKI = RC0, T1G = RB5 | DS Registers 12-1, 12-2 p.166-167, Table 12-2 p.158, Tables 2, 3 p.6-7 |
| Timer2/4/6: TxCON = TxOUTPS<3:0> (6:3), TMRxON (2), TxCKPS<1:0> (1, 4, 16); PRx, TMRx | DS Register 13-1 p.171 |
| EUSART1 TX1 = RC6, RX1 = RC7; EUSART2 TX2/RX2 = RB6/RB7 (28 pins) or RD6/RD7 (40/44 pins); both TRIS bits set, SPEN takes TX; BRG16 = BRGH = 1: baud = FOSC / (4 (n + 1)) | DS Tables 2, 3, 16.1.1.7 p.262, Registers 16-1 to 16-3 |
| ADC: ADCON0 CHS<4:0> is an AN number (AN0..3 = RA0..3, AN4 = RA5, AN5..7 = RE0..2, AN8 = RB2, AN9 = RB3, AN10 = RB1, AN11 = RB4, AN12 = RB0, AN13 = RB5, AN14..19 = RC2..7, AN20..27 = RD0..7), CTMU 29, DAC 30, FVR BUF2 31 (needs > 15 us acquisition); ADCON1 PVCFG/NVCFG; ADCON2 ADFM, ACQT, ADCS (FOSC/2..64 or FRC); TAD 1..25 us | DS Registers 17-1 to 17-3 p.295-297, Table 27-22 p.452 |
| FVR: VREFCON0 = FVREN, FVRST, FVRS<1:0> | DS Register 21-1 p.332 |
| Data EEPROM: EECON1 (EEPGD, CFGS, FREE, WRERR, WREN, WR, RD), EECON2 unlock 55h/AAh, EEADR(H), EEDATA; byte write TDEW 3 ms typical, CPU running, EEIF at the end | DS 7.1-7.4 p.99-101, D175 p.430 |
| Program flash: 64-byte erase and write blocks through TBLPTR; 64 holding registers (FFh after a Reset and after every write) loaded with TBLWT; CPU stalls about 2 ms (TIW) | DS 6.1-6.6 p.90-97, D183 p.430 |
| MSSP1: SCK1/SCL1 = RC3, SDI1/SDA1 = RC4, SDO1 = RC5; MSSP2: RB1/RB2/RB3 (28 pins), RD0/RD1/RD4 (40/44 pins); the Q10's SSPxCON1/STAT/CON2/CON3/ADD bits | DS Tables 2, 3, Registers 15-2 to 15-7 |
| CCP1..CCP5: CCPxCON = PxM (ECCP), DCxB<1:0>, CCPxM<3:0> (11xx PWM; 1110 = PxA active low on CCP1..3); duty CCPRxL:DCxB; CCPTMRS0/1 timer selection (00 = Timer2); pins CCP1 RC2, CCP2 RC1/RB3 (CCP2MX), CCP3 RB5 or RC6/RE0 (CCP3MX), CCP4 RB0/RD1, CCP5 RA4/RE2 | DS Registers 14-1 to 14-4 p.198-201, 14.3 p.180-182, Tables 2, 3 |
| Ports: ANSELA..E reset 1; weak pull-ups on port B only (WPUB, reset FFh, gated by INTCON2.RBPU); no ODCON | DS 10.7 p.148, Registers 9-2, 10-12 p.110, 152 |

## 5. Errata that touch this project

| Item | Effect here | Source |
|---|---|---|
| EUSART asynchronous Start bit missed 1 in 256 unless BRGH = BRG16 = 1 (older silicon) | `serial`, `serial2` always use BRGH = BRG16 = 1 | ES-25 12.1 p.6, ES-23 6.1, ES-26 6.1 |
| EUSART synchronous LSb corruption | not used (asynchronous only) | ES-25 12.2, ES-23 6.2 |
| SPI host with CKE = 0: BF/SSPIF half an SCK early, write collision | `spi` waits one SCK period after a transfer in modes 1 and 3 and repeats a write that sets WCOL (method 1) | ES-25 13.1 p.6, ES-23 7, ES-26 7 (all revisions) |
| ADC GO/DONE stuck (25/45K22 A2, A3) | `adc` gives up after a bounded wait (about 2 ms), clears GO and starts again, twice at most | ES-25 8 p.4 |
| VREFCON0 resets to 00h (25/45K22 A2, A3); reference unstable when cold | `adc` writes all of VREFCON0 in AdcRefFvr | ES-25 1.1, 1.2 p.3 |
| CCP3..CCP5 PWM clock cross-wired with CCP2 (25/45K22 A2, A3) | `pwm` puts every channel on Timer2 | ES-25 7 p.4 |
| Timer1/3/5 asynchronous counter: spurious TMRxIF | `timer` always synchronises (TxSYNC = 0) | ES-25 11 p.5, ES-23 5, ES-26 5 |
| Timer1/3/5 gate with FOSC as clock: 2 LSb resolution | noted for Timer1StartPulse with T1ClkFosc | ES-25 10 p.4, ES-23 4, ES-26 4 |
| FCMEN without IESO misses a clock failure in Sleep | a configuration matter: set IESO with FCMEN | ES-25 5.2 p.3, ES-23 2, ES-26 2 |
| HLVD, CTMU, comparator CxSYNC, HS oscillator start-up, POR current (older silicon) | not used by the library | ES-25 2-6, 9; ES-23 1, 3; ES-26 1, 3 |

## 6. Simulators

| Fact | Source |
|---|---|
| MDB models the K22 peripherals the library uses, except the oscillator status bits (OSTS, HFIOFS, PLLRDY read as written) and the holding registers after a flash write (they read 00h in MDB, FFh in the data sheet; `flashwrite` loads all 64 so it works either way) | MDB (`tests/exec_k22/lib_intosc.bas`, `lib_flashwrite.bas`) |
| basil-sim 0.2.10 models the K22 interrupts, timers, EUSART, MSSP, ADC, EEPROM and flash, CCP PWM on the fixed pins and the oscillator status; its differences from MDB are listed in picsim `docs/FACTS-SIM.md` (D-SIM-12 to D-SIM-14) | SIM |
