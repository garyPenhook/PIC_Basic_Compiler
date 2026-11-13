# Standard library (M6)

Written in the language, found by `Include "name"` in the project's `lib/` folder (LANGUAGE.md §9).
A routine is called as `Module.Routine(...)` or, when the name is unambiguous, by its own name.
Only what a program calls is compiled in. Each module cites the data sheet pages its register
values come from (DS40002043F, PIC18F27/47Q10; PIC16F17126/46 values from DS40002343F, PIC16F13113..13145 values from DS40002519D, PIC16F13214..13245 values from DS40002686B, PIC16F183xx values from DS40001799F / DS40001800E / DS40001795K / DS40001839E, PIC16F152xx values from DS40002195E, PIC16F18056/76 values from DS40002325C and PIC18F0x/1xQ41
values from DS40002214G / DS40002242F where the module is ported, see "Device support" below); the values were
checked against those documents.

`DelayUs`, `DelayMs`, `Input`, `Output`, `High`, `Low` and `Toggle` are compiler intrinsics
(LANGUAGE.md §12), so there is no module for them. No library module declares an `Interrupt`
handler: that would take a vector away from the program. Modules configure peripherals and read
flags; the program writes its own handler.

## Device support: work still to do (read this when adding a device or a family)

The modules were written for the PIC18F27/47Q10 and are being made device-independent one by one.
A module adapts with `#if _has(REG)` / `#if _has(REG.FIELD)` (MANUAL §Preprocessor), which asks the
device description whether a register or bit field exists, so most of a new part in a known layout
needs no module change. **A new device or family needs this table reviewed**, because a module that
is not listed as ported either does not compile on the new part or, worse, compiles and writes the
wrong register. The PIC16F171xx column is checked against the data sheet; since 0.1.50 the code generator for the part exists, and since 0.1.51 every
module except `dma` (the part has no DMA) builds for it: `delay`, `gpio`, `timer`, `serial`, `serial2`, `lcd`, `oled`, `aht30`, `spi`, `i2c`,
`pwm`, `eeprom`, `flashwrite`, `adc` and `floatlib` run in the simulator (`tests/exec_p16`, `P16_PORTABLE` in `tests/backend.rs`);
`intosc` and `system` build, with their register values read from the data sheet but not yet run on the part; a module that is not
ported stops with `#error`. The simulator has no ADC for the part, and shows no bus traffic (`spi`, `i2c`), so those tests check set-up
only. Nothing was run on a real part.

| Module | PIC18F27/47Q10 | PIC16F17126/46 (DS40002343F) | PIC16F13113..13145 (DS40002519D) | PIC18F0x/1xQ41 (DS40002214G, DS40002242F) | Still to do |
|---|---|---| --- |---|---|
| `delay` | done | portable (no device registers) | portable | portable | none |
| `gpio` | done | done (`_has` on `ANSELx`, `WPUx`, `ODCONx`) | done (`_has` on `ANSELx`, `WPUx`, `ODCONx`; 8-pin part has port A only) | done (the same registers; no port B on the 14-pin parts) | none |
| `intosc` | done | done (`OSCFRQ.FRQ`: 1..32 MHz) | done (`OSCFRQ.FRQ`: 1..32 MHz) | done (`OSCFRQ.HFFRQ`, 1..64 MHz as the Q10) | none |
| `system` | done | done | done | done (`PCON0` at `04F0h`, same bits) | none |
| `timer` | done | done (flags in PIR1/PIR2, own source constants) | done (flags in PIR0..PIR2; no secondary oscillator or Timer4: `T1ClkSosc` and `T2RstTmr4` absent, `T1ClkMfIntOsc32` and `T1ClkExtOsc` added) | done (flags in `PIR3`; own `T1Clk*`, `T1Gate*`, `T2Rst*` constants) | `T1Gate*` / `T2Rst*` lists hold only the sources checked so far |
| `serial` | done (TX RC6, RX RC7) | done (TX RC4, RX RC5) | done (EUSART1, TX RC4, RX RC5; RA4 and RA5 on the 8-pin part) | done (UART1, TX RC4, RX RC5) | an override for other pins |
| `serial2` | done (TX RB6, RX RB7) | done (EUSART2, TX RC2, RX RC1, `TX2IF`/`RC2IF` are `PIR5` bits 0 and 1) | `#error` (one EUSART) | done (UART2, TX RC2, RX RC1) | an override for other pins |
| `adc` | done (10 bits) | done (channels 58..62; 12 bits; erratum 1.1.2 noted; erratum 1.6.1 worked around: `AdcInit` writes `CPCON` = 01) | done (10 bits, `AdcMax` = 1023, channels 58..63, TAD >= 2 us for erratum 1.1.1 in DS80001115F; the ADC does not run in the simulator) | done (12 bits, `AdcMax` = 4095, channels 58..63, charge pump on, 8 us acquisition) | the 16F ADC does not run in the simulator, so only its set-up is tested |
| `eeprom` | done (1024 bytes) | done (256 bytes through `NVMREGS = 1`, address `70h:addr`, 55h/AAh unlock in `NVMCON2`) | `#error` (no data EEPROM; use `flashwrite`) | done (512 bytes, `NVMLOCK` unlock) | none |
| `flashwrite` | done | done (a sector is the 32-word row; word write through the write latches; `FlashUpdateWord` keeps the row in a 64-byte RAM image; 14-bit words, erased = 3FFFh) | done (as the PIC16F171xx; 2K/4K/8K words, `FlashLastSector` from the size) | done (`FlashLastSector` from the flash size; page read, erase, write through the NVM buffer bank) | none |
| `spi` | done | done (MSSP1, pins 0..23 as the Q41, `RxyPPS` 27 = SCK1 and 28 = SDO1, `SSP1CLKPPS`/`SSP1DATPPS` = the pin number) | done (MSSP1, `RxyPPS` 27 = SCK1 and 28 = SDO1; pins of the part only) | done (SPI1, any of RA/RB4..7/RC pins through PPS, at most 10 MHz) | none |
| `lcd` | done | done (20-pin part; port B pins refused on the 14-pin one) | done (pins of the part only: port B on the 20-pin parts, port C not on the 8-pin part) | done (port B pins refused on the 14-pin parts) | the 16F: port B does not exist on the 14-pin part; choose the pins |
| `i2c` | done | done (MSSP1 hardware host, pins 0..23, `RxyPPS` 27 = SCL1 and 28 = SDA1; `SSP1IF`/`BCL1IF` are `PIR5` bits 2 and 3) | done (MSSP1 hardware host as the PIC16F171xx; pins of the part only) | done, **in software** on two pins by default; the I2C1 peripheral with `#option I2c = Hardware` (block routines only, see below) | run on the I2C1 peripheral in silicon (it ran only on the instruction-level model, `scripts/test_i2chw.py`) |
| `pwm` | done | done (the 16-bit PWM1 and PWM2: channels 1..4 = PWM1S1P1 … PWM2S1P2, `RxyPPS` = 10 + channel; CCP1 and CCP2 are not offered) | done (CCP1, CCP2, PWM1, PWM2 = channels 1..4 on Timer2, as the Q10; `RxyPPS` 09h, 0Ah, 2Ch, 2Dh) | done with different channels: 1..6 = PWM1S1P1 … PWM3S1P2, one shared period (CCP1 not offered) | none |
| `oled` | done | done (builds and the set-up test passes in the simulator; not run against a display) | done over `i2c`/`spi`; the frame buffer (1 KB) does not fit the 1 KB RAM of the largest part: text and OledGoto/OledData/OledBitmap build (the buffer is not placed unless a pixel command is used; a pixel command stops with `E-RAM`) | done (over the software `i2c`, or `spi`) | |
| `aht30` | done | done (over the hardware `i2c`; set-up test passes in the simulator) | done (over the hardware `i2c`) | done (over the software `i2c`) | |
| `dma` | not applicable (no DMA) | not checked (the 16F17126/46 data sheet has not been read for DMA) | `#error` (no DMA) | written for software-started RAM/SFR copies (`DmaCopy`) trigger-started feeds (`DmaOnTrigger`) with abort triggers (`DmaAbortOn`) and flash- and EEPROM-source copies (`DmaCopyFlash`, `DmaCopyEeprom`; the EEPROM address form comes from Microchip's TB3164, not the Q41 data sheet); builds, register set-up tested, bytes moved checked only against a DMA model of the data sheet (`scripts/dma_sim.py`); a part without `DMAnCON0` gets `#error` | interrupts, priorities; data movement not seen on a real part (MDB has no DMA; the tests use the model) |
| `floatlib` | done | done, **written in Basic** on `LongWord` arithmetic (the PIC18 routines are assembly): the same results bit for bit (`tests/exec_p16/float_random.bas`), about 1.2K words for `+` against 200 on the PIC18 | done (as the PIC16F171xx; about 1.2K words for `+`, so 2K-word parts have little room left) | builds (no device registers); not run on the Q41 | hand-written assembly for the enhanced mid-range core would be several times smaller; run the float tests on the Q41 simulator |

### PIC16F13214 / 13215 / 13224 / 13225 / 13244 / 13245 (DS40002686B, errata DS80001213B; facts in `FACTS-16F132xx.md`)

A PIC16F17126/46-like peripheral set (16-bit PWM, two EUSART, Timer3/4, secondary oscillator, data EEPROM) with the PIC16F13145 family's CLB and 10-bit ADCC, in 8-, 14- and 20-pin packages. The modules choose
their branch from the registers the part has (`_has`); the ones below were checked against the data sheet. The simulator tests run on the PIC16F13245 (`tests/exec_p16` and `tests/exec_p132`); `tests/exec_p132/pins8`,
`pins14` and `pins20` check the pins each package accepts, and every part builds `tests/exec_p132_parts/small.bas`. The simulator has no ADC conversion and shows no bus traffic. Nothing was run on a real part.

| Module | PIC16F132xx |
|---|---|
| `delay`, `strings`, `shift`, `floatlib`, `fmath` | portable (no device registers) and run in the simulator on the PIC16F13245 (`tests/exec_p16`, `tests/exec_p132/lib_fmath`); the Float routines are about 1.2K words, so the 4K-word parts have little room left |
| `bits`, `buttons`, `pinio`, `pulse` | build for the part (`tests/exec/lib_bits`, `lib_buttons`, `lib_pinio`, `lib_pulse` retargeted); their tests are PIC18-only (`devices: 18F27Q10`), so they have not run on a PIC16F132xx |
| `gpio` | done (`ANSELx`, `WPUx`, `ODCONx`, `_has` per port; the 8-pin parts have port A only, the 14-pin parts no port B) |
| `intosc` | done (`OSCFRQ.FRQ` 1..32 MHz = 0..5; NOSC 110 = HFINTOSC, NDIV 1:1..1:512) |
| `system` | done (`PCON0` with the window violation flag; no fetch erratum, so `Sleep` adds no NOPs) |
| `timer` | done (Timer0/1/2; flags `PIR0.5`, `PIR1.6`, `PIR2.2`; Timer1 clocks 0..8 and, for this family only, 7 `T1ClkMfIntOsc32`, 9 `T1ClkExtOsc`, 10 `T1ClkRef`, 13 `T1ClkTmr3`; gates incl. `T1GateTmr4` and `T1GatePwm1P1`..`T1GatePwm2P2`; `T2RstPwm1P1`..`T2RstPwm2P2`) |
| `serial` | done (EUSART1, TX RC4 = `13h`, RX RC5; RA4 and RA5 on the 8-pin parts) |
| `serial2` | done (EUSART2, TX RC2 = `16h`, RX RC1, `TX2IF`/`RC2IF` are `PIR5` bits 0 and 1; **TX RA2 and RX RA1 on the 8-pin parts**) |
| `adc` | done (10 bits, `AdcMax` = 1023, channels 0..2, 4, 5, 12..23, VSS 58, temperature 59, DAC1 60, FVR 62/63; **TAD >= 0.5 us**, `MinTadNs` = 500: the PIC16F13145 family's 2 us comes from its own erratum, which this family does not have; no charge pump write, CPON resets to 01) |
| `eeprom` | done (256 bytes through `NVMREGS = 1`, `NVMADRH:NVMADRL` = `70h:addr`, 55h/AAh unlock; as the PIC16F17126/46) |
| `flashwrite` | done (32-word row, 14-bit words, `FlashLastSector` from the size: 4K and 8K words) |
| `spi` | done (MSSP1, `RxyPPS` 27 = SCK1 and 28 = SDO1; pins of the part only) |
| `i2c` | done (MSSP1 hardware host, `RxyPPS` 27 = SCL1 and 28 = SDA1; `SSP1IF`/`BCL1IF` are `PIR5` bits 2 and 3; pins of the part only) |
| `pwm` | done (the two 16-bit PWM modules: channels 1..4 = PWM1S1P1 .. PWM2S1P2, `RxyPPS` = 10 + channel = `0Bh`..`0Eh`; CCP1 and CCP2 are not offered; **pins of the part only**: the 8-pin parts have no port C) |
| `lcd` | done (pins of the part only) |
| `oled`, `aht30` | done over `i2c`/`spi`; the frame buffer (1 KB) does not fit the 1 KB RAM of the largest part, so text and `OledGoto`/`OledData`/`OledBitmap` build and a pixel command stops with `E-RAM` |
| `dma` | `#error` (no DMA) |

### PIC16F18313 … 18346 (DS40001799F, DS40001800E, DS40001795K, DS40001839E; facts in `FACTS-16F183xx.md`)

First-generation PPS parts: the register names and several codes differ from the PIC16F171xx, so every module that touches them has its own branch, chosen with `#if _has(ADCON0.CHS)` (or `_has(T1CON.TMR1CS)`,
`_has(ADCON0.CHS)`, `_has(PWM5DCL)` for the part of a module that differs). A module that is not ported stops with `#error`. The simulator tests (`tests/exec_p183`, the portable programs and `tests/exec_p16`)
run on the PIC16F18346; the simulator has no ADC for the part, so only its set-up is tested. Nothing was run on a real part.

| Module | PIC16F183xx |
|---|---|
| `delay`, `strings` | portable |
| `gpio` | done (`ANSELx`, `WPUx`, `ODCONx`, `_has` per port; 8-pin part has port A only, the 14-pin parts no port B) |
| `intosc` | `#error`: the HFFRQ codes differ from the Q10 and 32 MHz goes through the 2x PLL; set the speed with `Config RSTOSC = HFINT32` (32 MHz) or `HFINT1` and give `Clock` to match |
| `system` | done (no window violation cause on `PCON0`; clock decode for COSC 110 and for the 2x PLL, `HFFRQ` 1, 2, -, 4, 8, 12, 16 MHz) |
| `timer` | done (Timer0 as the PIC16F171xx; Timer1 with `TMR1CS` in `T1CON`, gate source in `T1GCON`, no `RD16` so the read takes `TMR1H` twice; old Timer2 with `T2CKPS` 1, 4, 16, 64 and no mode registers, so no `Timer2StartLimit`, `T2Mode*` or `T2Rst*`; `T1Clk*`: Fosc4, Fosc, Pin, LfIntOsc; `T1Gate*`: Pin, Tmr0, Cmp1, Cmp2) |
| `serial` | done (EUSART1, `RXPPS`, TX/CK = `14h`; TX RC4 and RX RC5, RA4 and RA5 on the 8-pin part) |
| `serial2` | `#error` (one EUSART) |
| `adc` | done (10 bits, `AdcMax` = 1023; `ADCON0.CHS`, `ADCON1.ADCS`; channels 60..63; TAD >= 1 us; the 5 us acquisition is a software delay after a channel change) |
| `eeprom` | done (256 bytes at F000h through `NVMREGS = 1`, `NVMADRH` = 70h; erratum WRERR covered by the read-back) |
| `flashwrite` | done (32-word row, 14-bit words; as the PIC16F171xx; `FlashLastSector` from the size) |
| `spi` | done (MSSP1, `RxyPPS` 24 = SCK1 and 25 = SDO1) |
| `i2c` | done (MSSP1 hardware host, `RxyPPS` 24 = SCL1 and 25 = SDA1; `SSP1IF`/`BCL1IF` are `PIR1` bits 3 and 2) |
| `lcd` | done (pins of the part only: port B on the 20-pin parts, port C not on the 8-pin part) |
| `pwm` | done (CCP1, CCP2, PWM5, PWM6 = channels 1..4 on Timer2 with prescalers 1, 4, 16, 64; `RxyPPS` 0Ch, 0Dh, 02h, 03h) |
| `oled`, `aht30` | done over `i2c`/`spi` (the 1 KB frame buffer does not fit the parts with less than 2 KB of RAM: use OledGoto/OledData) |
| `dma` | `#error` (no DMA) |
| `floatlib` | done (as the PIC16F171xx; about 1.2K words for `+`, so the 2K-word parts have little room left) |

### PIC16F15213 … 15244 (DS40002195E; facts in `FACTS-16F152xx.md`)

Parts with a fixed clock (no clock switching), a 10-bit ADC without ADCC, no data EEPROM and the PIC16F171xx register names for PPS and the timers. Several codes and flag bits differ from every other family,
so the modules tell this part apart with `#if _has(ADCON1.PREF)` (the PIC16F183xx calls the field `ADPREF`; `_has(PIR1.TMR1IF)` is true here too but with other bit numbers). A module that is not ported stops with `#error`.
The simulator tests (`tests/exec_p152`, the portable programs and `tests/exec_p16` that fit) run on the PIC16F15244; the simulator has no ADC for the part, so only its set-up is tested. Nothing was run on a real part.

| Module | PIC16F152xx |
|---|---|
| `delay`, `strings` | portable |
| `gpio` | done (`ANSELx`, `WPUx`, `ODCONx`, `_has` per port; the 8-pin parts have port A only, the 14-pin parts no port B) |
| `intosc` | done for `Clock` = 32, 16, 8, 4, 2, 1: only `OSCFRQ.FRQ` is written (no clock switching, no divider, so no `Clock` below 1 and `SetClockDiv` needs shift 0); `Config RSTOSC = HFINTOSC_32MHZ` or `HFINTOSC_1MHZ` must be the source |
| `system` | done (no window violation cause on `PCON0`; clock decode for COSC 00 and 10 with `OSCFRQ.FRQ` 0..5 = 1, 2, 4, 8, 16, 32 MHz, no divider) |
| `timer` | done (Timer0, Timer1 and Timer2 as the PIC16F171xx; flags `TMR1IF` and `TMR2IF` in `PIR1` bits 5 and 6, `TMR1GIF` in `PIR2`; `T1Clk*`: Pin, Fosc4, Fosc, HfIntOsc, LfIntOsc, SfIntOsc, MfIntOsc, MfIntOsc32, Tmr0; `T1Gate*`: Pin, Tmr0, Tmr2, Ccp1, Ccp2, Pwm3, Pwm4; `T2Rst*`: Pin, Ccp1, Ccp2, Pwm3, Pwm4) |
| `serial` | done (EUSART1, `RX1PPS`, TX/CK = `05h`; TX RC4 and RX RC5, RA4 and RA5 on the 8-pin parts; waits for TRMT, erratum 1.3.1) |
| `serial2` | `#error` (one EUSART) |
| `adc` | done (10 bits, `AdcMax` = 1023; `ADCON0.CHS`, `ADCON1.CS`/`PREF`; `AdcChVss` 27 and `AdcChFvr` 30, no temperature or DAC channel; TAD >= 0.5 us; the charge pump is switched on) |
| `eeprom` | `#error` (no data EEPROM; use `flashwrite`) |
| `flashwrite` | done (32-word row, 14-bit words; as the PIC16F171xx; `FlashLastSector` from the size, 63 or 127) |
| `spi` | done (MSSP1, `RxyPPS` 07h = SCK1 and 08h = SDO1) |
| `i2c` | done (MSSP1 hardware host, `RxyPPS` 07h = SCL1 and 08h = SDA1; `SSP1IF`/`BCL1IF` are `PIR1` bits 1 and 2; erratum 1.4.1 does not apply) |
| `lcd` | done (pins of the part only: port B on the 20-pin parts, port C not on the 8-pin parts) |
| `pwm` | done (CCP1, CCP2, PWM3, PWM4 = channels 1..4 on Timer2 with prescalers 1..128; `RxyPPS` 01h, 02h, 03h, 04h; any pin of the part; erratum 1.2.1 cannot be reached) |
| `oled`, `aht30` | done over `i2c`/`spi` (the 1 KB frame buffer does not fit: use OledGoto/OledData) |
| `dma` | `#error` (no DMA) |
| `floatlib` | done (as the PIC16F171xx; about 1.2K words for `+`, so the 2K-word parts have little room left) |

### PIC16F18056 / 18076 (DS40002325C; facts in `FACTS-16F1805x.md`)

Parts with a fixed clock (no clock switching), the 10-bit ADCC of the PIC16F171xx, two MSSP and two EUSART, 256 bytes of data flash and the PIC16F183xx-style `OSCCON2`/`OSCFRQ.FRQ`. The modules tell the part apart with
`Not _has(OSCCON1)` (the PIC16F152xx has none either but is picked out first by `_has(ADCON1.PREF)`) or, in `pwm`, with `_has(PWM5CON) And Not _has(PWM6CON)`. PPS routes each peripheral to two ports only
(Tables 18-1 and 18-2 p.169-170), so the pin-number modules accept pins 8..23 (ports B and C) where the table allows both, and the fixed pins below. The simulator tests (`tests/exec_p180`, the portable programs and
`tests/exec_p16` that apply) run on the PIC16F18056; the simulator does not convert with the ADC, so only its set-up is tested, and four programs are held back (see `FACTS-16F1805x.md`). Nothing was run on a real part.

| Module | PIC16F18056 / 18076 |
|---|---|
| `delay`, `strings` | portable |
| `gpio` | done (`GpioAllDigital` also clears `ANSELD` and `ANSELE` on the PIC16F18076; the mask routines cover ports A, B and C) |
| `intosc` | done for `Clock` = 32, 16, 8, 4, 2, 1 as on the PIC16F152xx: only `OSCFRQ.FRQ` is written; the source must be `RSTOSC = HFINTOSC_32MHz` or `HFINTOSC_1MHz` (COSC is `OSCCON2` bits 6:4) |
| `system` | done (no window violation cause on `PCON0`; `SysClockFrom(cosc, 0, frq)` takes COSC 0 or 6 and `OSCFRQ.FRQ` 0..5 = 1 .. 32 MHz; the watchdog is `WDTCON`) |
| `timer` | done (Timer0, Timer1, Timer2; flags `TMR1IF` and `TMR1GIF` in `PIR1` bits 3 and 4, `TMR2IF` bit 7; `T1Clk*` adds Sosc and ExtOsc, `T1Gate*` adds Pwm3, Pwm4, Pwm5, Nco1, Cmp1; `T2Rst*`: Pin, Tmr4, Tmr6, Ccp1, Ccp2, Pwm3, Pwm4, Pwm5, Cmp1; erratum 1.2.1 handled) |
| `serial` | done (EUSART1, TX on RC6 through `RC6PPS = 0Eh`, RX on RC7 through `RX1PPS = 23`; `TX1IF`/`RC1IF` are `PIR3` bits 2 and 3) |
| `serial2` | done (EUSART2, TX on RB6 through `RB6PPS = 11h`, RX on RB7 through `RX2PPS = 15`; `TX2IF`/`RC2IF` are `PIR3` bits 4 and 5) |
| `adc` | done (10 bits, `AdcMax` = 1023; ADCC registers; `AdcChVss` 58, `AdcChTemp` 59, `AdcChFvr` 62, `AdcChFvr2` 63, no DAC channel; `AdcPin` also takes channels 24..34 on the PIC16F18076; the charge pump is switched on, erratum 1.1.1) |
| `eeprom` | done (256 bytes, `NVMREGS`; as the PIC16F171xx) |
| `flashwrite` | done (32-word row, 14-bit words; `FlashLastSector` = 511) |
| `spi` | done (MSSP1, `RxyPPS` 15h = SCK1 and 16h = SDO1; pins 8..23) |
| `i2c` | done (MSSP1 hardware host, `RxyPPS` 15h = SCL1 and 16h = SDA1; `SSP1IF`/`BCL1IF` are `PIR3` bits 6 and 7; pins 8..23) |
| `lcd`, `shift`, `oled`, `aht30`, `rtcc`, `rtccspi` | done (portable programs run in the simulator; pins 0..23, ports A, B and C; `pinio` and `pulse` have no register differences but were not run there) |
| `pwm` | done (CCP1, CCP2, PWM3, PWM4 = channels 1..4 on Timer2 with prescalers 1..128; `RxyPPS` 09h, 0Ah, 0Bh, 0Ch; channels 1 and 2 on pins 8..23, channels 3 and 4 on pins 8..15 and, on the 28-pin part, 16..23) |
| `dma` | `#error` (no DMA) |
| `floatlib` | done (as the PIC16F171xx) |

On the PIC18-Q41 the `Gpio`, `Timer`, `Serial`, `Adc`, `Eeprom`, `Flashwrite`, `Spi`, `I2c`, `Pwm`, `Lcd`, `Oled`, `Aht30` and `Dma` tests (those in
`tests/exec_q41/` and the portable ones of `tests/exec`) run in the MPLAB X simulator (`BASIL_MDB=1 cargo test q41`); they check
register values and set-up, not waveforms (no part of the PIC18-Q41 transfer code ran against a real bus). Limits of the simulator: it
does not shift the UART transmit buffer out (so `lib_serial` sends one byte and does not flush), and it does
not vector on `SWIF` (the interrupt tests use `TMR0IF`, which a program can set).

How to port a module (the pattern used so far):

1. List the registers and bit fields the module names and compare them with the new part's device
   description (`devices/<part>.toml`); a name that is missing, or has different fields, is a difference.
2. Confirm each difference in the part's data sheet and errata, and cite the section in the module.
3. Gate the difference with `_has(...)` (one branch per layout, never a list of part numbers, so a future
   part with the same layout works without an edit). Add a pin default per part where the module owns a pin.
4. Check that the Q10 output is **byte-identical** to before (every byte counts), then run `cargo test`.
5. Update this table.

A module that does not support a part should say so with `#error` (as `intosc` does for a clock it cannot
make), never fall through to the Q10 registers.

## gpio
| Routine | Effect |
|---|---|
| `GpioAllDigital()` | `ANSELA/B/C = 0` (they reset to analog); a register the part lacks is skipped (`#if _has(REG)`) |
| `GpioPullUps(maskA, maskB, maskC)` | `WPUx`: a 1 bit enables that pin's pull-up |
| `GpioOpenDrain(maskA, maskB, maskC)` | `ODCONx`: a 1 bit makes that pin drive low only |

## delay
| Routine | Effect |
|---|---|
| `DelaySeconds(s)` | `s` x `DelayMs(1000)` |
| `DelayNop()` | a 5-cycle pause (call, `nop`, return) |

## timer (Timer0, Timer1, Timer2; FOSC/4 clock)
| Routine | Effect |
|---|---|
| `Timer0Start(prescale, period)` | 8-bit timer; one overflow per `(period+1) * 2^prescale` instruction cycles (`prescale` 0..15) |
| `Timer0Start16(prescale)` | 16-bit free-running timer |
| `Timer0Read()` | the 16-bit count (`TMR0L` is read first, which latches `TMR0H`) |
| `Timer0Expired()` | True once per overflow, clearing the flag |
| `Timer0Ack()` | clear the flag (call from your handler) |
| `Timer0EnableInterrupt()` / `Timer0DisableInterrupt()` | `PIE0.TMR0IE`; also `Enable(handler)` and, with priorities, clear `IPR0.TMR0IP` for a low handler |
| `Timer0Stop()` | |
| `Timer1Start(prescale)` | 16-bit free-running Timer1 (`prescale` 0..3 = 1:1..1:8); overflows every `65536 * 2^prescale` cycles |
| `Timer1StartSource(clk, prescale)` | as `Timer1Start` with any clock `T1Clk*` (`T1ClkPin` = T1CKI pin, rising edges, default RC0; also `T1ClkFosc4/Fosc/HfIntOsc/LfIntOsc/MfIntOsc/Sosc/Tmr0`). External clocks are synchronised (SYNC = 0). The pin must be digital (`GpioAllDigital`, `TRISx`); the first pulse after a start may be missed (data sheet 20.2.2) |
| `Timer1StartCounter(prescale)` | `Timer1StartSource(T1ClkPin, prescale)` |
| `FreqCount(pin, ms)` | rising edges on any pin (0..23) in `ms` milliseconds, counted by Timer1 through `T1CKIPPS` (a `LongWord`) |
| `Timer1StartGated(clk, prescale, source, activeHigh)` | counts only while the gate source `T1Gate*` (`T1GatePin` = T1G pin, default RB5; `Tmr0`, `Tmr2`, `Ccp1/2`, `Cmp1/2`) is high (`activeHigh`) or low; the gate is set before the timer is switched on |
| `Timer1StartPulse(clk, prescale, source, activeHigh, fullCycle)` | single-pulse gate: counts the first gate pulse after the call, then holds. `fullCycle` toggles the gate on each rising edge, so the time is a whole period of the source. Poll `Timer1PulseDone()`, then `Timer1Read()` |
| `Timer1GateState()` | the live gate (`T1GCON.GVAL`) |
| `Timer1Read()`, `Timer1Expired()`, `Timer1Ack()`, `Timer1Stop()` | as for Timer0 (`PIR4.TMR1IF`) |
| `Timer1EnableInterrupt()` / `Timer1DisableInterrupt()` | `PIE4.TMR1IE` |
| `Timer2Start(prescale, postscale, period)` | 8-bit Timer2, free-running period mode; flag every `(period+1) * 2^prescale * (postscale+1)` cycles (`prescale` 0..7 = 1:1..1:128, `postscale` 0..15 = 1:1..1:16) |
| `Timer2StartLimit(prescale, postscale, period, mode, source)` | Timer2 with a hardware-limit mode `T2Mode*` (`T2HLT.MODE`, Table 21-3: gate, reset, one-shot, mono-stable, level) and reset source `T2Rst*` (`T2RST`; `T2RstPin` = T2IN pin, default RC3, must be digital). In the triggered modes ON only arms the timer. A one-shot clears ON at the period match: test it with `Timer2Running()`, not the flag (the data sheet does not say the flag is set) |
| `Timer2Running()` | `T2CON.ON` |
| `Timer2Read()` | `T2TMR` |
| `Timer2Expired()`, `Timer2Ack()`, `Timer2Stop()` | as for Timer0 (`PIR4.TMR2IF`) |
| `Timer2EnableInterrupt()` / `Timer2DisableInterrupt()` | `PIE4.TMR2IE` |
| `Timer0OnExpire`, `Timer1OnExpire`, `Timer2OnExpire` | event variables of type `TTimerEvent` (`Event()`); assign a handler (`Timer0OnExpire = Tick`) |
| `Timer0Service()`, `Timer1Service()`, `Timer2Service()` | if the timer has overflowed (clearing the flag), call its `OnExpire` handler; call from the main loop, or from your own `Interrupt` inside `Save(0, Timer0Service)` |

PIC16F152xx (DS40002195E chapters 19-21): as the PIC16F171xx; `T1ClkPin`, `T1ClkFosc4`, `T1ClkFosc`, `T1ClkHfIntOsc`, `T1ClkLfIntOsc`, `T1ClkSfIntOsc`, `T1ClkMfIntOsc`, `T1ClkMfIntOsc32`, `T1ClkTmr0`; `T1GatePin`, `T1GateTmr0`, `T1GateTmr2`, `T1GateCcp1`, `T1GateCcp2`, `T1GatePwm3`, `T1GatePwm4`; `T2RstPin`, `T2RstCcp1`, `T2RstCcp2`, `T2RstPwm3`, `T2RstPwm4`; no secondary oscillator.

PIC16F183xx (DS40001839E chapters 26-28): Timer0 as above; Timer1 has `T1ClkFosc4`, `T1ClkFosc`, `T1ClkPin`, `T1ClkLfIntOsc` and the gate sources `T1GatePin`, `T1GateTmr0`, `T1GateCmp1`, `T1GateCmp2`, and `Timer1Read` reads `TMR1H` twice (no `RD16`); Timer2 prescales 1, 4, 16, 64 (`prescale` 0..3) and there are no `Timer2StartLimit`, `T2Mode*` or `T2Rst*`.

## serial (EUSART1, 8N1, TX on RC6, RX on RC7; PIC16F17126/46 and PIC18-Q41 UART1: TX on RC4, RX on RC5)
| Routine | Effect |
|---|---|
| `SerialInit(baud)` | PPS (`RC6PPS = 9`, `RX1PPS = 23`; PIC16F17126/46: `RC4PPS = 19`, `RX1PPS = 21`), pin directions, `BRG16 = BRGH = 1`, enables TX and RX. `n = round(FOSC / (4 * baud)) - 1`, computed at run time from `Clock` (a 32-bit divide, executed once) |
| `SerialWriteByte(b)`, `SerialWrite(text)`, `SerialNewLine()` | blocking send (`text` up to 80 characters) |
| `SerialWriteWord(v)`, `SerialWriteHex(v)` | unsigned decimal, two hex digits |
| `SerialAvailable()`, `SerialRead()` | receive; `SerialRead` waits and clears an overrun |
| `SerialReadTimeout(ms)`, `SerialReadLine(ms)`, `SerialWaitFor(text, ms)`, `SerialReadDec(ms)` | receive that gives up: a byte or -1; a line into `SerialLine`; True when `text` came; a decimal number into `SerialNumber`. `ms` is the longest wait for one byte. The same with the prefix `Serial2` |
| `SerialFlush()` | wait for the shift register to empty (`TRMT`) |
| `SerialOnRx` | event variable of type `TRxEvent` (`Event(ByVal c As Byte)`); assign a handler `Event OnByte(ByVal c As Byte)` |
| `SerialRxService()` | clear an overrun, and if a byte has arrived read it and call `SerialOnRx(byte)`; call from the main loop, or from your own `Interrupt` inside `Save(0, SerialRxService)` |

PIC18-Q41: `RC4PPS = 0x10` (UART1 TX), `U1RXPPS = 21`, `U1BRG`, `BRGS = 1`, `U1CON0 = 0xB0`, `U1CON2.RUNOVF = 1`, then
`U1CON1.ON`. `SerialWriteByte` waits for `U1FIFO.TXBF = 0`; `SerialAvailable` is `U1FIFO.RXBE = 0`; `SerialFlush` waits for
`U1FIFO.TXBE` and `U1ERRIR.TXMTIF`; a receive FIFO overflow flag (`RXFOIF`) is simply cleared, the receiver keeps running.

`Clock` must be FOSC in MHz. Baud accuracy follows the oscillator; the internal oscillator drifts
with voltage and temperature (data sheet 29.1.3), so use a crystal for anything beyond casual use.

PIC16F183xx: `RC4PPS = 20`, `RXPPS = 21` (RA4/RA5 with `RA4PPS = 20`, `RXPPS = 5` on the 8-pin PIC16F18313/PIC16LF18313); `TXIF`/`RCIF` are `PIR1` bits 4 and 5.

PIC16F152xx: `RC4PPS = 5` (TX1/CK1), `RX1PPS = 21` (RA4/RA5 with `RA4PPS = 5`, `RX1PPS = 5` on the 8-pin parts); `RC1IF` is `PIR1` bit 4. `SerialWriteByte` waits for TRMT, not TXIF (erratum 1.3.1: a byte written as the shift register empties can be sent twice).

## serial2 (EUSART2, 8N1, TX on RB6, RX on RB7; PIC18-Q41 UART2: TX on RC2, RX on RC1)
Same routines as `serial` with the prefix `Serial2` (`Serial2Init`, `Serial2WriteByte`, `Serial2Write`,
`Serial2NewLine`, `Serial2WriteWord`, `Serial2WriteHex`, `Serial2Available`, `Serial2Read`, `Serial2Flush`).
`RB6PPS = 0x0B` (EUSART2 TX/CK, Table 18-2), `RX2PPS = 0x0F` (RB7, Table 18-1), flags `TX2IF`/`RC2IF` are
`PIR3` bits 6 and 7, registers `SP2BRG`, `TX2STA`, `RC2STA`, `BAUD2CON`. RB6/RB7 are also the ICSP pins, so
disconnect the programmer while using them. Both modules can be included and run together. PIC18-Q41:
`RC2PPS = 0x13` (UART2 TX), `U2RXPPS = 17` (RC1, its reset selection); RC1 is also the default SPI1 data-in and
I2C1 data pin.

The PIC16F183xx parts have one EUSART: `serial2` stops with `#error`.
The PIC16F152xx parts have one EUSART as well: `serial2` stops with `#error`.

## adc (ADCC, basic mode, right-justified results: 10 bits on the Q10, 12 bits on the PIC16F17126/46 and PIC18-Q41)
| Routine | Effect |
|---|---|
| `AdcInit()` | ADC on, VDD/VSS reference, FOSC clock with the smallest TAD >= 1 us (ADCLK), hardware acquisition (`ADACQ`) of 5 us (counted in ADC clocks on the Q10, in FOSC clocks, 13 bits, on the Q41 and PIC16F171xx); runs a 32-bit calculation once from `Clock` |
| `AdcPin(ch)` | `TRISx`/`ANSELx` bit of channel 0..23 (RA0-7 = 0..7, RB = 8..15, RC = 16..23) |
| `AdcRead(ch)` | one conversion, 0..1023 (`AdcMax`: 4095 on the 12-bit parts). Channels `AdcChVss` 60, `AdcChTemp` 61, `AdcChDac` 62, `AdcChFvr` 63 are internal (PIC16F17126/46: 58, 59, 60, 62; `AdcChDac2` 61; its pins are RA0..RA5, RB4..RB7, RC0..RC7 and there is no first-conversion workaround; PIC18-Q41: `AdcChDac2` 58, `AdcChVss` 59, `AdcChTemp` 60, `AdcChDac` 61, `AdcChFvr` 62, `AdcChFvr2` 63, the same pins and no workaround, the charge pump `ADCP.CPON` is switched on by `AdcInit`, and the acquisition is 8 us) |
| `ADin(ch)` | one-call read: first call runs `AdcInit`, a channel change runs `AdcPin`, then `AdcRead` |
| `AdcReadAvg(ch, n)` | mean of n (1..64) conversions |
| `AdcMillivolts(raw, vrefMv)` | `raw * vref / AdcMax` (`AdcMax` = 1023 or 4095) |
| `AdcRefVdd()` / `AdcRefFvr(gain)` | reference VDD, or FVR at gain 1, 2, 4 (any value >= 4 is taken as 4, 0 as 1; waits for `FVRRDY`) |

Errata (DS80000832G): 1.4.4, the first conversion after a channel change is run and dropped (the
module remembers the last channel; code that writes `ADPCH` itself bypasses that). 1.4.1, `AdcRefFvr`
raises TAD to >= 8 us, which `ADCS` allows only up to `Clock` = 16 MHz; above that the slowest clock is
used and the missing-code workaround is not met, so use the VDD reference there. Not reentrant.
The temperature indicator needs `FVRCON.TSEN` (not set here). Source impedance above 10 kohm needs a
larger `ADACQ`.

PIC16F183xx: 10 bits (`AdcMax` 1023) on `ADCON0.CHS` / `ADCON1.ADCS`; `AdcChVss` 60, `AdcChTemp` 61, `AdcChDac` 62, `AdcChFvr` 63; the conversion clock is FOSC/n with TAD >= 1 us and the 5 us acquisition is a software delay after the channel or reference changes. The LF parts have no 4.096 V FVR gain.

PIC16F152xx: 10 bits (`AdcMax` 1023) on `ADCON0.CHS` / `ADCON1.CS` / `ADCON1.PREF`; `AdcChVss` 27 and `AdcChFvr` 30 (no `AdcChTemp` or `AdcChDac`); channels RA0..RA2, RA4, RA5 = 0..2, 4, 5, RB5..RB7 = 13..15, RC2..RC5 = 18..21; TAD >= 0.5 us (FOSC/n, n = 2 .. 64), the 5 us acquisition is a software delay, and `AdcInit` writes `CPCON = 01` (the charge pump is off at reset).

## eeprom (data EEPROM, 1024 bytes; 512 bytes on the PIC18-Q41, 256 on the PIC16F17126/46)
| Routine | Effect |
|---|---|
| `EepromRead(addr)` | byte at 0..1023 (0..511 on the Q41, 0..255 on the PIC16F17126/46); 255 for a larger address |
| `EepromWrite(addr, value)` | skips the write when the byte already holds `value`; otherwise unlock sequence, waits for the write to finish. Returns 1 when the byte reads back as `value`, 0 for an invalid address or a failed write |
| `EepromReadWord(addr)` / `EepromWriteWord(addr, value)` | 16-bit value, low byte first, at addr and addr + 1 (the write returns 1 only if both bytes were stored). Both bytes must be inside the array: a word write at the last byte or beyond stores nothing and returns 0, a word read there gives 255 in each byte that does not exist (65535 from 65535). Before 0.1.168 the address wrapped at 65535 and a word write there overwrote byte 0 |
| `EepromSize` | constant 1024 (512 on the Q41; the device's `_EepromBytes`) |

`NVMEN` is set only around the write and global interrupts are off for the unlock sequence (the previous
`GIE` is restored). Errata 1.6.1 (DS80000832G): `NVMERR` stays set across Resets after a Reset during a write
until one write succeeds, so it is not used as the error flag: success is the read-back, and the module clears
`NVMERR`. A write takes the device's programming time, during which the routine waits (the CPU is not stalled
by the hardware, but the next write cannot start). Not reentrant: do not call it from a handler and from the
main program.

PIC16F17126/46 (DS40002343F section 15.2): the data flash is read and written through `NVMREGS = 1`, `NVMADRH:NVMADRL = 70h:addr`,
`NVMDATL`; a read is `RD`, a write is `WREN`, the 55h/AAh unlock in `NVMCON2` and `WR`, with interrupts off for the unlock (the previous `GIE`
is restored). The CPU stalls until the write is done. `NVMCON1` is cleared afterwards (it clears `WRERR`, which is how a failed write is
cleared; success is the read-back as on the other parts). The data sheet and its errata (DS80001009E) show no erratum for the NVM.

PIC16F183xx and PIC16LF183xx: 256 bytes at F000h through `NVMREGS = 1`, `NVMADRH = 70h` (reads back F0h); the WRERR erratum is covered by the read-back.

PIC16F152xx: no data EEPROM, `eeprom` stops with `#error`; use `flashwrite`.

## flashwrite (program flash self-write)
PIC16F17126/46 (DS40002343F section 15.1): addresses are word addresses 0..16383 and a **sector is the 32-word row** (`FlashSectorWords` = 32,
`FlashLastSector` = 511); a word is 14 bits, so values are masked to 14 bits and an erased word reads 3FFFh. `FlashEraseSector` is a row erase
(`FREE`), `FlashWriteWord` loads the write latch of the word (`LWLO`) and then writes the latches to the row (the other latches hold 3FFFh, so
the other words of the row are left alone; the word must still be erased; after a write that fails with `WRERR` a latch may stay loaded and would be
written into another row by the next write, so reset before writing again), `FlashUpdateWord` reads the row into a 64-byte RAM image, erases it,
loads the 32 latches and writes (Example 15-4). Each operation is the 55h/AAh unlock and `WR` with interrupts off; the CPU stalls until it ends
(about 2 ms), so there is no wait on `WR`. `FlashReadWord` uses `RD`. The part has no flash erratum (DS80001009E). Write protection set in the
configuration words makes a write fail with `WRERR` (section 15.1.2.8), which the routines report. The rest of this section describes the PIC18 parts.

Addresses are PFM **word** addresses, 0..65535 (byte address / 2); a sector is 128 words (256 bytes), sectors 0..511.
On the PIC18-Q41 the flash is 8, 16 or 32 K words, so `FlashLastSector` is 63, 127 or 255 (the device's `_FlashBytes` / 256 - 1).
| Routine | Effect |
|---|---|
| `FlashReadWord(addr)` | the word at `addr` (65535 when erased); no unlock needed |
| `FlashEraseSector(sector)` | erases sector 0..511 (about 10 ms, CPU stalled). Returns 1; 0 for a sector above 511 (nothing is erased) or when `NVMERR` was set (write-protected) |
| `FlashWriteWord(addr, value)` | programs one **erased** word (about 50 us). Returns 1 when it reads back as `value` |
| `FlashUpdateWord(addr, value)` | replaces one word and keeps the other 127 of its sector (about 20 ms): nothing if it already holds `value`, a plain word write if erased, otherwise sector read, erase, `TBLWT` of the two bytes, sector write (Example 12-4). Returns 1 when it reads back as `value` |
| `FlashSectorAddr(sector)` | word address of the first word of the sector |
| `FlashSectorWords`, `FlashLastSector` | constants 128 and 511 |

Every unlock sequence ends `BSF NVMCON1,x` followed by two all-zero `NOP`s in the same `Asm` block: errata 1.9.1
(DS80000832G p.7), the first instruction after a self-write may not execute. Errata 1.6.2: no flash writes above 85 degrees C.
`NVMERR` is cleared before each operation and read right after it (errata 1.6.1), and writes are verified by read-back.
Global interrupts are off for each operation and `GIE` is restored; the CPU stalls during erase and write, so interrupts are
served late. Endurance is 10k erase/write cycles per sector. The compiler fills flash from address 0, so keep data in the
last sector (`FlashLastSector`) unless `basil --report` shows the code ends well below it; erasing a sector holding code
destroys it. Write protection (`WRTn` configuration bits) makes a write return 0. Not reentrant.

PIC18-Q41 (DS40002214G 10.3): the operations are `NVMCMD` in `NVMCON1` (word write 011, page read 010, page write 101,
page erase 110), the unlock sequence is `NVMLOCK = 55h, AAh` then `NVMCON0.GO`, and the write-error flag is `NVMCON1.WRERR`;
the errata 1.9.1 / 1.6.x `NOP`s above are Q10-only. `FlashUpdateWord` follows the data sheet's Word Modify (page read into
the buffer RAM, page erase, `TBLWT` of the two bytes, page write). The buffer RAM is the bank after the GPR banks (bank 9 / 13 /
21), which the compiler never allocates. `CONFIG8.WRTAPP` and `CONFIG7.DEBUG` must be 1; the configuration
words the compiler writes keep every bit that the pack's `implemented` mask omits at 1 (it used to clear them, which on the
Q41 turned on `DEBUG` and the write protection of the application block: self-writes to flash failed).

PIC16F183xx: as the PIC16F17126/46 (32-word row, 14-bit words); `NVMADRH` bit 7 reads 1.

PIC16F152xx: as the PIC16F17126/46 (32-word row, 14-bit words, 2K or 4K words of flash, so `FlashLastSector` is 63 or 127); the Memory Access Partition write-protect bits (CONFIG4) are off unless the program sets them.

## pwm (CCP1, CCP2, PWM3, PWM4 on Timer2; PIC18-Q41: six outputs of PWM1..PWM3; PIC16F17126/46: four outputs of PWM1 and PWM2)
PIC16F17126/46: the same module as on the Q41 with two PWM modules (DS40002343F chapter 29): channels 1..4 are PWM1S1P1, PWM1S1P2, PWM2S1P1,
PWM2S1P2 on RA0..RA5 (not RA3), RB4..RB7 (20-pin part), RC0..RC7, `RxyPPS` = 10 + channel (PWM1S1P1_OUT = 0Bh, Table 18-2); channels 5 and 6 are
refused. Everything else is as described for the Q41 next.

PIC18-Q41: channels 1..6 are PWM1S1P1, PWM1S1P2, PWM2S1P1, PWM2S1P2, PWM3S1P1, PWM3S1P2 on any of RA0..RA5 (not RA3),
RB4..RB7, RC0..RC7 (`RxyPPS` = 9 + channel); the period is shared (`PwmInit(hz)` sets `PWMxCLK` = FOSC, `PWMxCPRE`, `PWMxPR`;
`PwmSteps` is `PR + 1`, up to 65535, and a duty of `PwmSteps` is 100 %); `PwmInvert` restarts the module, because the slice
configuration may only be written while it is disabled. Timer2 is not used. The Q10 description below applies to the Q10.
| Routine | Effect |
|---|---|
| `PwmInit(hz)` | picks the Timer2 prescale and `T2PR` for `hz` (1..1000000; FOSC/4 clock): `f = FOSC / (4 * prescale * (T2PR + 1))`. Returns 1, or 0 when no prescale of 1..128 reaches `hz` or a channel is running. Starts nothing |
| `PwmFrequency()` / `PwmSteps()` | achieved frequency in Hz; duty cycle steps per period, `4 * (T2PR + 1)` (1024 only when `T2PR` = 255) |
| `PwmStart(ch, pin, duty)` | channel 1 = CCP1, 2 = CCP2, 3 = PWM3, 4 = PWM4, on pin 0..23 (RA0..RC7, as the `Adc` channels): CCP1/CCP2 on ports B and C, PWM3/PWM4 on ports A and C. `duty` in steps. Follows the data sheet set-up order (driver off, routing, duty, Timer2 on, wait for the first overflow, driver on) so the first period is complete. Returns 0 for a bad channel or pin, a pin used by another running channel, or no successful `PwmInit`; a running channel is restarted |
| `PwmDuty(ch, duty)` / `PwmPercent(ch, pct)` | new duty cycle of a running channel (steps, or 0..100 %; the percentage is worked out as `(PwmSteps / 4) * pct / 25` in a Word, the same value as `PwmSteps * pct / 100`, because `PwmSteps` is `4 * n` with `n` at most 256) |
| `PwmInvert(ch, inverted)` | output polarity of PWM3/PWM4 (`PWMxCON.POL`); returns 0 for channels 1 and 2 |
| `PwmStop(ch)` | module off, pin back to an input driven by `LATxy`; Timer2 stops with the last channel |

All channels share one frequency; each has its own duty. The module owns Timer2 while a channel runs: do not
use the `Timer` module's Timer2 routines or a Timer2 interrupt then (`PwmStart` waits for `TMR2IF` and clears it).
With `T2PR` = 255 the highest duty is 1023 of 1024 steps (99.9 %), so 100 % is not reachable that way. The duty
registers are double buffered and copied at the period match; if that falls between the two byte writes of one
update, one period can use a mixed value. Not reentrant: do not call it from a handler and from the main program.

PIC16F183xx: CCP1, CCP2, PWM5 and PWM6 are channels 1..4 on Timer2 (prescalers 1, 4, 16, 64); `RxyPPS` 0Ch, 0Dh, 02h, 03h.

PIC16F152xx: CCP1, CCP2, PWM3 and PWM4 are channels 1..4 on Timer2 (prescalers 1..128, `T2CLKCON`); `RxyPPS` 01h, 02h, 03h, 04h; any pin of the part; there is no `CCPTMRS`.

## i2c (MSSP1 host; PIC18-Q41: software host)
PIC16F17126/46: the MSSP1 host as on the Q10 (DS40002343F chapter 31) with the pins of the Q41 numbering: 0..23, RA0..RA5 except RA3, RB4..RB7 and
RC0..RC7 as the part has them; `RxyPPS` 27 = SCL1 and 28 = SDA1 (Table 18-2), `SSP1CLKPPS`/`SSP1DATPPS` = the pin number; `SSP1IF` is `PIR5` bit 2 and
`BCL1IF` bit 3. Erratum 1.2.1 (start and stop flags may be set when I2C is enabled, silicon B0 only) does not touch this module, which clears
`SSP1IF` before each step and does not use the start or stop interrupts.

PIC18-Q41: the same routines, in software on two ordinary pins (any of RA0..RA5 except RA3, RB4..RB7, RC0..RC7, numbered 0..23
as the `Adc` channels), open drain by TRIS, `hz` 2000..400000 (the real clock is lower, much lower on a slow `Clock`), clock
stretching waited for, arbitration checked by reading SDA back. The I2C1 peripheral cannot carry the step-by-step API: it counts the
bytes of a transfer in hardware (`I2C1CNT`), the host sends the Stop or waits for the Restart when the count reaches 0, and it decides
the acknowledge of a received byte from the count, not from the program (`I2cReceive(ack)` decides it after the byte has arrived; a byte
sent is only acknowledged-or-not at the next byte or at the pause). So the peripheral is offered through block routines, selected by
`#option I2c = Hardware` in the program (see "PIC18-Q41 hardware host" below). The Q10 description below applies to the Q10.
| Routine | Effect |
|---|---|
| `I2cInit(hz, scl, sda)` | MSSP1 as I2C host at `hz` (1..1000000): `f = FOSC / (4 * (SSPxADD + 1))`, divider rounded up so the clock is at or below `hz`. `scl`, `sda` are pins 8..23 (ports B and C, as the `Adc` channels; reset selection RC3/RC4 = 19/20), routed through `SSP1CLKPPS`/`SSP1DATPPS` and `RxyPPS` = 0x0F/0x10. Returns 1, or 0 for a bad pin, equal pins, or no `SSPxADD` of 3..255 (at 64 MHz the slowest clock is 62 kHz) |
| `I2cStart()` / `I2cRestart()` / `I2cStop()` | one condition each; return a status code |
| `I2cSend(b)` | address byte (7-bit address << 1 or R/W) or data; 0 acknowledged, 3 not acknowledged |
| `I2cReceive(ack)` | one byte, then ACK (`True`) or NACK (`False`); returns 0 and sets the status on an error |
| `I2cPing(addr)` | True when a client acknowledges the 7-bit address |
| `I2cWriteReg(addr, reg, value)` / `I2cReadReg(addr, reg)` | register write / read (read: Restart after the register byte) |
| `I2cStatus()` | status of the last routine: 0 ok, 1 timeout, 2 bus collision, 3 no acknowledge, 4 not initialised |
| `I2cOff(scl, sda)` | MSSP off, both pins back to `LATxy`; call it before `I2cInit` on other pins |

The host mode does not queue events, so every step waits for the previous one; each wait is bounded (a stuck
or unpulled bus gives status 1, after which the hardware may still be mid-operation: call `I2cInit` again to reset it). `I2cPing` ends with a Stop, so `I2cStatus` afterwards describes the Stop, not the address byte. The module polls `SSP1IF` and clears `BCL1IF`/`WCOL`, so keep the MSSP1
interrupt disabled. `SMP` (slew rate) is cleared for clocks between 100 kHz and 1 MHz. External pull-ups are
needed. Single host only; not reentrant.

PIC18-Q41 hardware host (`#option I2c = Hardware` in the main program; ignored on parts with an MSSP, whose host is always hardware). The module
drives I2C1 in host mode, 7-bit addressing, `ABD = 1` (a write to `I2C1TXB` starts the transfer), `I2C1CLK` = FOSC/4, `FME = 0`:
`SCL = FOSC / (4 * 5 * (BAUD + 1))`, so `Clock` must be FOSC in MHz, the divider is rounded up (the clock is at most `hz`) and the slowest clock is
FOSC / 5120 (12.5 kHz at 64 MHz). `I2cInit(hz, scl, sda)` accepts `hz` 1..400000 and the same pins as the software host (0..23 as the part has them,
RA3 refused); any pin works through `RxyPPS` (33 = SCL1, 34 = SDA1; bidirectional, so `I2C1SCLPPS`/`I2C1SDAPPS` select the same pin), with the
standard input levels except on the I2C pads (RB4 = SDA1 and RB6 = SCL1 on the 20-pin parts, RC0/RC1 on the 14-pin ones; not configured here).
The pins are made digital and open drain; the module overrides TRISx and LATx [DS40002214G 21.3]. Routines:

| Routine | Effect |
|---|---|
| `I2cReadRegs(addr, reg, n)` | Start, address + W, `reg`, Restart, address + R, `n` (1..8) bytes into `I2cBuf(0..n-1)`, the last not acknowledged, Stop. Returns the status (also in `I2cStatus`) |
| `I2cWriteRegs(addr, reg, n)` | Start, address + W, `reg`, `I2cBuf(0..n-1)` (n 1..8), Stop. Returns the status |
| `I2cProbe(addr)` | Start, address + W, Stop. Returns the status (0 acknowledged, 3 not) |
| `I2cPing`, `I2cWriteReg`, `I2cReadReg`, `I2cStatus`, `I2cOff` | as above (built on the block routines in hardware mode) |
| `I2cBuf(8)` | the data of the block routines |

`I2cStart`, `I2cRestart`, `I2cStop`, `I2cSend` and `I2cReceive` do not exist in hardware mode (a program that calls them stops with an unknown-routine
error; `aht30`, which uses only them, stops with `#error`; `oled` leaves out its I2C connection, so `OledInitI2c` does not exist and the SPI connection
works). The block routines exist on every backend (built from the step routines on the software and MSSP hosts, where they also set `I2cStatus`), so a
program written with them builds with and without the option. In hardware mode `I2cOff` ignores its arguments: the module remembers the pins of the last
`I2cInit`, takes their `RxyPPS` back to `LATxy` and makes them push-pull again; call it before an `I2cInit` on other pins. Status 5 means a count outside 1..8 (nothing is sent). Every
wait is bounded (20000 polls); after a timeout or a collision the module sends a Stop (P) if it is still active and is switched off
and on again, so the next call starts from idle (a not acknowledge needs no reset: the module has stopped itself, and a register-phase NACK of a read gets its
Stop with P). The module polls its flags and uses no interrupt; not reentrant; single host. The flags are cleared
and the buffers emptied before each transfer, and 25 us are waited after enabling the module (errata DS80000901H 1.3.2). With the option, `rtcc` moves
its blocks with these routines (`ReadBlock`/`WriteBlock` are thin wrappers); without it `rtcc` is byte-for-byte what it was.

PIC16F183xx: the same hardware host; `RxyPPS` 24 = SCL1 and 25 = SDA1; `SSP1IF`/`BCL1IF` are `PIR1` bits 3 and 2.

PIC16F152xx: the same hardware host; `RxyPPS` 07h = SCL1 and 08h = SDA1; `SSP1IF`/`BCL1IF` are `PIR1` bits 1 and 2.

## softserial (asynchronous serial on any two pins)
| Routine | Effect |
|---|---|
| `SoftInit(tx, rx, baud, inverted)` | pins 0..23 (as `pinio`), speed from `Clock`; False when the rate cannot be made |
| `SoftWriteByte(b)`, `SoftWrite(text)`, `SoftNewLine()` | send |
| `SoftReadByte(ms)`, `SoftAvailable()` | receive a byte (-1 after `ms` ms, -2 for a framing error) / the start bit is there |
| `SoftHoldIrq(on)` | hold the global interrupt enable off during a byte (default True) |

Portable (PIC18 and PIC16 enhanced mid-range). Bit times in cycles, so the baud rate is checked in the simulator: `scripts/test_softserial.py`; `tests/exec/lib_softserial_rx.bas` runs received bytes through basil-sim; `tests/hw/softserial_echo.bas` is the bench program for a real part.

## spi (MSSP1 host)
PIC16F17126/46: pins numbered 0..23 as on the Q41 (RA0..RA5 except RA3, RB4..RB7 and RC0..RC7 as the part has them; SCK on RA3 is refused);
`RxyPPS` 27 = SCK1, 28 = SDO1 (Table 18-2), `SSP1CLKPPS`/`SSP1DATPPS` = the pin number. The rest is as for the Q10 below.

| Routine | Effect |
|---|---|
| `SpiInit(hz, mode, sck, sdo, sdi)` | MSSP1 as SPI host, mode 0..3 (CKP = CPOL; CKE = 1 for modes 0 and 2). Pins 8..23 (ports B and C, as the `Adc` channels); `sdo` = 255 for receive only. Clock `FOSC / 4` for `hz` of `FOSC / 4` or more, else `FOSC / (4 * (SSPxADD + 1))` with `SSPxADD` 1..255, rounded to at or below `hz` (lowest `FOSC / 1024`). Input sampled mid-bit (`SMP` = 0). Returns 1, or 0 for a bad pin or mode, a pin used twice, or a clock out of range |
| `SpiTransfer(b)` | sends `b`, returns the byte received at the same time |
| `SpiWrite(b)` / `SpiRead()` | send ignoring the reply / receive (sends 255) |
| `SpiStatus()` | 0 ok, 1 timeout (bounded wait for `BF`), 4 not initialised |
| `SpiOff(sck, sdo)` | MSSP off, `SCK` and `SDO` back to `LATxy`; call before `SpiInit` on other pins |

The chip select is not part of the module (use `Gpio` or a port bit). The module owns MSSP1 (not together with `I2c`),
does not use its interrupt, and is not reentrant.

PIC16F183xx: `RxyPPS` 24 = SCK1 and 25 = SDO1.

PIC16F152xx: `RxyPPS` 07h = SCK1 and 08h = SDO1.

## intosc (internal oscillator set-up)
`Include "intosc"` makes the hardware run at `Clock`: its start-up code, run before the main program, writes `OSCFRQ` and
`OSCCON1` (HFINTOSC, divider) and waits for `OSCCON3.ORDY` and `OSCSTAT.HFOR`, each wait bounded. `Clock` must be 64, 48,
32, 16, 12, 8, 4, 2, 1 (HFINTOSC, no divider) or 0.5, 0.25, 0.125, 0.0625, 0.03125 (1 MHz divided by 2..32); any other value
is a compile-time error. Needs `CSWEN = ON` in `Config` unless `Clock` already is the `RSTOSC` speed. Include it first.
| Routine | Effect |
|---|---|
| `SetClock(mhz)` | HFINTOSC at `mhz` (1, 2, 4, 8, 12, 16, 32, 48 or 64), divider 1:1; True when the switch completed and read back, False (nothing written) for another value |
| `SetClockDiv(mhz, shift)` | the same divided by 2^`shift` (`shift` 0..9) |

A run-time change does not change the compile-time `Clock` that `DelayMs`/`DelayUs` and the library timing use. Full
description, register order and the design background: `docs/CLOCK.md`.

PIC16F183xx: `#error`; set the speed with `Config RSTOSC = HFINT32` (32 MHz) or `HFINT1` and give `Clock` to match, then check with `System.SysClockOk()`.

PIC16F152xx: `Clock` = 32, 16, 8, 4, 2 or 1 writes `OSCFRQ.FRQ`; there is no divider and no clock switching, so the source must be `RSTOSC = HFINTOSC_32MHZ` or `HFINTOSC_1MHZ`.

## system (reset cause, wake-up cause, clock check)
| Routine | Effect |
|---|---|
| `SysResetCause()` | cause of the latest Reset not yet cleared, from `PCON0`, tested in this order: 1 power-on, 2 brown-out, 7 stack overflow, 8 stack underflow, 5 watchdog window violation, 4 watchdog time-out, 3 MCLR pin, 6 `RESET` instruction, 0 none |
| `SysResetFlags()` | the raw `PCON0` value |
| `SysClearResetFlags()` | all `PCON0` flags to their inactive state (`PCON0` = 63); call it after reading the cause, because hardware never clears a flag |
| `SysWakeCause()` | wake-up / power-down cause from `STATUS` `TO` and `PD` (read-only; bits 4 and 3 on PIC16, 6 and 5 on PIC18): 0 none, 1 woke from Sleep (not by the watchdog), 2 woke from Sleep by a watchdog time-out, 3 watchdog time-out while running |
| `SysWakeFrom(st)` | the same decoding of a given `STATUS` value |
| `SysClearWakeFlags()` | `TO` and `PD` back to 1 (`clrwdt`, which also restarts the watchdog count); call it after reading the cause |
| `SysClockHz()` | system clock in Hz from `OSCCON2` and `OSCFRQ`: HFINTOSC (1, 2, 4, 8, 12, 16, 32, 48 or 64 MHz) divided by 1..512; 0 for any other source or a reserved code. Nominal frequency (`OSCTUNE` ignored) |
| `SysClockFrom(cosc, cdiv, hffrq)` | the same conversion from given field values |
| `SysClockOk()` | True when `SysClockHz()` equals `Clock` |
| `Sleep()` | the `sleep` instruction and two NOPs; returns on a wake-up |
| `Sleep(seconds)`, `Snooze(period)` | timed sleeps, the watchdog as timer (WDTCON or WDTCON0, PS bits 5:1, enable bit 0; Config `WDTE = SWDTEN` or `ON`) |

A flag left from an earlier Reset is reported until it is cleared; after a power-on Reset the brown-out flag is
unknown, so power-on is tested first. The module does not change the clock (that is `intosc`, `docs/CLOCK.md`): `DelayUs`/`DelayMs`, `Serial`,
`Pwm`, `I2c`, `Spi` and `Adc` compute from the compile-time `Clock`, so a run-time change makes them wrong.
`SysClockOk` is the run-time check that the oscillator really runs at `Clock`.

PIC16F183xx: no window-violation cause (`PCON0` has no such bit); `SysClockFrom` decodes COSC 110 (HFFRQ 1, 2, 4, 8, 12, 16, 32 MHz) and COSC 000 (2x PLL: 16, 24, 32 MHz).

PIC16F152xx: no window-violation cause; `SysClockFrom(cosc, 0, frq)` takes COSC 0 or 2 and `OSCFRQ.FRQ` 0..5 = 1, 2, 4, 8, 16, 32 MHz (any divider code gives 0).

## lcd (HD44780U character LCD, 4-bit)
Source: the HD44780U data sheet (`HD44780.pdf`): instruction table (Table 6), "Initializing by Instruction" (Figure 24), DDRAM map, bus timing. Pins `0..23` (RA0 = 0, RB0 = 8, RC0 = 16 ...); R/W tied to ground, the busy flag is not read (fixed waits: 50 us, 2 ms after Clear/Home).

| Routine | Effect |
|---|---|
| `LcdInit(rs, en, d4, d5, d6, d7, lines)` | six pins to digital outputs, the 4-bit initialisation by instruction (about 55 ms), display on, no cursor, increment, no shift. `lines` 1 or 2 (5 x 8 font). Returns 1, or 0 for a bad `lines`, a pin above 23 or a pin used twice |
| `LcdCommand(c)` | any instruction byte |
| `LcdClear()` / `LcdHome()` | clear display / return home |
| `LcdDisplay(on, cursor, blink)` | display on/off control |
| `LcdShift(whole, right)` | shift the cursor or the whole display one position |
| `LcdGoto(col, row)` | `col` 0..39, `row` 0..1 (second line at DDRAM 40H); one-line displays: `col` 0..79, `row` 0 |
| `LcdSetAddress(a)` | raw DDRAM address (for four-line displays, whose wiring the data sheet does not describe) |
| `LcdWriteChar(ch)` / `LcdWrite(s)` / `LcdWriteWord(v)` / `LcdWriteHex(v)` | character, string, unsigned decimal, two hex digits |
| `LcdCustomRow(slot, row, bits)` | one row of user character 0..7; follow with `LcdGoto` before writing text |

Uses read-modify-write on `LATA/B/C`: not for use from a handler and the main program together.

## glcd (graphic LCD: KS0108, T6963C, ST7920 on an 8-bit parallel bus)
Source: Samsung S6B0108 Ver. 0.0 (the KS0108's driver), Toshiba T6963C 2002-01-07, Sitronix ST7920 V4.0 (all in `docs/`, git-ignored). Tests: `tests/exec_glcd_ks`, `tests/exec_glcd_t69`, `tests/exec_glcd_st79` run the real module against a software model of each controller in the simulator (`glcd_models_in_simulator`); **nothing has run on a real display.** The 8 data lines take a whole port (`data` = 8 or 16 for port B or C; port A is refused, RA3 is input only on most parts); the control lines are pins 0..23 as in `lcd`. All three backends are linked into a program that calls the drawing routines (about 6 KB on the PIC18, 4 K words on a PIC16), so a part with 2 K words of flash (PIC16F152xx 2 K parts) does not fit.

| Routine | Effect |
|---|---|
| `GlcdInitKs0108(data, rs, rw, en, cs1, cs2, rst, csHigh)` | 128 x 64 from two KS0108 chips; `csHigh` True for active-high chip selects. Returns 1, or 0 for a bad pin / bus |
| `GlcdInitT6963(data, wr, rd, ce, cd, rst, xres, yres, fontWidth)` | any size (columns xres / fontWidth at most 64, `fontWidth` 6 or 8 as the module's FS and MD pins). Sets graphic home 0, text area after it, CG RAM after that, OR mode, text and graphics on |
| `GlcdInitSt7920(data, rs, rw, en, rst, folded)` | `folded` True: the usual 128 x 64 module (rows 32..63 in words 8..15; **not stated in the data sheet**); False: Table 7 as is, 256 x 64. 8-bit parallel only |
| `GlcdClear()` | clear graphics (and the T6963C text layer), text position home |
| `GlcdPlot(x, y)` / `GlcdUnplot(x, y)` / `GlcdSetPixel(x, y, on)` / `GlcdPixel(x, y)` | set / clear / either / read (1 or 0); outside the display is ignored |
| `GlcdLine(on, x0, y0, x1, y1)` / `GlcdLineTo(on, x, y)` | Bresenham line; LineTo starts at the end of the last line |
| `GlcdBox(on, x, y, size)` / `GlcdCircle(on, x, y, r)` | outline of a square / circle centred on (x, y) |
| `GlcdWriteByte(row, col, v)` / `GlcdReadByte(row, col)` | `LCDwrite` / `LCDread` counterpart: KS0108 page 0..7 and x 0..127 (bit 0 on top); T6963C pixel row and byte column; ST7920 pixel row and byte column |
| `GlcdTextAt(col, row)` / `GlcdWriteChar(ch)` / `GlcdWrite(s)` / `GlcdWriteWord(v)` | text in the 5 x 7 font on a 6 x 8 cell grid (T6963C: its own text layer and CG ROM) |
| `GlcdCommand(c)` / `GlcdCommand(c, d1)` / `GlcdCommand(c, d1, d2)` | `Toshiba_Command` counterpart: any T6963C command (data first); ignored on the other controllers |
| `GlcdUdg(code, img)` / `GlcdWriteCode(code)` | `Toshiba_UDG` counterpart: user character 128..255 from 8 row bytes, and a raw text code (T6963C) |

## epaper (WeAct 2.13" / 2.9" e-paper, SSD1680, 4-wire SPI)
Source: Solomon Systech SSD1680 Rev 0.14 (`docs/SSD1680_Datasheet.pdf`: command table 7-1, data entry 8.3, RAM windows 8.4-8.6, operation flow 9.1, SPI 6.1 and 12.1), the WeAct panel specs and schematic (`docs/WeAct-*`), and the vendor's example code (github.com/WeActStudio/WeActStudio.EpaperModule), which supplies what the data sheet does not (marked `[WeAct]` in the source). Test: `tests/exec_epaper` runs the real module against a software model of the SSD1680 (`epaper_model_in_simulator`); **nothing has run on a real panel.** No frame buffer: bytes of 8 pixels are written straight to the controller RAM (`x`, `w` multiples of 8). Fast and partial refresh are not provided.

| Routine | Effect |
|---|---|
| `EpdInit(size, threeColour, dc, cs, res, busy)` | size 0 = 2.13" (122 x 250), 1 = 2.9" (128 x 296); returns 1, 0 (bad argument) or 2 (BUSY stuck) |
| `EpdClear(colour)` / `EpdFillRect(x, y, w, h, colour)` | colours 0 white, 1 black, 2 red |
| `EpdTextColour(c)` / `EpdTextAt(col, row)` / `EpdWriteChar(ch)` / `EpdWrite(s)` | 5 x 7 font in 8 x 8 cells |
| `EpdWindow(x, y, w, h)` / `EpdBegin(plane)` / `EpdPut(b)` / `EpdEnd()` | stream bitmap bytes into plane 0 (black / white) or 1 (red) |
| `EpdUpdate()` / `EpdSleep()` / `EpdWake()` | refresh (22h F7h, 20h, wait BUSY) / deep sleep / hardware reset and start-up code |

## oled (SSD1309 128 x 64 OLED, I2C or 4-wire SPI)
Source: the SSD1309 data sheet Rev 1.1 (`Solomon_SSD1309_v1.1.pdf`): command tables 9-1..9-5, I2C format 8.1.5, 4-wire SPI 8.1.3, power-on 8.8, timing 13-4/13-6. The caller sets up the bus first (`I2cInit` at no more than 400 kHz, or `SpiInit` in mode 0 at no more than 10 MHz). The panel supply VCC is external. No frame buffer (the interfaces are write-only): the display is written in 8-pixel pages, byte = one column, bit 0 on top.

| Routine | Effect |
|---|---|
| `OledInitI2c(addr, res)` | I2C address `60` or `61` (0x3C/0x3D); `res` = RES# pin 0..23 or 255. Unlock, horizontal addressing, clear RAM, display on. Returns 1 when everything was acknowledged |
| `OledInitSpi(dc, cs, res)` | D/C#, CS# (255 = tied low) and RES# (255 = none) on pins 0..23. Returns 0 for a bad pin or a pin used twice |
| `OledStatus()` / `OledClearStatus()` | first `I2c` error code since init (0 = fine; always 0 for SPI) |
| `OledOn(on)`, `OledContrast(v)`, `OledInvert(b)`, `OledAllOn(b)`, `OledFlip(rotated)` | AFh/AEh, 81h, A7h/A6h, A5h/A4h, A1h+C8h / A0h+C0h |
| `OledGoto(col, page)` | column 0..127, page 0..7 |
| `OledTextGoto(x, line)` | character cell 0..20, line 0..7 (6 x 8 pixel cells) |
| `OledData(b)` / `OledFill(pattern)` / `OledClear()` | one column byte / whole RAM / clear |
| `OledWriteChar(ch)` / `OledWrite(s)` / `OledWriteWord(v)` / `OledWriteHex(v)` | text in a 5 x 7 font (X11 "5x7", public domain; ASCII 32..126) |
| `FontByte(i)` | byte `i` (0..474) of the font table (a `Const` array in program memory) |
| `OledBitmap(x, page, w, img)` | draws `w` columns of the `Const` byte array `img` straight to the display at column `x`, page `page` (no frame buffer; 8 pixel rows high, bit 0 on top) |

Pixel drawing uses a 1024-byte frame buffer in RAM (the display cannot be read back). It is linked only by a program that calls one of the commands below, so text-only programs pay nothing. The commands change the buffer; `OledUpdate` sends it to the display. Coordinates: `x` 0..127 left to right, `y` 0..63 top to bottom; points outside the screen are ignored.

| Routine | Effect |
|---|---|
| `OledPixel(x, y, on)` / `OledPoint(x, y)` | set or clear one pixel / read it back (1 or 0) |
| `OledBufFill(pattern)` / `OledBufClear()` | fill or clear the whole buffer |
| `OledUpdate()` | send the buffer to the display |
| `OledLine(x0, y0, x1, y1, on)` | line, `Integer` coordinates, clipped to the screen |
| `OledRect(x, y, w, h, on)` / `OledFillRect(x, y, w, h, on)` | rectangle outline / filled |
| `OledBufBitmap(x, y, w, pages, opaque, img)` | `Const` image into the buffer at any pixel position: `w` columns, `pages` rows of 8 pixels; `opaque` also clears the image's clear pixels |
| `OledBufChar(x, y, ch, on)` / `OledBufText(x, y, on, s)` | 5 x 7 text at any pixel position, set pixels only (so text can go over a picture) |

## pinio (pin access by number)

Support module for the bit-banged modules. Pins are numbered 0..23 as in `lcd` (RA0 = 0, RB0 = 8, RC0 = 16).
`PinOk(pin)`, `PinSet(pin, level)`, `PinGet(pin)`, `PinOutput(pin)`, `PinInput(pin)` (both clear ANSELx),
`PinDriveLow(pin)` / `PinRelease(pin)` for an open-drain line without ODCONx. Pins the part lacks (port B on
the 14-pin PIC18-Q41 and PIC16F13123..13125, port B and C on the PIC16F13113) are refused by `PinOk` and ignored.
Works on every supported family (only LATx, PORTx, TRISx and ANSELx are used).

## shift (ShiftOut / ShiftIn)

Bit-banged shift for 74HC595/74HC165, DACs, ADCs: `ShiftOut(data, dataPin, clkPin, lsbFirst, bits)`,
`ShiftIn(dataPin, clkPin, lsbFirst, bits)` (1..8 bits) and `ShiftOut16` / `ShiftIn16` (1..16 bits). Clock idles
low, data changes while low and is valid on the rising edge (SPI mode 0). Bad pins or bit counts do nothing.
Test `tests/exec/lib_shift.bas` (set-up only; the simulator has no pin model); built for every family.

## buttons (Counter, Button)

Polled, on any pin 0..23 as in `pinio`. `Counter(pin, ms)` counts rising edges in about `ms` ms (10 to 40 per cent long; edges faster than about 40 kHz missed). `Button(pin, down, delay, rate, ByRef state)` is a debounced push button with auto-repeat: True for a press to act on, `state` a caller's Byte (0 at start). Test `tests/exec/lib_buttons.bas`. Include as `Include "buttons"`; calls are `Buttons.Button(...)`.

## pulse (PulseIn, PulseOut, RCin, Pot, Servo, PwmPin, Sound, Sound2, Freqout)

Bit-banged pulse measurement and generation on any pin (pins 0..23 as in `pinio`; a missing pin or a zero count stops a routine, a
measurement then returns 0). Time is kept by polling and cycle-counted delays; one "unit" is a 10 us poll plus the loop time, so units are
10 to 14 us at 16 MHz and above and the results are not exact: calibrate with a known pulse, or use a hardware timer. Interrupts lengthen every time.

| Routine | Effect |
|---|---|
| `PulseOut(pin, period, level)` / `PulseOut(pin, period)` | a pulse of `period` units, high (`level` True) or low; the two-argument form is the opposite of the pin's present level. The pin becomes an output |
| `PulseIn(pin, level)` | `Word`: width in units of the next pulse at `level` (the clock starts at the edge into `level`); 0 after about 0.65 s without a complete pulse. The pin becomes an input |
| `RCin(pin, level)` | `Word`: units the pin stays at `level` (1 if it is not at `level` at the call, 0 after 65535 units): times an R-C network |
| `Pot(pin, scale)` | `Byte`: discharges the capacitor for 1 ms, times the rise with `RCin`, returns `units * scale / 256` (at most 255) |
| `Servo(pin, width)` | one pulse of `width` microseconds (500..2500) high; call it every 20 ms |
| `PwmPin(pin, duty, cycles)` | software PWM for an R-C filter: `cycles` periods of 256 steps of 10 us, high for `duty` steps (0 = always low, 255 = always high); the pin is an input afterwards |
| `Sound(pin, note, duration)` | note 0 silence, 1..127 a tone of about 78.74 x note Hz, 128..255 noise; `duration` in 10 ms |
| `Sound2(pin1, pin2, f1, f2, ms)` | two tones (Hz, 0 = silent) at once on two pins for `ms` ms, from one 10 us time base: exact to about 10 % |
| `Freqout(pin, ms, f1)` / `Freqout(pin, ms, f1, f2)` | square wave of `f1` Hz (8..32767) for `ms` ms, or two added on one pin (10 us base, 197 Hz and up, about 10 %) |
| `WaitUs(us)` | delay of `us` microseconds (a `Word`) |

Tests: `tests/exec/lib_pulse.bas` (set-up and final pin states) and `tests/exec_pins/lib_pins_model.bas` (against a pin model: waveforms measured by `PulseIn`, `RCin`
and `Pot`, and the pin writes of the others counted). Not run on hardware.

## irremote (SonyIn, RC5In)

Infrared remote decoders for the output of a receiver module that idles high and goes low during a burst. `SonyIn(pin)` reads a Sony SIRC 12-bit frame
(the pulse widths are judged against the header, so the poll time does not matter); `RC5In(pin)` reads a Philips RC5 frame (the line is sampled at fixed
times, so it needs a `Clock` of 16 MHz or more and no interrupts). Both return a `Word`, command in the low byte and system in the high byte, or 65535 when
no valid frame arrives in about 0.65 s. `RC5In` returns the 7-bit command (the second start bit is the inverse of command bit 6) and drops the toggle bit.
Tested: `SonyIn` against a waveform in `tests/exec_pins/lib_pins_model.bas`; `RC5In` only for the no-signal case (its timing is in microseconds, which the pin model cannot play).

## x10 (Xout, Xin: X-10 power-line control)

`Xout(dataPin, zeroPin, house, key, reps)` sends a code through a PL513 or TW523; `Xin(dataPin, zeroPin, timeout, value)` receives one through a TW523.
`house` is 0..15 (A..P), `key` 0..15 is the unit 1..16 and 16 + n a function (`UnitOn` 18, `UnitOff` 26, `UnitsOff` 28, `LightsOn` 20, `LightsOff` 16,
`Bright` 22, `DimIt` 30), sent as the X-10 protocol defines them. Frames go out `reps` times (at least 2) in pairs with three silent cycles between pairs, except `Bright` and `DimIt`.
`Xin` gives house in the high byte and key in the low byte and returns False on a timeout (in half-cycles; 0 = until the zero-cross pulses stop), a frame whose bit and complement agree,
or no zero-cross pulses for about 50 ms. The interface outputs are open collector: use 4.7 k pull-ups. `CodeOf` / `NumberOf` convert a house or unit number to the 4-bit line code and back.
The start code, bit order and function codes follow the X-10 protocol as recalled from memory; the 1 ms burst
and the 0.5 ms sampling delay are not measured on a real interface. Tested against a pin model: frames recorded by `Xout` are played back through `Xin`. Never connect a pin to the AC line.

## aht30 (AHT30 temperature and humidity sensor, I2C)
Source: the Aosong AHT30 data sheet (Sep 2023): address 0x38 (5.1), measurement command 0xAC 0x33 0x00 and 80 ms wait (5.2), status word (Table 9), CRC8 (5.2), conversion formulas (5.2), I2C timing (Table 8). The caller sets up the bus first (`I2cInit` at no more than 400 kHz, external pull-ups); sample at most once a second to keep self-heating under 0.1 C (2.4). Results: temperature `Integer` in 1/100 degree C, humidity `Word` in 1/100 %RH, rounded to nearest, written only on status 0.

| Routine | Effect |
|---|---|
| `Aht30Init()` | waits 5 ms (power-up time) |
| `Aht30Start()` | sends 0xAC 0x33 0x00; returns the status |
| `Aht30Fetch(temp, rh)` | reads the 7-byte frame at least 80 ms after `Aht30Start`, checks busy and CRC8, converts; returns the status |
| `Aht30Measure(temp, rh)` | `Aht30Start`, `DelayMs(80)`, `Aht30Fetch` |

Status: 0 ok, 1..4 as `I2cStatus` (timeout, collision, no acknowledge, I2c not initialised), 5 busy (fetched too early), 6 CRC mismatch. The calibration and CRC_flag bits of the status byte are not checked.

## rtcc (Microchip I2C real-time clock/calendars)
Source: DS20005010J (MCP7940N), DS20002292C (MCP7940M), DS20005009 (MCP79400/1/2), DS20002266K (MCP79410/1/2) and the errata DS80000611F, DS80000612F, DS80000608, DS80000604. All of them share one register map, with the RTCC and the 64-byte SRAM at 7-bit address 0x6F and the EEPROM at 0x57. The caller sets up `I2c` first (400 kHz at 2.5 V and above, 100 kHz below). The module owns no pins.

| Part | RTCC, alarms, SRAM | VBAT, power-fail time stamps | Protected EEPROM (8 bytes) | EEPROM (128 bytes) |
|---|---|---|---|---|
| MCP7940M | yes | no | no | no |
| MCP7940N | yes | yes | no | no |
| MCP79400/1/2 | yes | yes | yes (79401 EUI-48, 79402 EUI-64) | no |
| MCP79410/1/2 | yes | yes | yes (79411 EUI-48, 79412 EUI-64) | yes |

| Routine | Effect |
|---|---|
| `RtccSet(year, month, day, weekday, hour, minute, second)` | stops the oscillator, loads the time in 24-hour mode in the order the errata ask for, starts it, waits for OSCRUN (at most 2 s, status 6 if it never runs), writes the weekday again. Years 0..99 = 2000..2099 |
| `RtccRead()` | copies the seven time registers in one transfer (the chip buffers them, so the copy cannot straddle a rollover) |
| `RtccYear()`, `RtccMonth()`, `RtccDay()`, `RtccWeekday()`, `RtccHour()`, `RtccMinute()`, `RtccSecond()` | decode the copy (binary, 0..23 hours even if the clock is in 12-hour mode) |
| `RtccOscRun()`, `RtccPowerFail()`, `RtccBatteryOn()`, `RtccLeap()` | flags of the copy |
| `RtccStart()`, `RtccStop()` | ST bit |
| `RtccBattery(en)`, `RtccClearPowerFail()` | VBATEN; both also clear PWRFAIL |
| `RtccStamp(up, month, day, hour, minute)` | power-down (`up` False) or power-up time stamp |
| `RtccAlarm(n, mask, month, day, weekday, hour, minute, second)`, `RtccAlarmEnable(n, arm)`, `RtccAlarmFlag(n, flag)`, `RtccAlarmClear(n)`, `RtccAlarmPolarity(activeHigh)` | the two alarms (mask 0 seconds, 1 minutes, 2 hours, 3 weekday, 4 date, 7 all) and the MFP polarity |
| `RtccSquareWave(sel)`, `RtccPinLevel(level)` | MFP as 1 Hz / 4.096 / 8.192 / 32.768 kHz output, or as a general purpose output |
| `RtccTrim(steps, coarse)` | digital trim, -127..127 steps of about 1 ppm |
| `RtccRamRead(addr, v)`, `RtccRamWrite(addr, v)` | the 64 SRAM bytes |
| `RtccEeRead(addr, v)`, `RtccEeWrite(addr, v)`, `RtccEeProtect(level)` | the 128-byte EEPROM and its block protection (MCP79410/1/2) |
| `RtccIdRead(i, v)`, `RtccIdWrite(i, v)` | the 8 protected bytes, written after the 0x55 / 0xAA unlock |

Status: 0 ok, 1..4 as `I2cStatus`, 5 an argument out of range (nothing was sent), 6 a wait ran out (oscillator, EEPROM write cycle). The EEPROM routines on a part without EEPROM also give 6, after 20 ms, because a busy EEPROM and an absent one both fail to acknowledge. Errata worked around: date increment at noon (24-hour mode only), date changing on a month or year write, weekday changing after a write. Not worked around: the spurious minute/hour alarm with a slowing trim (DS80000611F issue 2). Tests: `tests/exec/lib_rtcc.bas` (no bus: status 4, bad arguments 5) and `tests/exec_rtcc/lib_rtcc_model.bas`, which runs every routine in the simulator against a software model of the chip (`tests/exec_rtcc/i2c.bas`). Nothing has run on a real chip.

## rtccspi (Microchip SPI real-time clock/calendars)
Source: DS20002300E (MCP79510/11/12, MCP79520/21/22), DS20002280F (MCP795W10/11/12, MCP795W20/21/22) and the errata DS80000680E and DS80000542. The parts run from 1.8 V to 3.6 V, so a 5 V PIC needs level shifting. Set up `Spi` first in mode 0 at up to 5 MHz (3 MHz below 2.5 V); `RtccspiInit(cs)` takes the chip select pin (`Pinio` numbering, 0..23) and drives it high. The register map is that of the I2C parts moved up by one (hundredths of a second at 0).

Same routines as `rtcc` with the prefix `Rtccspi` (`RtccspiSet`, `RtccspiRead`, `RtccspiSecond` ..., `RtccspiHundredths`, `RtccspiAlarm(n, mask, month, day, weekday, hour, minute, second, hundredths)`, `RtccspiTrim(steps, coarse)` with 8-bit steps -255..255, `RtccspiSquareWave`, `RtccspiSquareWaveOff`, `RtccspiRamRead/Write`, `RtccspiStamp`, `RtccspiBattery`, `RtccspiClearPowerFail`, `RtccspiStart/Stop`), and in addition:

| Routine | Effect |
|---|---|
| `RtccspiInit(cs)` | chip select pin; 1 ok, 0 not a pin of the part |
| `RtccspiAlarmPin(n, wdo)` | W parts: alarm n on the WDO or IRQ pin |
| `RtccspiRamClear()` | CLRRAM |
| `RtccspiEeRead/Write(addr, v)`, `RtccspiEeProtect(level)` | EEPROM (128 or 256 bytes) with EEWREN and WIP polling handled |
| `RtccspiIdRead/Write(i, v)` | the 16 protected bytes (EUI node address in the first 8 of the X1/X2 parts), EEWREN + UNLOCK 0x55 + UNLOCK 0xAA + IDWRITE |
| `RtccspiWdt(en, period, delay, longPulse)`, `RtccspiWdtClear()`, `RtccspiWdtFlag(f)`, `RtccspiWdtFlagClear()` | W parts: watchdog |
| `RtccspiEvents(lowEnable, slow, highCount)`, `RtccspiEventFlags(low, high, clr)` | W parts: event detection |
| `RtccspiReadReg(reg, v)`, `RtccspiWriteReg(reg, v)` | any register 0..95 |

Status as for `rtcc` (4 = `RtccspiInit` or `Spi` not done). Errata worked around: as for `rtcc`, plus the weekday reset to 1 (DS80000680E issue 3). Documented, not worked around: hundredths not in step with seconds until the first minute rollover, hundredths reading the same twice, the 8 kHz / 32 kHz output disturbing a crystal MCP795xx. `RtccspiTrim` writes RTCHOUR (the trim sign lives there) only when the sign changes, so the window in which a rollover could be overwritten is small. Test: `tests/exec_rtcc/lib_rtccspi_model.bas` runs every routine against a software model of the chip. Nothing has run on a real chip.

## strings (String helpers)
| Routine | Effect |
|---|---|
| `Len(s)` | `Byte`: the characters before the `Null` (0 for an empty string). `s` is `ByRefConst`: a `String` of any size, or a literal |

Portable (no device registers); `tests/exec/lib_strings.bas` runs on the PIC18 and PIC16 parts.

## format (numbers as text)
| Routine | Effect |
|---|---|
| `FmtDec(n, width, fill)` | unsigned decimal (`Byte`, `Word`, `LongWord` overloads) into `FmtBuf`, padded to `width` with `fill` |
| `FmtSDec(n, width, fill)` | signed decimal (`ShortInt`, `Integer`, `LongInt`); the sign counts in the width |
| `FmtHex(n, digits)` / `FmtBin(n, digits)` | the low `digits` hexadecimal (at most 8) or binary (at most 32) digits, with leading zeros |

`FmtBuf` is `Public Dim FmtBuf As String(32)`: pass it to `SerialWrite`, `LcdWrite`, `OledWrite` and the like. Portable (no device registers);
`tests/exec/lib_format.bas` runs on the PIC18, 16F17146 and 16F15244 in the simulators (MDB).

## floatlib (Float arithmetic; included automatically)
Not included by hand: any source that mentions `Float` gets it. A Float is its IEEE-754 binary32 pattern in 4 bytes. The compiler turns
`+ - * /`, the six comparisons and the conversions into calls to `FAdd FSub FMul FDiv`, `FEq FNe FLt FLe FGt FGe`, `FFromLong FFromULong FToLong`
(on `LongWord` patterns); negation and `Abs` flip and clear the sign bit inline. Only the routines a program uses are linked. Round to nearest
even; infinities and NaN propagate; denormals are flushed to zero. On the PIC16F17126/46 the routines are Basic source (the PIC18 ones are assembly);
the results are the same bit for bit (`tests/exec_p16/float_random.bas`, made by `scripts/gen_float_vectors.py`, runs the same vectors on both cores),
the code is larger (about 1.2K words for `+`, 1.4K for `*`, 0.9K for `/`, 0.3K for the comparisons, 0.7K and 0.4K for the conversions). Float work directly in an `Interrupt` handler is `E-ISR-CALL`: put it in a
routine and call that inside `Save(…) … Restore`. Cost on the PIC18: about 200 words for `+`, 195 for `*`, 150 for `/`, 86 for the comparisons, plus 53 shared (hand-written assembly). See D51, D55.

## Tests
`tests/exec/lib_serial.bas`, `lib_serial2.bas` (set-up only), `lib_adc.bas`, `lib_eeprom.bas`, `lib_flashwrite.bas`, `lib_pwm.bas`, `lib_i2c.bas`, `lib_spi.bas`, `lib_lcd.bas` and `lib_oled.bas` and `lib_aht30.bas` (set-up only; no pin model in the simulator), `lib_system.bas`, `lib_intosc.bas`, `lib_intosc_div.bas`, `lib_timer.bas` and `lib_timer12.bas` and `lib_timer_hw.bas` run in the simulator (register values, TXIF handshake,
timer overflows); `tests/programs/library_all.bas` (built by `tests/backend.rs`) includes every module. Not yet checked on hardware (D6).
