# Facts: PIC16(L)F15313 / 15323 / 15324 / 15325 / 15344 / 15345 / 15354 / 15355 / 15356 / 15375 / 15376 / 15385 / 15386 (enhanced mid-range core, PPS parts with the PIC16F183xx oscillator and the PIC18F27Q10 interrupt flags)

Read through the pic-docs server (PDF page numbers) from five data sheets, which share one Table 1 (p.3) and one register layout, and from their silicon errata:

| Data sheet | Parts | Errata |
|---|---|---|
| DS40001897C | PIC16(L)F15313, 15323 (8 and 14 pin) | none published (the Microchip page lists none) |
| DS40001889E | PIC16(L)F15324, 15344 (14 and 20 pin) | DS80000728D |
| DS40001865F | PIC16(L)F15325, 15345 (14 and 20 pin) | DS80000721D |
| DS40001853E | PIC16(L)F15354, 15355 (28 pin) | DS80000717K |
| DS40001866E | PIC16(L)F15356, 15375, 15376, 15385, 15386 (28, 40, 44 and 48 pin) | DS80000725F |

The core, the instruction set, the interrupt and the stack are those of the other enhanced mid-range parts (`docs/FACTS-16F1714x.md`); this file lists what differs. The code generator is the same one (`pic16e`). Every part exists as a PIC16F (2.3 to 5.5 V)
and a PIC16LF (1.8 to 3.6 V) variant with the same registers; the device files carry both (`16F15313` and `16LF15313` and so on), 26 in all. The PIC16F15313 family is the part of the PIC16(L)F153xx line that the Microchip page calls "PIC16(L)F153XX".

## Parts (Table 1 p.3, DEVID Register 5-6 p.84, 88, 88, 84, 110)

| Part | I/O | Program flash | SRAM | ADC channels | EUSART / MSSP | Device ID (F, LF) |
|---|---|---|---|---|---|---|
| PIC16(L)F15313 | 6 | 2K words | 256 | 5 | 1 / 1 | 30BEh, 30BFh |
| PIC16(L)F15323 | 12 | 2K words | 256 | 11 | 1 / 1 | 30C0h, 30C1h |
| PIC16(L)F15324 | 12 | 4K words | 512 | 11 | 2 / 1 | 30C2h, 30C3h |
| PIC16(L)F15325 | 12 | 8K words | 1024 | 11 | 2 / 1 | 30C6h, 30C7h |
| PIC16(L)F15344 | 18 | 4K words | 512 | 17 | 2 / 1 | 30C4h, 30C5h |
| PIC16(L)F15345 | 18 | 8K words | 1024 | 17 | 2 / 1 | 30C8h, 30C9h |
| PIC16(L)F15354 | 25 | 4K words | 512 | 24 | 2 / 2 | 30ACh, 30ADh |
| PIC16(L)F15355 | 25 | 8K words | 1024 | 24 | 2 / 2 | 30AEh, 30AFh |
| PIC16(L)F15356 | 25 | 16K words | 2048 | 24 | 2 / 2 | 30B0h, 30B1h |
| PIC16(L)F15375 | 36 | 8K words | 1024 | 35 | 2 / 2 | 30B2h, 30B3h |
| PIC16(L)F15376 | 36 | 16K words | 2048 | 35 | 2 / 2 | 30B4h, 30B5h |
| PIC16(L)F15385 | 44 | 8K words | 1024 | 43 | 2 / 2 | 30B6h, 30B7h |
| PIC16(L)F15386 | 44 | 16K words | 2048 | 43 | 2 / 2 | 30B8h, 30B9h |

- The I/O count includes the input-only RA3 (MCLR). Every part has two CCP, four 10-bit PWM (PWM3 to PWM6), Timer0 (8 or 16 bit), Timer1 (16 bit), Timer2 (8 bit with hardware limit), four CLC, one CWG, one NCO, one 5-bit DAC, the fixed voltage reference,
  a temperature indicator, a zero-cross detector, the windowed watchdog, the Memory Access Partition and the Device Information Area; one comparator on the PIC16(L)F15313 and two on the others. **No data EEPROM** (the 224 bytes of storage area flash
  are part of the program flash), no DMA.
- Reset vector 0000h, interrupt vector 0004h, 16-level hardware stack (Fig. 4-1 p.28, 32, 32, 25, 49). Five configuration words at 8007h-800Bh, four user ID words at 8000h-8003h, revision ID 8005h, device ID 8006h (Table 13-3 p.165, 169, 170, 167, 193).
- Ports (from the device files): A (RA0-RA5, RA3 input only; RA0-RA7 on the 28-pin and larger parts), B (RB4-RB7 on the 20-pin parts, RB0-RB7 on the 28-pin and larger parts), C (RC0-RC5 on the 14-pin parts, RC0-RC7 above), D (RD0-RD7 on the PIC16(L)F15375/76/85/86),
  E (RE3 only, the MCLR input, on the 28-pin parts; RE0-RE3 on the PIC16(L)F15375/76/85/86), F (RF0-RF7 on the PIC16(L)F15385/86). The 8-pin PIC16(L)F15313 has port A only.
- `devices/*.expect.toml` carry the numbers above, so `scripts/check-devices.sh` cross-checks the generated files against the data sheets (the device IDs are in the comments and were compared by hand: the pack's values equal the data sheets').

## Peripherals as the library uses them

- **Clock (chapter 9, DS40001897C p.100-114):** the oscillator is that of the PIC16F183xx and the Q10: OSCCON1 = NOSC<2:0> (bits 6:4) | NDIV<3:0>, OSCCON2 = COSC | CDIV (read only), OSCCON3 (CSWHOLD, ORDY, NOSCR), OSCSTAT (HFOR bit 6), OSCFRQ.HFFRQ<2:0>.
  **HFFRQ 0..6 = 1, 2, 4, 8, 12, 16, 32 MHz**, 7 is reserved (Register 9-6 p.114); NOSC 110 is the HFINTOSC at that speed, 001 the HFINTOSC with the 2x PLL (from 16 MHz to 32 MHz), 101 the LFINTOSC, 111 EXTOSC, 010 EXTOSC with the 4x PLL; NDIV divides by 1 to 512
  (Tables 9-1 and 9-2 p.111). RSTOSC (Register 5-1 p.76) is **HFINT32** (000: HFINTOSC at 32 MHz, OSCFRQ 110), HFINTPLL (001: 16 MHz through the PLL), EXT4X (010), HFINT1 (110: OSCFRQ 010, CDIV 0010), LFINT (101), EXT1X (111), and on the PIC16(L)F15354 and larger parts SOSC (100, from the device files).
  OSCCON1 is read only while `CSWEN = OFF`, so `Config CSWEN = ON` is needed for a run-time switch. The simulator does not model these registers (they read 0).
- **PCON0** has nWDTWV (bit 5), nRWDT, nRMCLR, nRI, nPOR, nBOR, STKUNF, STKOVF; PCON1 has nMEMV. WDTCON0 = WDTPS<4:0> (bits 5:1) | SEN (bit 0), WDTCON1 = WDTCS | WINDOW.
- **PPS** (chapter 15, DS40001889E p.195-201): output codes RxyPPS (5 bits): CLC1..4 = 01h..04h, CWG1A..D = 05h..08h, CCP1 09h, CCP2 0Ah, PWM3 0Bh, PWM4 0Ch, PWM5 0Dh, PWM6 0Eh, **TX1/CK1 0Fh**, DT1 10h, TX2/CK2 11h, DT2 12h, C1OUT 13h,
  C2OUT 14h, **SCK1/SCL1 15h, SDO1/SDA1 16h**, TMR0 19h, NCO1OUT 1Ah, CLKR 1Bh (Table 15-4 p.199 of DS40001889E, the PIC16(L)F15324 and 15344; the codes of the MSSP2 outputs on the 28-pin and larger parts were not needed and are not listed here). Input registers (xxxPPS, Register 15-1 p.200) take PORT<5:3> | PIN<2:0>:
  RA0..RA5 = 0..5, RB4..RB7 = 12..15 (RB0..RB7 = 8..15 on the 28-pin and larger parts), RC0..RC7 = 16..23 (Table 15-3 p.197): INTPPS, T0CKIPPS, T1CKIPPS, T1GPPS, T2INPPS, CCP1PPS, CCP2PPS, CWG1PPS, CLCIN0..3PPS, ADACTPPS, SSP1CLKPPS, SSP1DATPPS,
  SSP1SSPPS, **RX1DTPPS and TX1CKPPS**, RX2DTPPS and TX2CKPPS. The register names differ from both the PIC16F183xx (`RXPPS`) and the PIC16F152xx (`RX1PPS`) parts. Only RB1, RB2, RC3 and RC4 have the I2C and SMBus input buffers (15.3 note p.198).
  The RxyPPS registers are contiguous from RA0PPS (1F10h) in pin order for ports A to E, which module `pinio`, `i2c`, `spi` and `pwm` rely on (checked in the device files); **port F is not**: RF0PPS is at 1E38h (7736), not 1F38h, so `pwm` writes
  RF0PPS .. RF7PPS by name. The PPS input register values are PORT<5:3> | PIN<2:0> with RD = 0x18..0x1F, RE0..RE2 = 0x20..0x22 and RF = 0x28..0x2F (Table 15-4 p.239 of DS40001866E), i.e. the pin numbers 0..47 of module `pinio`.
- **Which ports each signal reaches** (the bullets in Tables 15-1 to 15-7, which the text extraction of the PDF drops; read from the page images): on the **8- to 20-pin parts (PIC16(L)F15313, 15323, 15324, 15325, 15344, 15345) every output and every input reaches every
  pin of the part** (DS40001897C p.186-187, 190; DS40001889E p.195-196, 199; DS40001865F p.200). On the **28-pin and larger parts each signal reaches two ports only**:

  | Signal | PIC16(L)F15354/55/56 (28 pin) | PIC16(L)F15375/76 | PIC16(L)F15385/86 |
  |---|---|---|---|
  | CCP1, CCP2 (outputs 09h, 0Ah) | B, C | B, C | **C, F** |
  | PWM3, PWM4 (outputs 0Bh, 0Ch) | B, C | B, D | B, D |
  | SCK1/SCL1, SDO1/SDA1 (15h, 16h) and SSP1CLKPPS, SSP1DATPPS | B, C | B, C | B, C |
  | TX1/CK1 (0Fh) | B, C | B, C | C, F |
  | RX1DTPPS | B, C | B, C | B, C, F |
  | TX2/CK2 (11h), RX2DTPPS | B, C | B, D | B, D |

  (DS40001853E Tables 15-1 p.197 and 15-3 p.200, DS40001866E Tables 15-1 to 15-3 p.236-238 and 15-5 to 15-7 p.241-243.) The library follows them: `pwm` takes the masks of CCP1/CCP2 and PWM3/PWM4 from the part, `spi` and `i2c` accept pins 8..23 only on the 28-pin and larger
  parts, `serial2` uses RB6 and RB7 (the reset selections of TX2CKPPS and RX2DTPPS, valid on every one of those parts), and `serial` keeps RC4 and RC5, which every part allows.
- **Flags**: TMR0IF PIR0 bit 5; ADIF PIR1 bit 0; SSP1IF PIR3 bit 0, BCL1IF bit 1, **TX1IF bit 4, RC1IF bit 5**, TX2IF bit 6, RC2IF bit 7; **TMR1IF PIR4 bit 0, TMR2IF bit 1**; TMR1GIF PIR5 bit 0. The enables are the same bits of PIE0, PIE1, PIE3, PIE4. The
  layout of PIR3 and PIR4 is that of the PIC18F27Q10 for the EUSART and the timers, so `_has(PIR3.TX1IF)` is true on both; the library tells this family apart with `_has(RX1DTPPS)` (true on the PIC16F152xx too, which is tested first through `_has(ADCON1.PREF)`).
- Timer0: as the PIC16F17126/46 (T0CON0, T0CON1; period in TMR0H in 8-bit mode). Timer1 (Registers 26-3, 26-4 p.287-288, T1CON = CKPS<5:4> | nSYNC | RD16 | ON): T1CLK CS<3:0>: 0 T1CKIPPS, 1 FOSC/4, 2 FOSC, 3 HFINTOSC, 4 LFINTOSC, 5 MFINTOSC 500 kHz,
  6 MFINTOSC 32 kHz, 8 CLKR, 9 Timer0 overflow, 10..13 LC1..LC4; T1GATE GSS<4:0>: 0 T1GPPS, 1 Timer0, 2 Timer2 postscaled, 3 CCP1, 4 CCP2, 5 PWM3, 6 PWM4, 7 PWM5, 8 PWM6, 9 NCO1, 10 C1 (synchronised), 11 C2, then ZCD1 and LC1..LC4 (the data sheet's
  code for ZCD1 is printed as 00100, a typo for 01100). Timer2 (chapter 27): T2CON = ON | CKPS<2:0> (1 to 128) | OUTPS<3:0>, T2HLT, T2CLKCON (CS 0001 = FOSC/4), T2RST RSEL: 0 T2INPPS, 1 CCP1, 2 CCP2, 3 PWM3, 4 PWM4, 5 PWM5, 6 PWM6, 7 C1,
  8 C2, 9 ZCD1, 10..13 LC1..LC4 (Register 27-4 p.313).
- ADC (chapter 20, 10 bits, DS40001866E p.280-283): ADCON0 = CHS<5:0> (bits 7:2) | GO/DONE (bit 1) | ADON; ADCON1 = ADFM | ADCS<2:0> (bits 6:4) | ADPREF<1:0> (00 VDD, 10 VREF+ pin, 11 FVR); ADACT. CS = 000 FOSC/2, 100 /4, 001 /8, 101 /16, 010 /32, 110 /64,
  011 and 111 FRC. Channels: RA0..RA7 = 0..7, RB0..RB7 = 8..15, RC0..RC7 = 16..23, RD0..RD7 = 24..31, RE0..RE2 = 32..34, RF0..RF7 = 40..47, **AVSS 59, temperature indicator 60, DAC1 61, FVR buffer 1 62, buffer 2 63**. TAD 1 to 9 us (AD20, Table 37-13
  p.492 of DS40001889E). No ADACQ: the acquisition time is a software delay. No charge pump, no ADNREF.
- NVM (chapter 13, p.158-172): NVMADRH:NVMADRL, NVMDATH:NVMDATL, NVMCON1 = NVMREGS (6) | LWLO (5) | FREE (4) | WRERR (3) | WREN (2) | WR (1) | RD (0), NVMCON2 unlock 55h/AAh then WR. Rows of 32 words with 32 write latches (ERSIZ and WLSIZ, DS40001889E p.92;
  Table 13-4 p.172), erased words read 3FFFh. NVMADRH has bits 0 to 6 only.
- PWM (CCP and PWM chapters): CCP1 and CCP2 in PWM mode and the 10-bit PWM3 to PWM6, all on Timer2; CCPxCON = EN | OUT | FMT | MODE (156 = EN, left aligned, PWM), PWMxCON = EN | OUT | POL (bit 4). There is no CCPTMRS or PWMTMRS. The library offers
  channels 1 to 4 (CCP1, CCP2, PWM3, PWM4).
- MSSP1 (`SSP1CON1/2/3`, `SSP1STAT`, `SSP1ADD`) and EUSART1 (`TX1STA`, `RC1STA`, `BAUD1CON`, `SP1BRGL/H`, `TX1REG`), EUSART2 and MSSP2 on the parts that have them; as on the other enhanced mid-range parts.

## Errata (the issues in bold apply to the library)

- **DS80000728D 5.1, DS80000717K 5.1 Timer0**: with FOSC/4 as the clock, clearing T0ASYNC may stop TMR0H counting in 16-bit mode / cause incorrect behaviour; workaround: set T0ASYNC. `Timer0Start` and `Timer0Start16` set it (T0CON1 bit 4) on this family.
- **DS80000725F 5.1 EUSART (PIC16(L)F15356/75/76/85/86, silicon A1 and A2)**: a byte written to TX1REG just as the shift register empties can be sent twice; workaround 2 waits for TRMT. `Serial.SerialWriteByte` and `Serial2.Serial2WriteByte` do that on those parts only (the other four errata documents
  list no EUSART issue).
- **DS80000721D 1.1, DS80000717K 1.1, DS80000725F 1.1 ADC**: the FVR as positive reference increases the missing codes; workaround: TAD of 8 us, or VDD as reference. `Adc.AdcRefFvr` selects the slowest FOSC/n (n up to 64), which reaches 8 us only at FOSC <= 8 MHz; the
  PIC16(L)F15313/23 and 15324/44 errata do not list the issue, but the ADC is the same, so the rule applies to all.
- DS80000728D 3.1 and DS80000721D 7.1 NVM: WRERR may be set again by a Reset after an interrupted operation (the same as DS80000666H item 4.2 for the PIC16F183xx); `Flashwrite` clears NVMCON1 and reports success only by the read-back.
- MSSP SPI client mode (DS80000721D 6.1, DS80000728D 2.1): SSPBUF corruption; the modules are hosts only, so they are not affected. WWDT in DOZE mode and with SOSC (DS80000728D 4.1, DS80000721D 3.1/3.2, DS80000717K 3.1, DS80000725F 3.1): not used.
  FVR accuracy, ADC offset error and VDDMIN of the LF parts are specifications only. CLKR first output pulse (DS80000728D 6.1, DS80000721D 9.1): not used.
- Data breakpoints on the upper banks (DS80000721D 2.1, DS80000717K 2.1, DS80000725F 2.1) are a debugger matter.
