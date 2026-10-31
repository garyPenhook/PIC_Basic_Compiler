# Facts: PIC16F15213 / 15214 / 15223 / 15224 / 15243 / 15244 (enhanced mid-range core, second-generation PPS parts with a fixed clock)

Read from DS40002195E (PIC16F15213/14/23/24/43/44, PDF page numbers) and from the silicon errata DS80000918K, through the pic-docs server. The core, the instruction set, the
interrupt and the stack are those of the PIC16F17126/46 (`docs/FACTS-16F1714x.md`); this file lists what differs. The code generator is the same one (`pic16e`). The other PIC16F152xx
parts (PIC16F15225, 15245, 15254 .. 15276) are in a different data sheet and are not described here.

## Parts (Table 1 p.1, Table 9-1 p.32)

| Part | Pins | I/O | Program flash | SRAM | Ports | ADC channels | Device ID |
|---|---|---|---|---|---|---|---|
| PIC16F15213 | 8 | 6 | 2K words | 256 | A (RA0-RA2, RA4, RA5; RA3 is MCLR, input only) | 5 | 30E3h |
| PIC16F15214 | 8 | 6 | 4K words | 512 | A | 5 | 30E6h |
| PIC16F15223 | 14 | 12 | 2K words | 256 | A, C (RC0-RC5) | 9 | 30E4h |
| PIC16F15224 | 14 | 12 | 4K words | 512 | A, C | 9 | 30E7h |
| PIC16F15243 | 20 | 18 | 2K words | 256 | A, B (RB4-RB7), C (RC0-RC7) | 12 | 30E5h |
| PIC16F15244 | 20 | 18 | 4K words | 512 | A, B, C | 12 | 30E8h |

- Table 1 gives the flash as 3.5K and 7K bytes: that is 2048 and 4096 words of 14 bits. One MSSP, one EUSART, two CCP, two 10-bit PWM, Timer0 (8 or 16 bit), Timer1 (16 bit), Timer2 (8 bit with
  hardware limit), a 10-bit ADC, the fixed voltage reference and a charge pump. **No data EEPROM**, no DAC, no comparator, no CLC, no secondary oscillator, no second MSSP or EUSART.
- Reset vector 0000h, interrupt vector 0004h, 16-level hardware stack (Fig. 9-1 p.33, 7.2). Five configuration words at 8007h-800Bh, four user ID words at 8000h-8003h, revision ID 8005h,
  device ID 8006h (8.1, 8.4, 8.5 p.22; Register 8.7.1 p.30).
- RAM is 80 bytes of GPR in each of the first banks plus 16 bytes of common RAM, as on the other PIC16F1xxxx parts.
- Memory Access Partition (MAP): the flash can be split into application, boot and storage-area blocks by CONFIG4 (BBEN, SAFEN, BBSIZE, WRTAPP, WRTB, WRTSAF); every one of them is off at reset
  (CONFIG words erased = 3FFFh), so the self-write of the `flashwrite` module reaches all of the flash unless the program sets them.
- `devices/16F152xx.expect.toml` carry the numbers above, so `scripts/check-devices.sh` cross-checks the generated files against the data sheet.

## Peripherals as the library uses them

- **Clock (chapter 11, Table 11-1 p.77):** RSTOSC is the only source selection; the family has **no clock switching** (p.78), no OSCCON1/OSCCON2/OSCCON3 and no divider. RSTOSC = 00 is the HFINTOSC at
  32 MHz (config name `HFINTOSC_32MHZ`, COSC = 00, FRQ = 5), 10 the HFINTOSC at 1 MHz (`HFINTOSC_1MHZ`, FRQ = 0), 01 the LFINTOSC, 11 the external clock (`EXTOSC`). OSCCON holds only COSC<1:0>
  (bits 5:4, read only). With an HFINTOSC setting the speed is OSCFRQ.FRQ (p.85): 0..5 = 1, 2, 4, 8, 16, 32 MHz. OSCSTAT.HFOR is bit 6.
- PCON0 (p.73): STKOVF, STKUNF, RWDT, RMCLR, RI, POR, BOR; **no WDTWV bit** (bit 5 unimplemented), so `System.SysResetCause` has no cause 5 there. PCON1 has nMEMV (memory execution violation).
- **PPS** (chapter 18, Table 18-1 and 18-2 p.148): output codes RxyPPS: CCP1 01h, CCP2 02h, PWM3 03h, PWM4 04h, **TX1/CK1 05h**, DT1 06h, SCL1/SCK1 07h, SDA1/SDO1 08h, TMR0 09h. Input registers
  (xxxPPS, 18.8.1 p.151) take PORT<5:3> | PIN<2:0>, so RA0..RA5 = 0..5, RB4..RB7 = 12..15, RC0..RC7 = 16..23: INTPPS, T0CKIPPS, T1CKIPPS, T1GPPS, T2INPPS, CCP1PPS, CCP2PPS, SSP1CLKPPS, SSP1DATPPS,
  SSP1SSPPS, **RX1PPS**, CK1PPS, ADACTPPS. The register names are those of the PIC16F17126/46 (`RX1PPS`), not those of the PIC16F183xx (`RXPPS`). RA3 has no RxyPPS (input only); there is no RA6/RA7 or port B bits 0-3.
- Flags (12.9): TMR0IF PIR0 bit 5; ADIF PIR1 bit 0, SSP1IF bit 1, BCL1IF bit 2, **TX1IF bit 3, RC1IF bit 4, TMR1IF bit 5, TMR2IF bit 6**, CCP1IF bit 7; **TMR1GIF PIR2 bit 5**, NVMIF bit 6, CCP2IF bit 7.
  The enables are the same bits of PIE0, PIE1 and PIE2. `_has(PIR1.TMR1IF)` is true here as on the PIC16F13145 family, but the bit numbers differ, so the library tells this part apart with `_has(ADCON1.PREF)`
  (the PIC16F183xx calls the field ADPREF).
- Timer0: as the PIC16F17126/46 (T0CON0, T0CON1 with CS 010 = FOSC/4, TMR0H buffered in 16-bit mode, period in TMR0H in 8-bit mode; p.159).
- Timer1 (20.11, p.172-176): T1CON = CKPS<5:4> | SYNC | RD16 | ON, T1GCON = GE | GPOL | GTM | GSPM | GGO | GVAL, T1CLK (CS<4:0>: 0 pin, 1 FOSC/4, 2 FOSC, 3 HFINTOSC, 4 LFINTOSC, 5 SFINTOSC 1 MHz, 6 MFINTOSC 500 kHz,
  7 MFINTOSC 32 kHz, 8 TMR0) and T1GATE (GSS<4:0>: 0 pin, 1 TMR0, 2 TMR2 postscaled, 3 CCP1, 4 CCP2, 5 PWM3, 6 PWM4). RD16 exists (bit 1), so the 16-bit read takes TMR1L first.
- Timer2 (chapter 21, p.194-197): T2CON = ON | CKPS<6:4> (prescalers 1 to 128) | OUTPS<3:0>; T2HLT (MODE<4:0> as Table 21-1 p.181), T2CLKCON (CS 001 = FOSC/4), T2RST (RSEL: 0 pin, 1 CCP1, 2 CCP2, 3 PWM3, 4 PWM4), T2PR, T2TMR.
- ADC (chapter 27, 10 bits, p.318-331): ADCON0 = CHS<7:2> | GO (bit 1) | ON (bit 0); ADCON1 = FM | CS<6:4> | PREF<1:0> (00 VDD, 10 VREF+ pin, 11 FVR); ADACT, ADRESH:ADRESL. CS = 000 FOSC/2, 100 /4, 001 /8, 101 /16, 010 /32, 110 /64,
  011 and 111 ADCRC. Channels RA0, RA1, RA2, RA4, RA5 = 0, 1, 2, 4, 5, RB5..RB7 = 13..15, RC2..RC5 = 18..21, **VSS 27, FVR buffer 1 30**; RB4, RC0, RC1, RC6, RC7 have no channel. No temperature indicator, no DAC channel.
  TAD 0.5 to 9 us with the FOSC clock source (AD20, Table 32-12 p.378), acquisition 2 us typical (AD23). No ADACQ: acquisition is a software delay. FVRCON = FVREN | FVRRDY (always 1) | ADFVR<1:0> (p.316).
- Charge pump (chapter 28, p.333-335): CPCON = CPON<7:6> | CPT | CPRDY; **CPON resets to 00 (off)**, 01 = on while the ADC is enabled and VDD < 4.6 V.
- NVM (chapter 15, p.107-124): NVMADRH:NVMADRL, NVMDATH:NVMDATL, NVMCON1 = NVMREGS (6) | LWLO (5) | FREE (4) | WRERR (3) | WREN (2) | WR (1) | RD (0), NVMCON2 unlock 55h/AAh then WR (the CPU stalls until it is done). Rows of 32 words
  with 32 write latches (Fig. 15-4 p.114), erased words read 3FFFh, a write needs an erased word. The same flow as the PIC16F17126/46 and the PIC16F183xx; NVMADR bit 15 is undefined while WR = 1 (Register 15.2.1), and the module does not read it.
- PWM (chapters 22 and 23): CCP1 and CCP2 in PWM mode and the 10-bit PWM3/PWM4, all on Timer2 (Table 22-1), period (T2PR + 1) * 4 * Tosc * prescale (Equation 22-1 p.204); CCPxCON = EN | OUT | FMT | MODE (156 = EN, left aligned,
  PWM), PWMxCON = EN | OUT | POL (bit 4). There is no CCPTMRS or PWMTMRS.
- MSSP1: `SSP1CON1/2/3`, `SSP1STAT`, `SSP1ADD`, as on the PIC16F17126/46; SSPM = 1000 I2C master, 1010 SPI master with SSP1ADD >= 1. RB4I2C and RB6I2C (20-pin parts) or RC0I2C and RC1I2C (14-pin parts) are the I2C pad controls (the 8-pin parts have none).
- EUSART1: `TX1STA`, `RC1STA`, `BAUD1CON`, `SP1BRGL/H`, as on the PIC16F13145 family; serial uses RC4 (TX) and RC5 (RX), RA4 and RA5 on the 8-pin parts.

## Errata (DS80000918K, revisions up to A9; the issues in bold apply to the current silicon)

- **1.2.1 CCP PWM duty cycle** with T2PR = 0 and a Timer2 prescaler other than 1:1 (PWM resolution of two bits). No workaround exists, and the `pwm` module cannot reach the case: `PwmInit` chooses the smallest prescale
  that gives T2PR + 1 <= 256, so T2PR = 0 only comes with prescale 1:1 (for 1 MHz at 4 MHz or more); any other prescale gives T2PR >= 128.
- **1.3.1 EUSART double byte transmit:** a byte written to TX1REG just as the shift register empties can be sent twice. `Serial.SerialWriteByte` follows workaround method 2 on this part: it waits for TRMT (shift register empty)
  instead of TXIF. Characters still go out back to back (the byte is written within a few cycles of the stop bit).
- **1.4.1 MSSP I2C start/stop flags** can be set when I2C is enabled. The `i2c` module keeps SCIE and PCIE clear, clears SSP1IF before each step and never reads the S and P bits, so it is not affected.
- **1.5.1 low-voltage programming** is not possible when VDD is below the BORV level with BOR enabled (a programming-tool matter).
- Fixed in later silicon (open on earlier revisions only, DS80000918K Table 2 p.2): 1.1.1 self-write above 85 C with VDD above 5.3 V (A3 only), 1.6.1 WDT reset outside Sleep (A3, A5, A6), 1.7.1 waking from Sleep (A3 to A7). The library does not use Sleep or the WDT.
- The compiler's PIC16F131xx first-fetch workaround (`FetchNop`) does not apply to these parts.
