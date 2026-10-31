# Facts: PIC16F18313 / 18323 / 18324 / 18325 / 18326 / 18344 / 18345 / 18346 (enhanced mid-range core, first-generation PPS parts)

Read from DS40001799F (PIC16(L)F18313/18323), DS40001800E (18324/18344), DS40001795K (18325/18345) and DS40001839E (18326/18346), and from the silicon errata
DS80000666H, DS80000667E, DS80000668L and DS80000709H, through the pic-docs server. Page numbers are PDF pages; where the four data sheets differ only in page
numbers the one of DS40001839E is given. The LF parts (PIC16LF183xx, 1.8 to 3.6 V) share the data sheets and the registers; the device files describe the F parts.
The core, the instruction set, the interrupt and the stack are those of the PIC16F17126/46 (`docs/FACTS-16F1714x.md`); this file lists what differs. The code
generator is the same one (`pic16e`).

## Parts (Family Types table p.3 of every data sheet)

| Part | Pins | I/O | Program flash | SRAM | EEPROM | Ports | MSSP | CCP | PWM | Comparators | CWG | CLC | Timers (8/16-bit) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| PIC16F18313 | 8 | 6 | 2K words | 256 | 256 | A (RA0-RA2, RA4, RA5; RA3 is MCLR, input only) | 1 | 2 | 2 | 1 | 1 | 2 | 2/1 |
| PIC16F18323 | 14 | 12 | 2K words | 256 | 256 | A, C (RC0-RC5) | 1 | 2 | 2 | 2 | 1 | 2 | 2/1 |
| PIC16F18324 | 14 | 12 | 4K words | 512 | 256 | A, C | 1 | 4 | 2 | 2 | 2 | 4 | 4/3 |
| PIC16F18325 | 14 | 12 | 8K words | 1024 | 256 | A, C | 2 | 4 | 2 | 2 | 2 | 4 | 4/3 |
| PIC16F18326 | 14 | 12 | 16K words | 2048 | 256 | A, C | 2 | 4 | 2 | 2 | 2 | 4 | 4/3 |
| PIC16F18344 | 20 | 18 | 4K words | 512 | 256 | A, B (RB4-RB7), C (RC0-RC7) | 1 | 4 | 2 | 2 | 2 | 4 | 4/3 |
| PIC16F18345 | 20 | 18 | 8K words | 1024 | 256 | A, B, C | 2 | 4 | 2 | 2 | 2 | 4 | 4/3 |
| PIC16F18346 | 20 | 18 | 16K words | 2048 | 256 | A, B, C | 2 | 4 | 2 | 2 | 2 | 4 | 4/3 |

- One EUSART (no second one), one 5-bit DAC, a 10-bit ADC, NCO, DSM, clock reference. The data sheets call the 256 bytes at F000h-F0FFh "EEPROM" (p.1, Table 11-3 p.134);
  the pack calls it data EEPROM too. It is written byte by byte through NVMREG with an implicit erase, so it is true data EEPROM for the `eeprom` module.
- Reset vector 0000h, interrupt vector 0004h (Fig. 4-1: 799F p.22, 800E p.26, 795K p.28, 839E p.28), 16-level hardware stack (3.2, 4.4). Four configuration words at
  8007h-800Ah, four user ID words at 8000h-8003h (Table 11-3). Device IDs (Register 5-5): 18313 3066h, 18323 3067h, 18324 303Ah, 18344 303Bh, 18325 303Eh, 18345 303Fh,
  18326 30A4h, 18346 30A5h (the F parts; the LF parts are 2 higher).
- RAM is 80 bytes of GPR in each of the first banks plus 16 bytes of common RAM, as on the other PIC16F1xxxx parts.
- `devices/16F183xx.expect.toml` carry the numbers above, so `scripts/check-devices.sh` cross-checks the generated files against the data sheets.

## Peripherals as the library uses them

- PPS output codes (RxyPPS, Register 13-2 p.163; the 18313/18323 sheet has fewer sources but the same codes where it has them): PWM5 02h, PWM6 03h, CLC1..4 04h..07h, CWG1A..D 08h..0Bh,
  CCP1 0Ch, CCP2 0Dh, CCP3 0Eh, CCP4 0Fh, CWG2A..D 10h..13h, **TX/CK 14h, DT 15h**, C1 16h, C2 17h, **SCK1/SCL1 18h, SDO1/SDA1 19h**, SCK2/SCL2 1Ah, SDO2/SDA2 1Bh, TMR0 1Ch, NCO1 1Dh.
  Input registers (xxxPPS, Register 13-1 p.162) take RA0..RA5 = 0..5, RB4..RB7 = 12..15, RC0..RC7 = 16..23 (RXPPS, SSP1CLKPPS, SSP1DATPPS, T1CKIPPS ...). Any output can go to any pin of the part.
  The register names differ from the PIC16F17126/46: `RXPPS` (not `RX1PPS`), `TXPPS`. `_has(ADCON0.CHS)` selects the 183xx branch in the library.
- EUSART1: `TX1STA`, `RC1STA`, `BAUD1CON`, `SP1BRGL/H`; TXIF and RCIF are PIR1 bits 4 and 5. Serial uses RC4 (TX) and RC5 (RX), RA4 and RA5 on the 8-pin part.
- Oscillator: OSCFRQ.HFFRQ (Register 7-6 p.93): 0 = 1, 1 = 2, 3 = 4, 4 = 8, 5 = 12, 6 = 16, 7 and above = 32 MHz with NOSC = 110; with NOSC = 000 (HFINTOSC with the 2x PLL) 4, 5, 6 = 16, 24, 32 MHz.
  `RSTOSC = HFINT32` (not `HFINTOSC_32MHz`) is the 32 MHz power-up setting; `HFINT1`, `LFINT`, `SOSC`, `EXT1X`, `EXT4X` are the others. OSCCON2 holds COSC and CDIV (read only).
- PCON0 (Table 6-5 p.77): STKOVF, STKUNF, RWDT, RMCLR, RI, POR, BOR; **no WDTWV bit** (bit 5 unimplemented), so `System.SysResetCause` has no cause 5 there.
- Flags: Timer0 PIR0 bit 5, Timer1 PIR1 bit 0 (gate bit 7), Timer2 PIR1 bit 1, SSP1IF PIR1 bit 3, BCL1IF PIR1 bit 2, NVMIF PIR2 bit 4.
- Timer0: as the PIC16F17126/46 (T0CON0, T0CON1 with T0CS 010 = FOSC/4; TMR0H buffered read in 16-bit mode, period register in 8-bit mode) [26.1].
- Timer1 (Registers 27-1, 27-2 p.293-294): T1CON = TMR1CS<1:0> (00 FOSC/4, 01 FOSC, 10 T1CKI pin or SOSC, 11 LFINTOSC) | T1CKPS | T1SOSC | T1SYNC | TMR1ON; **no RD16 bit** (bit 1 is unimplemented although 27.4
  describes it), so the 16-bit read takes TMR1H twice. T1GCON holds the gate source T1GSS<1:0> (00 pin, 01 Timer0 overflow, 10 C1, 11 C2).
- Timer2 (Register 28-1 p.299): T2CON = T2OUTPS<3:0> (bits 6-3) | TMR2ON (bit 2) | T2CKPS<1:0> (prescalers 1, 4, 16, 64); `TMR2`, `PR2`; no clock, mode or reset registers.
- ADC (chapter 22, 10 bits): ADCON0 = CHS<5:0> | GO/DONE | ADON, ADCON1 = ADFM | ADCS<2:0> | ADNREF | ADPREF<1:0> (Registers 22-1, 22-2); channels RA0..RA2, RA4, RA5 = 0..2, 4, 5, RB4..RB7 = 12..15, RC0..RC7 = 16..23,
  VSS 60, temperature 61, DAC 62, FVR 63. ADCS = 000 FOSC/2, 100 /4, 001 /8, 101 /16, 010 /32, 110 /64 (Table 22-1); TAD 1..9 us (AD20 in Table 35-13). No ADACQ: acquisition is a software delay (4.62 us worked
  example, Equation 22-1). FVRRDY always reads 1 (Register 16-1).
- NVM (chapter 11): `NVMADRH:NVMADRL`, `NVMDATH:NVMDATL`, `NVMCON1` = RD, WR, WREN, WRERR, FREE, LWLO, NVMREGS (bits 0-6), `NVMCON2` unlock 55h/AAh then WR, no NOPs after WR (11.4.2). Rows of 32 words with 32 write latches (Table 11-1).
  EEPROM: NVMREGS = 1, address 7000h + byte address (11.4.3) written as NVMADRH = 70h; **NVMADRH bit 7 is unimplemented and reads 1** (Register 11-4), so it reads back as F0h.
- PWM (chapters 18 and 29): the 10-bit PWM5/PWM6 and CCP1..CCP4 in PWM mode on Timer2/4/6; period (PR2 + 1) * 4 * Tosc * prescale (Equation 18-1); CCPTMRS (reset 55h) and PWMTMRS (reset 05h) select Timer2 with 01 (Registers 29-5, 18-4).
- MSSP1: `SSP1CON1/2/3`, `SSP1STAT`, `SSP1ADD`, as on the PIC16F17126/46; SSPM = 1000 I2C master, 1010 SPI master with SSP1ADD >= 1 (Register 30-2 p.362). MSSP2 on the 18325/18326/18345/18346 is not used by the library.

## Errata (latest silicon of each family)

- **DS80000666H (18313/18323, revision A6):** 4.2 WRERR is set again by a Reset after an interrupted write until a write succeeds (the `eeprom` and `flashwrite` modules report success by the read-back and clear NVMCON1);
  3.4 SPI slave mode corrupts the transmit register when SCK arrives during an SFR or RAM write (no slave mode in the library); 5.1 FVR accuracy below -20 C; 5.3 NVM access on LF devices below 2.0 V at 25 C or less.
  Fixed in A6 (open on A3/A4 only): OSCTUNE reset value 0x20 (1.1), the 32 MHz clock not locking when HFFRQ = 0111 or 1xxx is used with NOSC = 110 (1.2: use RSTOSC = HFINT32 and HFFRQ = 0110 with NOSC = 000),
  FSCM with 4x PLL (1.3, none), PLLR bit (1.4), TX pin low with TXEN = 0 (2.1), SPI slave data corruption in Sleep (3.1-3.3), NVMREG write below 2.2 V at -40 C on LF (4.1).
- **DS80000667E (18324/18344, A6):** 1.2.2 WRERR as above; 1.3.1 FVR accuracy; 1.3.3 NVM on LF; 1.5.2 an ADC auto-conversion trigger does not start a conversion in Sleep (not used). The Timer0 FOSC/4 problem
  (1.6.1) and the ADC reference problem with the FVR (1.5.1) are fixed in A6.
- **DS80000668L (18325/18345, A8):** 4.2 WRERR; 5.1 revision ID bit 6; 7.2 FVR accuracy; 7.3 NVM on LF; 8.1 auto-conversion in Sleep. The Sleep wake-up problem (2.1) and the PPSLOCK problem in Doze (3.1) are fixed in A7.
- **DS80000709H (18326/18346, A4):** 1.3.1-1.3.3 electrical items only (VDDMIN of LF parts, ADC offset specification, FVR accuracy). The FSCM item and the MSSP2 I2C item concern revision A1.
- None of these needs a code workaround in the compiler or the library beyond the read-back of the NVM writes. The compiler's PIC16F131xx first-fetch workaround (`FetchNop`) does not apply to these parts.
