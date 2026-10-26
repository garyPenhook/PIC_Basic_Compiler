# PIC18-Q41 fact base (PIC18F04/05/06/14/15/16Q41)

Every fact below was read from a Microchip document and carries its source. Page numbers are PDF
pages. Where the MPLAB X simulator was the evidence, it says so.

* **DS-A** = PIC18F06/16Q41 Data Sheet, DS40002214G (967 pp.)
* **DS-B** = PIC18F04/05/14/15Q41 Data Sheet, DS40002242F (967 pp.; same chapters and page numbers as DS-A)
* **ES-A** = PIC18F06/16Q41 Silicon Errata and Data Sheet Clarifications, DS80000901H
* **ES-B** = PIC18F04/05/14/15Q41 Silicon Errata and Data Sheet Clarifications, DS80000911H
* **PACK** = Microchip device pack `PIC18F-Q_DFP 1.31.492`, files `edc/PIC18F<nn>Q41.PIC`
* **SIM** = MPLAB X simulator (`mdb`), device `PIC18F16Q41`

Status key: ✔ verified · ◐ verified, with a caveat in the text.

Parts: PIC18F04Q41 / 05Q41 / 06Q41 are the 14-pin parts (ports A and C, 12 I/O); PIC18F14Q41 / 15Q41 /
16Q41 are the 20-pin parts (ports A, B and C, 18 I/O). `x4` = 16 KB flash / 1 KB RAM, `x5` = 32 KB / 2 KB,
`x6` = 64 KB / 4 KB; all have 512 bytes of data EEPROM. (DS-A Table 1 p.1, DS-B Table 1 p.1, DS-A Table 3-1 p.13.)

## 1. Memory

| Fact | Value | Source |
|---|---|---|
| ✔ Program flash | 8 / 16 / 32 K words = 16 / 32 / 64 KB; 21-bit PC; the addresses do not roll over | DS-A Fig. 9-1 p.58, 9.1 p.57 |
| ✔ Flash page | 128 words = 256 bytes (the erase size); 64 / 128 / 256 user-erasable pages | DS-A Table 9-3 p.65, 10.3.1 p.89 |
| ✔ User IDs | 32 words at `20 0000h`–`20 003Fh` | DS-A Fig. 9-1 p.58, 8.3 p.43 |
| ✔ Configuration bytes | `30 0000h`–`30 0009h`: CONFIG1 … CONFIG9 (one byte each) | DS-A 8.1 p.43, 8.6 p.53 |
| ◐ Pack's configuration sector | `300000h`–`300012h` (18 bytes); the extra bytes hold no register, so `devgen check` records it as an accepted difference | PACK `ConfigFuseSector`; `devices/18F*Q41.expect.toml` |
| ✔ Data EEPROM | 512 bytes at `38 0000h`–`38 01FFh` | DS-A Fig. 9-1 p.58 |
| ✔ Device Information Area / Device Configuration Information | `2C 0000h`–`2C 00FFh` / `3C 0000h`–`3C 0009h`, read only | DS-A Fig. 9-1 p.58, 9.3 p.65 |
| ✔ Device ID | `3F FFFEh`; revision ID `3F FFFCh` | DS-A 8.4 p.43 |
| ✔ Data memory | 14-bit addresses, up to 64 banks of 256 bytes; SFRs in banks 0–4, general purpose RAM from bank 5 (`0500h`) | DS-A 9.4 p.65, Fig. 9-3 p.66 |
| ✔ SRAM | 1024 / 2048 / 4096 bytes at `0500h`…; the bank after them is the NVM page buffer and is not user RAM (bank 9 / 13 / 21) | DS-A Table 1 p.1, Table 10-2 p.92; PACK `SystemGPRDataSector` |
| ✔ `MOVFF` reaches 12-bit addresses only; the three-word `MOVFFL` takes the full address. `pic-as` writes `movffl` when an operand is above `0FFFh`; the compiler writes it itself so branch sizes stay exact | DS-A 7.4.3 p.32 (Tables 7-5, 7-6); tried with `pic-as` |

## 2. Access Bank

| Fact | Value | Source |
|---|---|---|
| ✔ Access RAM | `0500h`–`055Fh` (96 bytes), Access Bank offsets `00h`–`5Fh` | DS-A 9.4.2 p.68, Fig. 9-3 p.66 |
| ✔ Fast SFRs | `0460h`–`04FFh` (160 bytes), offsets `60h`–`FFh` | DS-A 9.4.2 p.68 |
| ✔ An address below `0460h` (most SFRs: `LATx`, `TRISx`, `T0CON0`, `NVMCON0` …) is **not** in the Access Bank and needs `BSR` | DS-A Fig. 9-3 p.66 |

The Q10 compiler tested "address below the end of Access RAM, or at or above the SFR half" and that is
true of every low SFR here, so `bcf TRISC, 0, c` was generated with a wrong access bit. The test now
uses both ranges (`in_access` in `src/codegen.rs`).

## 3. Return stack

| Fact | Source |
|---|---|
| ✔ 127 levels (calls and interrupts); `STKPTR` is 7 bits; overflow or underflow resets the part when `STVREN` is on. The compiler's `E-STACK` limit comes from the device description (`hw_stack`, from the pack's `hwstackdepth`) | DS-A 9.1.3 p.60, 9.1.3.2 p.61; PACK `hwstackdepth="127"` |

## 4. Interrupts

| Fact | Value | Source |
|---|---|---|
| ✔ The part has the vectored interrupt controller (VIC): `INTCON0` (`GIE/GIEH` bit 7, `GIEL` bit 6, `IPEN` bit 5, `INTxEDG` bits 2:0) and `INTCON1` (`STAT`), at `04D6h` / `04D7h`. There is no `INTCON` | DS-A 11.2 p.113, 11.13.1 p.127 |
| ✔ `MVECEN` (CONFIG3 bit 3) is **on** when unprogrammed. With `MVECEN = 0` the IVT is not used, interrupts are compatible with earlier PIC18, `IVTBASE` defaults to `000008h`: high-priority vector `000008h`, low-priority vector eight words on, `000018h` | DS-A 11.3.3 p.114, 11.12 p.125; PACK `MVECEN` default |
| ✔ With `MVECEN = 0` the word at each vector is a `GOTO` | DS-A 11.3.2 p.114. Microchip's own MCC project and the XC8 build in it use `MVECEN = OFF`, `IPEN = 0`, a `GOTO` at `0008h`, and `RETFIE 1` |
| ◐ A handler written directly at `0008h` (as on the Q10) was entered with the return address pushed twice in the simulator and ran twice | SIM. The compiler therefore writes `goto __ISR_H` at `0008h` (and `0018h`) on the VIC parts |
| ✔ `GIEL` is reserved (reads 0) when `IPEN = 0` | DS-A 11.13.1 p.127. The Q10 `Enable` set bit 6 as well (PEIE there); with it set the simulator vectored twice, so `Enable` sets only `GIE` here |
| ✔ Hardware does not change `GIE/GIEH/GIEL` when it serves an interrupt; its state machine keeps track instead. A request still pending when `GIE` is cleared is dropped | DS-A 11.5 p.118, 11.8.1 p.123–124 |
| ✔ Context: on entry hardware saves `STATUS`, `WREG`, `BSR`, `FSR0/1/2`, `PRODL/H`, `PCLATH/U`, two levels deep (main and low-priority ISR); `RETFIE 1` restores all of them | DS-A 11.6 p.120–121, RETFIE p.847 |
| ✔ Interrupt flags are in `PIR0`…`PIR10`, enables in `PIE`, priority in `IPR`. Timer0/1/2 flags: `PIR3` bits 7/4/3; `NVMIF` is `PIR0` bit 4; `SWIF` is `PIR0` bit 0 | DS-A 11.13 p.144–149 |
| ◐ The simulator does not vector on `SWIF`; a flag a program can set (such as `TMR0IF`) does | SIM |

## 5. Clock, reset and configuration

| Fact | Value | Source |
|---|---|---|
| ✔ `OSCCON1` (`NOSC`, `NDIV`), `OSCCON2` (`COSC`, `CDIV`), `OSCCON3`, `OSCFRQ`, `OSCSTAT` as on the Q10; `OSCFRQ` codes 0…8 = 1, 2, 4, 8, 12, 16, 32, 48, 64 MHz (the pack names the field `HFFRQ`, the data sheet `FRQ`) | DS-A 12.5 p.194–199 |
| ✔ `RSTOSC` 0 = `HFINTOSC_64MHZ`, 6 = `HFINTOSC_1MHZ` | PACK `RSTOSC`; DS-A Table 12-2 p.184 |
| ✔ `PCON0` (reset flags) at `04F0h` with the Q10 bit layout | DS-A 14.13.2 p.232 |
| ✔ `PORTx`, `LATx`, `TRISx`, `ANSELx` (reset 1), `WPUx`, `ODCONx` as on the Q10; no port B on the 14-pin parts | DS-A 19.14 p.304–312, Table 3-1 p.13 |

## 6. Peripherals the library uses

| Fact | Source |
|---|---|
| Timer0 `T0CON0/1`, Timer1 `T1CON/T1GCON/T1CLK/T1GATE`, Timer2 `T2CON/T2HLT/T2CLKCON/T2RST` have the Q10 layout; the clock, gate and reset source selection tables differ | DS-A 24.5 p.359–360, 25.13 p.374–378, 26.7 p.384, 26.10 p.397–400 |
| ADCC is 12-bit; `ADPCH` is 8 bits wide with the pins at 0…5, 12…15, 16…23 and the internal sources at 58…63; `ADCP.CPON` is the charge pump; TAD 0.5–9 µs (AD20); 7.79 µs acquisition example for a 10 kΩ source | DS-A 40.3 p.723, 40.7 p.735–742, 40.7.23 p.758, 48.4.8 p.903 |
| UART1…3: `UxCON0/1/2`, `UxBRG`, `UxTXB`, `UxRXB`, `UxFIFO` (`TXBF` bit 4, `TXBE` bit 5, `RXBE` bit 1), `UxERRIR` (`TXMTIF` bit 7, `RXFOIF` bit 1); baud = FOSC·(1 + 3·BRGS) / (16·(BRG + 1)); `UxTX` PPS codes 10h / 13h / 16h | DS-A 34.20 p.547–562, Table 21-2 p.323 |
| PPS input registers `xxxPPS` = `PORT[5:3] | PIN[2:0]` (A = 0, B = 1, C = 2); default pins in Table 21-1 | DS-A 21.8.1 p.326, Table 21-1 p.322 |
| NVM: `NVMCON0.GO`, `NVMCON1` (`NVMCMD` bits 2:0, `WRERR` bit 7), `NVMLOCK` (55h, AAh), `NVMADR` (22-bit byte address), `NVMDAT`; data EEPROM bytes; flash word write needs an erased word; page read/erase/write use the buffer RAM; `TBLWT` writes it with `TBLPTRL` as the offset | DS-A 10.1–10.5 p.87–108 |
| SPI1: `SPI1CON0` (`EN`, `LSBF`, `MST`, `BMODE`), `SPI1CON1` (`SMP`, `CKE`, `CKP`, `FST`, `SSP`, `SDIP`, `SDOP`), `SPI1CON2` (`TXR`, `RXR`), `SPI1BAUD`, `SPI1TWIDTH`, `SPI1TXB/RXB`; FSCK = Fclk / (2·(BAUD + 1)); host full duplex at most 10 MHz (95 ns) | DS-A 35.7 p.589–596, 35.3 p.575, Table 48-21 p.908 |
| I2C1 host transfers count bytes in hardware (`I2C1CNT`, `I2C1ADB1`, `S`, `P`, `RSEN`, `MDR`) | DS-A 36.4.2 p.643–657, 36.5 p.669–672 |

## 7. Errata that touch this project

| Item | Effect here | Source |
|---|---|---|
| ADCC 1.1.2 double sample with `ADPRE = ADACQ = 0` | not used (the `adc` module uses basic mode with `ADACQ` set) | ES-A p.3, ES-B p.2 |
| ADCC 1.1.1 (rev A4 only) ADC off with LFINTOSC/SOSC clock and BOR and FVR off | none for the library, which clocks from HFINTOSC | ES-A p.3 |
| I2C 1.3.x / 1.4.x (start/stop flags, bus time-out, clock-stretch disable, multi-host) | the I2C module is not ported; recorded for when it is | ES-A p.4–6 |
| UART 1.5.1 (`TXDE` may fall early), 1.5.2 (9-bit address mode mismatch) | the `serial` modules use neither | ES-A p.7–8 |
| CPU 1.7.1 FSR shadow registers not writable | the compiler never writes a shadow register | ES-A p.8–9 |
| Instruction set 1.9.1 `PUSHL` (extended instruction set) | the compiler does not use `PUSHL` or the extended instruction set | ES-A p.9 |
| Memory 1.10.1 DIA temperature constants TSLR2/TSHR2 wrong | not used | ES-A p.10 |

The 04/05/14/15 errata sheet lists the same items under other numbers (and "ADC offset error specification
lowered in ECH, ECM and ECL modes" for revision E0), ES-B p.2.
