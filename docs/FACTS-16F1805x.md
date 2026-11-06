# Facts: PIC16F18056 / PIC16F18076 (enhanced mid-range core, PPS parts with a fixed clock, ADCC, CLC and a data flash)

Read from DS40002325C (PIC16F18056/76, PDF page numbers) and from the silicon errata DS80001014D, through the pic-docs server and a text extract of the data sheet. The core, the
instruction set, the interrupt and the stack are those of the PIC16F17126/46 (`docs/FACTS-16F1714x.md`); this file lists what differs. The code generator is the same one (`pic16e`).
The other PIC16F180xx/181xx parts (PIC16F18013 … 18046, 18054/74, 18055/75, 18114 … 18176) are in other data sheets and are not described here.

## Parts (Table 1 p.1, Table 9-1 p.35)

| Part | Pins | I/O | Program flash | SRAM | Data flash | Ports | ADC channels (external) | Device ID |
|---|---|---|---|---|---|---|---|---|
| PIC16F18056 | 28 | 25 | 16K words (28 KB) | 2,048 | 256 bytes | A, B, C, RE3 (input only, MCLR) | 24 | 30FFh |
| PIC16F18076 | 40/44 | 36 | 16K words | 2,048 | 256 bytes | A, B, C, D, E (RE0-RE2, RE3) | 35 | 3100h |

- Table 1 gives the flash as 28K bytes: 16384 words of 14 bits (last address 3FFFh). Two MSSP, two EUSART, two CCP, three 10-bit PWM (PWM3 to PWM5), Timer0 (8 or 16 bit), Timer1 and
  Timer3 (16 bit, gated), Timer2, Timer4 and Timer6 (8 bit, hardware limit), a 10-bit ADC with computation, one 8-bit DAC, one comparator, ZCD, four CLC, NCO, CWG, FVR and a charge pump.
- Reset vector 0000h, interrupt vector 0004h, 16-level hardware stack (9.1 p.35, 9.5 p.51). Five configuration words at 8007h-800Bh (CONFIG3 has no fields), four user ID words at
  8000h-8003h (8.1, 8.4 p.25), revision ID 8005h, device ID 8006h (Register 8.7.1 p.33).
- RAM is 80 bytes of GPR in each bank plus 16 bytes of common RAM, as on the other PIC16F1xxxx parts.
- `devices/16F18056.expect.toml` and `16F18076.expect.toml` carry the sizes above, so `scripts/check-devices.sh` cross-checks the generated files against the data sheet.

## Peripherals as the library uses them

- **Clock (chapter 11, Table 11-1 p.80):** RSTOSC is the only source selection; the family has **no clock switching** and no divider (p.81). RSTOSC = 000 is the HFINTOSC at 32 MHz (config name
  `HFINTOSC_32MHz`), 110 the HFINTOSC at 1 MHz (`HFINTOSC_1MHz`), 101 the LFINTOSC, 100 the SOSC, 111 the external clock. COSC is the read-only OSCCON2 bits 6:4 (p.90); `OSCFRQ.FRQ` (bits 2:0)
  = 0..5 gives 1, 2, 4, 8, 16, 32 MHz (p.93); `OSCSTAT.HFOR` is bit 6 (p.94). There is no OSCCON1. The `intosc` module only writes `OSCFRQ` and the `system` module decodes COSC 000 and 110.
- **Reset flags (PCON0, 10.12.2 p.89):** STKOVF bit 7, STKUNF bit 6, RWDT bit 4, RMCLR bit 3, RI bit 2, POR bit 1, BOR bit 0; bit 5 is unimplemented (no window-violation flag).
- **PPS (chapter 18, Tables 18-1 and 18-2 p.169-170, 18.8.1 p.173):** `xxxPPS` = PORT[5:3] | PIN[2:0]. The 28-pin part routes every input and output to two ports only, the 40-pin part to two
  as well, but not always the same two: TX1 and RX1 (`RxyPPS` 0Eh, `RX1PPS`) B or C; TX2/CK2 (11h) and RX2 B or C on the 28-pin part, B or D on the 40-pin part; SCL1/SCK1 15h, SDA1/SDO1 16h B or C;
  SCL2/SCK2 17h, SDA2/SDO2 18h B or C (B or D); CCP1 09h and CCP2 0Ah B or C; PWM3 0Bh and PWM4 0Ch B or C (B or D); PWM5 0Dh A or C. Reset selections: RX1 = RC7, CK1 = RC6, RX2 = RB7,
  CK2 = RB6, SSP1CLK = RC3, SSP1DAT = RC4. So `serial` uses RC6 and RC7, `serial2` RB6 and RB7, and `spi`/`i2c` accept pins 8..23 (ports B and C).
- **Interrupt flags:** PIR0: INTF 0, IOCIF 4, TMR0IF 5. PIR1: NVMIF 0, ACTIF 2, TMR1IF 3, TMR1GIF 4, TMR3IF 5, TMR3GIF 6, TMR2IF 7. PIR3: CLC3IF 0, CLC4IF 1, TX1IF 2, RC1IF 3, TX2IF 4, RC2IF 5,
  SSP1IF 6, BCL1IF 7 (12.10.10 p.111). PIR4: SSP2IF 0, BCL2IF 1, CM1IF 2, ADIF 3, ADTIF 4, ZCDIF 5. There is no PIR5.
- **Timers (chapters 19-21):** Timer0 as the other parts (T0CON1 CS = 010 is FOSC/4). `T1CLK` CS: 0 pin, 1 FOSC/4, 2 FOSC, 3 HFINTOSC, 4 LFINTOSC, 5 SFINTOSC, 6 MFINTOSC 500 kHz, 7 MFINTOSC 32 kHz,
  8 SOSC, 9 EXTOSC, 10 Timer0 overflow (Table 20-4 p.197). `T1GATE` GSS: 0 pin, 1 Timer0, 3 Timer2, 7 CCP1, 8 CCP2, 9 PWM3, 10 PWM4, 11 PWM5, 12 NCO1, 13 C1 (Table 20-5 p.198).
  `T2RST` RSEL: 0 pin, 2 Timer4, 3 Timer6, 4 CCP1, 5 CCP2, 6 PWM3, 7 PWM4, 8 PWM5, 9 C1 (Table 21-4 p.220). `T2CLKCON` CS = 1 is FOSC/4 (Table 21-3 p.219).
- **ADC (chapter 31):** the ADCC of the PIC16F17126/46 with a 10-bit result (AD01 p.529); TAD 1..8 us (AD20 p.529). ADPCH (Table 31-6 p.428): RA0..RA7 = 0..7, RB = 8..15, RC = 16..23, RD = 24..31,
  RE0..RE2 = 32..34, ADCG1 = 35, VSS = 58, temperature indicator = 59, FVR buffer 1 = 62, buffer 2 = 63; there is **no DAC channel**. CPCON resets to 00 (charge pump off, erratum 1.1.1).
- **MSSP (chapter 29):** two hosts; SSP1STAT/CON1/CON2/CON3/ADD as the other PIC16F1xxxx parts.
- **EUSART (chapter 30):** two; the register names are the PIC16F17126's (`TX1STA`, `RC1STA`, `BAUD1CON`, `SP1BRGL/H`).
- **CCP and PWM (chapters 24 to 27):** CCPxCON = EN 7 | OUT 5 | FMT 4 | MODE 3:0; PWMxCON = EN 7 | OUT 5 | POL 4; PWMxDC is DCH:DCL with the two low bits in bits 7:6. CCPTMRS0 and PWMTMRS0 reset to Timer2 (25.1.1 p.273, 27.1.1 p.284).
- **Data flash (15.2 p.134):** 256 bytes at F000h (NVMREGS = 1, NVMADR = 70h:address); a byte write erases first; writes through the FSRs are not supported. Program flash: 32-word rows, 32 write latches,
  unlock 55h, AAh, WR (15.1 p.122, 15.1.2.2 p.124).
- **Charge pump (chapter 37):** CPCON CPON<1:0> bits 7:6; 01 = on when the ADC is on and VDD < 4.6 V.

## Errata (DS80001014D, silicon A1 to A3, all affected)

- **1.1.1 CPON defaults to OFF instead of AUTO.** `Adc.AdcInit` writes `CPCON = 01`.
- **1.2.1 Writing the Timer1 gate source can set TMR1GIF** (and interrupt when TMR1GIE is set). The gate procedures of the `timer` module clear `TMR1GIF` after the writes, as they do for the PIC16F171xx.
- Data sheet clarifications: Timer0 with PR0 = 0 in 8-bit mode gives no output and no interrupt (2.1); AD05 gain error 2.5 LSb (2.2); the CPT bit of CPCON reads the opposite of its description (2.3).
  None of them is reached by a library module.

## Simulator (MPLAB X 6.35, device models PIC16F18056 and PIC16F18076)

- The model says "Peripheral Missing: OSC" and has partial TMR1 and TMR3 support; the ADC does not convert (GO never clears), so only the set-up is tested.
- Four programs of `tests/exec` give wrong results in the model although the identical hex file is right in the PIC16F17146 model: `float_compare`, `lib_floatlib_edge`, `arith_integer`,
  `arith_word`. In `float_compare` the 64-byte array `vGe` sits at data address 5A0h and its entries 0, 1 and 3 read 0 where 1 was stored (the write itself reads back 0 at the next instruction);
  in `lib_floatlib_edge` the variable `r217` is at 5A0h and reads 0. The same two programs fail on the PIC16F18076 model. Reducing `float_compare` to five of its six comparison groups makes it pass, so the
  loss needs the whole program. Not understood; not shown to be a fault of the compiler or of silicon. These four are in the skip list `P180_SKIP` of `tests/backend.rs`.
