# Standard library (M6)

Written in the language, found by `Include "name"` in the project's `lib/` folder (LANGUAGE.md §9).
A routine is called as `Module.Routine(...)` or, when the name is unambiguous, by its own name.
Only what a program calls is compiled in. Each module cites the data sheet pages its register
values come from (DS40002043F, PIC18F27/47Q10; PIC16F17126/46 values from DS40002343F and PIC18F0x/1xQ41
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
wrong register. Nothing here can be built for the PIC16F171xx until a `pic16e` code generator exists,
so the 16F column is checked against the data sheet and the preprocessing only, not run on hardware.

| Module | PIC18F27/47Q10 | PIC16F17126/46 (DS40002343F) | PIC18F0x/1xQ41 (DS40002214G, DS40002242F) | Still to do |
|---|---|---|---|---|
| `delay` | done | portable (no device registers) | portable | none |
| `gpio` | done | done (`_has` on `ANSELx`, `WPUx`, `ODCONx`) | done (the same registers; no port B on the 14-pin parts) | none |
| `intosc` | done | done (`OSCFRQ.FRQ`: 1..32 MHz) | done (`OSCFRQ.HFFRQ`, 1..64 MHz as the Q10) | none |
| `system` | done | done | done (`PCON0` at `04F0h`, same bits) | none |
| `timer` | done | done (flags in PIR1/PIR2, own source constants) | done (flags in `PIR3`; own `T1Clk*`, `T1Gate*`, `T2Rst*` constants) | `T1Gate*` / `T2Rst*` lists hold only the sources checked so far |
| `serial` | done (TX RC6, RX RC7) | done (TX RC4, RX RC5) | done (UART1, TX RC4, RX RC5) | an override for other pins |
| `serial2` | done (TX RB6, RX RB7) | **not ported** | done (UART2, TX RC2, RX RC1) | pins (`RB6PPS` missing on the 14-pin 16F part, no port B), `RX2PPS` encoding, flags in another PIR |
| `adc` | done (10 bits) | done (channels 58..62; erratum 1.1.2 noted; 12 bits) | done (12 bits, `AdcMax` = 4095, channels 58..63, charge pump on, 8 us acquisition) | none |
| `eeprom` | done (1024 bytes) | **not ported** | done (512 bytes, `NVMLOCK` unlock) | the 16F: different NVM registers (no `NVMCON0`, `NVMADRU`), different unlock and access sequence |
| `flashwrite` | done | **not ported** (`#error`) | done (`FlashLastSector` from the flash size; page read, erase, write through the NVM buffer bank) | the 16F: same NVM differences as `eeprom`; the 16F errata 1.9.1 equivalent has not been read |
| `spi` | done | **not ported** | done (SPI1, any of RA/RB4..7/RC pins through PPS, at most 10 MHz) | default pins for MSSP1, `RxyPPS` codes and `SSP1xPPS` for the 16F, `RB*PPS` missing on the 14-pin part |
| `lcd` | done | **not ported** | done (port B pins refused on the 14-pin parts) | the 16F: port B does not exist on the 14-pin part; choose the pins |
| `i2c` | done | **not ported** | done, **in software** on two pins (see below) | the 16F; a driver around the I2C1 peripheral would need the byte count first (FACTS-18F-Q41.md section 6, errata 1.3.x) |
| `pwm` | done | **not ported** | done with different channels: 1..6 = PWM1S1P1 … PWM3S1P2, one shared period (CCP1 not offered) | the 16F has CCP1/CCP2 and PWM1/PWM2 of a different kind, no PWM3/PWM4, no `CCPTMRS`; pin routing |
| `oled` | done | **not ported** | done (over the software `i2c`, or `spi`) | uses `TBLPTR` / `TABLAT` (PIC18 table reads); needs an alternative for the enhanced mid-range core |
| `aht30` | done | portable if the core generator supports them | done (over the software `i2c`) | |
| `dma` | not applicable (no DMA) | not checked (the 16F17126/46 data sheet has not been read for DMA) | written for software-started RAM/SFR copies (`DmaCopy`) trigger-started feeds (`DmaOnTrigger`) with abort triggers (`DmaAbortOn`) and flash-source copies (`DmaCopyFlash`); builds, register set-up tested, bytes not seen moving; a part without `DMAnCON0` gets `#error` | EEPROM sources, interrupts, priorities; data movement not seen on a real part (the simulator does not model DMA) |
| `floatlib` | done | portable if the core generator supports them | builds (no device registers); not run on the Q41 | check once `pic16e` code generation exists; run the float tests on the Q41 simulator |

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
| `DelayNop()` | one instruction cycle |

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

## serial (EUSART1, 8N1, TX on RC6, RX on RC7; PIC16F17126/46 and PIC18-Q41 UART1: TX on RC4, RX on RC5)
| Routine | Effect |
|---|---|
| `SerialInit(baud)` | PPS (`RC6PPS = 9`, `RX1PPS = 23`; PIC16F17126/46: `RC4PPS = 19`, `RX1PPS = 21`), pin directions, `BRG16 = BRGH = 1`, enables TX and RX. `n = round(FOSC / (4 * baud)) - 1`, computed at run time from `Clock` (a 32-bit divide, executed once) |
| `SerialWriteByte(b)`, `SerialWrite(text)`, `SerialNewLine()` | blocking send (`text` up to 80 characters) |
| `SerialWriteWord(v)`, `SerialWriteHex(v)` | unsigned decimal, two hex digits |
| `SerialAvailable()`, `SerialRead()` | receive; `SerialRead` waits and clears an overrun |
| `SerialFlush()` | wait for the shift register to empty (`TRMT`) |
| `SerialOnRx` | event variable of type `TRxEvent` (`Event(ByVal c As Byte)`); assign a handler `Event OnByte(ByVal c As Byte)` |
| `SerialRxService()` | clear an overrun, and if a byte has arrived read it and call `SerialOnRx(byte)`; call from the main loop, or from your own `Interrupt` inside `Save(0, SerialRxService)` |

PIC18-Q41: `RC4PPS = 0x10` (UART1 TX), `U1RXPPS = 21`, `U1BRG`, `BRGS = 1`, `U1CON0 = 0xB0`, `U1CON2.RUNOVF = 1`, then
`U1CON1.ON`. `SerialWriteByte` waits for `U1FIFO.TXBF = 0`; `SerialAvailable` is `U1FIFO.RXBE = 0`; `SerialFlush` waits for
`U1FIFO.TXBE` and `U1ERRIR.TXMTIF`; a receive FIFO overflow flag (`RXFOIF`) is simply cleared, the receiver keeps running.

`Clock` must be FOSC in MHz. Baud accuracy follows the oscillator; the internal oscillator drifts
with voltage and temperature (data sheet 29.1.3), so use a crystal for anything beyond casual use.

## serial2 (EUSART2, 8N1, TX on RB6, RX on RB7; PIC18-Q41 UART2: TX on RC2, RX on RC1)
Same routines as `serial` with the prefix `Serial2` (`Serial2Init`, `Serial2WriteByte`, `Serial2Write`,
`Serial2NewLine`, `Serial2WriteWord`, `Serial2WriteHex`, `Serial2Available`, `Serial2Read`, `Serial2Flush`).
`RB6PPS = 0x0B` (EUSART2 TX/CK, Table 18-2), `RX2PPS = 0x0F` (RB7, Table 18-1), flags `TX2IF`/`RC2IF` are
`PIR3` bits 6 and 7, registers `SP2BRG`, `TX2STA`, `RC2STA`, `BAUD2CON`. RB6/RB7 are also the ICSP pins, so
disconnect the programmer while using them. Both modules can be included and run together. PIC18-Q41:
`RC2PPS = 0x13` (UART2 TX), `U2RXPPS = 17` (RC1, its reset selection); RC1 is also the default SPI1 data-in and
I2C1 data pin.

## adc (ADCC, basic mode, right-justified results: 10 bits on the Q10, 12 bits on the PIC16F17126/46 and PIC18-Q41)
| Routine | Effect |
|---|---|
| `AdcInit()` | ADC on, VDD/VSS reference, FOSC clock with the smallest TAD >= 1 us (ADCLK), hardware acquisition (`ADACQ`) of 5 us; runs a 32-bit calculation once from `Clock` |
| `AdcPin(ch)` | `TRISx`/`ANSELx` bit of channel 0..23 (RA0-7 = 0..7, RB = 8..15, RC = 16..23) |
| `AdcRead(ch)` | one conversion, 0..1023 (`AdcMax`: 4095 on the 12-bit parts). Channels `AdcChVss` 60, `AdcChTemp` 61, `AdcChDac` 62, `AdcChFvr` 63 are internal (PIC16F17126/46: 58, 59, 60, 62; `AdcChDac2` 61; its pins are RA0..RA5, RB4..RB7, RC0..RC7 and there is no first-conversion workaround; PIC18-Q41: `AdcChDac2` 58, `AdcChVss` 59, `AdcChTemp` 60, `AdcChDac` 61, `AdcChFvr` 62, `AdcChFvr2` 63, the same pins and no workaround, the charge pump `ADCP.CPON` is switched on by `AdcInit`, and the acquisition is 8 us) |
| `AdcReadAvg(ch, n)` | mean of n (1..64) conversions |
| `AdcMillivolts(raw, vrefMv)` | `raw * vref / AdcMax` (`AdcMax` = 1023 or 4095) |
| `AdcRefVdd()` / `AdcRefFvr(gain)` | reference VDD, or FVR at gain 1, 2, 4 (any value >= 4 is taken as 4, 0 as 1; waits for `FVRRDY`) |

Errata (DS80000832G): 1.4.4, the first conversion after a channel change is run and dropped (the
module remembers the last channel; code that writes `ADPCH` itself bypasses that). 1.4.1, `AdcRefFvr`
raises TAD to >= 8 us, which `ADCS` allows only up to `Clock` = 16 MHz; above that the slowest clock is
used and the missing-code workaround is not met, so use the VDD reference there. Not reentrant.
The temperature indicator needs `FVRCON.TSEN` (not set here). Source impedance above 10 kohm needs a
larger `ADACQ`.

## eeprom (data EEPROM, 1024 bytes; 512 bytes on the PIC18-Q41)
| Routine | Effect |
|---|---|
| `EepromRead(addr)` | byte at 0..1023 (0..511 on the Q41); 255 for a larger address |
| `EepromWrite(addr, value)` | skips the write when the byte already holds `value`; otherwise unlock sequence, waits for the write to finish. Returns 1 when the byte reads back as `value`, 0 for an invalid address or a failed write |
| `EepromReadWord(addr)` / `EepromWriteWord(addr, value)` | 16-bit value, low byte first, at addr and addr + 1 (the write returns 1 only if both bytes were stored) |
| `EepromSize` | constant 1024 (512 on the Q41; the device's `_EepromBytes`) |

`NVMEN` is set only around the write and global interrupts are off for the unlock sequence (the previous
`GIE` is restored). Errata 1.6.1 (DS80000832G): `NVMERR` stays set across Resets after a Reset during a write
until one write succeeds, so it is not used as the error flag: success is the read-back, and the module clears
`NVMERR`. A write takes the device's programming time, during which the routine waits (the CPU is not stalled
by the hardware, but the next write cannot start). Not reentrant: do not call it from a handler and from the
main program.

## flashwrite (program flash self-write)
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

## pwm (CCP1, CCP2, PWM3, PWM4 on Timer2; PIC18-Q41: six outputs of PWM1..PWM3)
PIC18-Q41: channels 1..6 are PWM1S1P1, PWM1S1P2, PWM2S1P1, PWM2S1P2, PWM3S1P1, PWM3S1P2 on any of RA0..RA5 (not RA3),
RB4..RB7, RC0..RC7 (`RxyPPS` = 9 + channel); the period is shared (`PwmInit(hz)` sets `PWMxCLK` = FOSC, `PWMxCPRE`, `PWMxPR`;
`PwmSteps` is `PR + 1`, up to 65535, and a duty of `PwmSteps` is 100 %); `PwmInvert` restarts the module, because the slice
configuration may only be written while it is disabled. Timer2 is not used. The Q10 description below applies to the Q10.
| Routine | Effect |
|---|---|
| `PwmInit(hz)` | picks the Timer2 prescale and `T2PR` for `hz` (1..1000000; FOSC/4 clock): `f = FOSC / (4 * prescale * (T2PR + 1))`. Returns 1, or 0 when no prescale of 1..128 reaches `hz` or a channel is running. Starts nothing |
| `PwmFrequency()` / `PwmSteps()` | achieved frequency in Hz; duty cycle steps per period, `4 * (T2PR + 1)` (1024 only when `T2PR` = 255) |
| `PwmStart(ch, pin, duty)` | channel 1 = CCP1, 2 = CCP2, 3 = PWM3, 4 = PWM4, on pin 0..23 (RA0..RC7, as the `Adc` channels): CCP1/CCP2 on ports B and C, PWM3/PWM4 on ports A and C. `duty` in steps. Follows the data sheet set-up order (driver off, routing, duty, Timer2 on, wait for the first overflow, driver on) so the first period is complete. Returns 0 for a bad channel or pin, a pin used by another running channel, or no successful `PwmInit`; a running channel is restarted |
| `PwmDuty(ch, duty)` / `PwmPercent(ch, pct)` | new duty cycle of a running channel (steps, or 0..100 %) |
| `PwmInvert(ch, inverted)` | output polarity of PWM3/PWM4 (`PWMxCON.POL`); returns 0 for channels 1 and 2 |
| `PwmStop(ch)` | module off, pin back to an input driven by `LATxy`; Timer2 stops with the last channel |

All channels share one frequency; each has its own duty. The module owns Timer2 while a channel runs: do not
use the `Timer` module's Timer2 routines or a Timer2 interrupt then (`PwmStart` waits for `TMR2IF` and clears it).
With `T2PR` = 255 the highest duty is 1023 of 1024 steps (99.9 %), so 100 % is not reachable that way. The duty
registers are double buffered and copied at the period match; if that falls between the two byte writes of one
update, one period can use a mixed value. Not reentrant: do not call it from a handler and from the main program.

## i2c (MSSP1 host; PIC18-Q41: software host)
PIC18-Q41: the same routines, in software on two ordinary pins (any of RA0..RA5 except RA3, RB4..RB7, RC0..RC7, numbered 0..23
as the `Adc` channels), open drain by TRIS, `hz` 2000..400000 (the real clock is lower, much lower on a slow `Clock`), clock
stretching waited for, arbitration checked by reading SDA back. Why not the I2C1 peripheral: it counts the bytes of a transfer
in hardware, so the step-by-step API (`I2cReceive(ack)` decides the acknowledge after the byte has arrived) cannot be mapped onto
it. A hardware driver can replace this branch later without changing the routines. The Q10 description below applies to the Q10.
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

## spi (MSSP1 host)
| Routine | Effect |
|---|---|
| `SpiInit(hz, mode, sck, sdo, sdi)` | MSSP1 as SPI host, mode 0..3 (CKP = CPOL; CKE = 1 for modes 0 and 2). Pins 8..23 (ports B and C, as the `Adc` channels); `sdo` = 255 for receive only. Clock `FOSC / 4` for `hz` of `FOSC / 4` or more, else `FOSC / (4 * (SSPxADD + 1))` with `SSPxADD` 1..255, rounded to at or below `hz` (lowest `FOSC / 1024`). Input sampled mid-bit (`SMP` = 0). Returns 1, or 0 for a bad pin or mode, a pin used twice, or a clock out of range |
| `SpiTransfer(b)` | sends `b`, returns the byte received at the same time |
| `SpiWrite(b)` / `SpiRead()` | send ignoring the reply / receive (sends 255) |
| `SpiStatus()` | 0 ok, 1 timeout (bounded wait for `BF`), 4 not initialised |
| `SpiOff(sck, sdo)` | MSSP off, `SCK` and `SDO` back to `LATxy`; call before `SpiInit` on other pins |

The chip select is not part of the module (use `Gpio` or a port bit). The module owns MSSP1 (not together with `I2c`),
does not use its interrupt, and is not reentrant.

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

## system (reset cause, clock check)
| Routine | Effect |
|---|---|
| `SysResetCause()` | cause of the latest Reset not yet cleared, from `PCON0`, tested in this order: 1 power-on, 2 brown-out, 7 stack overflow, 8 stack underflow, 5 watchdog window violation, 4 watchdog time-out, 3 MCLR pin, 6 `RESET` instruction, 0 none |
| `SysResetFlags()` | the raw `PCON0` value |
| `SysClearResetFlags()` | all `PCON0` flags to their inactive state (`PCON0` = 63); call it after reading the cause, because hardware never clears a flag |
| `SysClockHz()` | system clock in Hz from `OSCCON2` and `OSCFRQ`: HFINTOSC (1, 2, 4, 8, 12, 16, 32, 48 or 64 MHz) divided by 1..512; 0 for any other source or a reserved code. Nominal frequency (`OSCTUNE` ignored) |
| `SysClockFrom(cosc, cdiv, hffrq)` | the same conversion from given field values |
| `SysClockOk()` | True when `SysClockHz()` equals `Clock` |

A flag left from an earlier Reset is reported until it is cleared; after a power-on Reset the brown-out flag is
unknown, so power-on is tested first. The module does not change the clock (that is `intosc`, `docs/CLOCK.md`): `DelayUs`/`DelayMs`, `Serial`,
`Pwm`, `I2c`, `Spi` and `Adc` compute from the compile-time `Clock`, so a run-time change makes them wrong.
`SysClockOk` is the run-time check that the oscillator really runs at `Clock`.

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

## aht30 (AHT30 temperature and humidity sensor, I2C)
Source: the Aosong AHT30 data sheet (Sep 2023): address 0x38 (5.1), measurement command 0xAC 0x33 0x00 and 80 ms wait (5.2), status word (Table 9), CRC8 (5.2), conversion formulas (5.2), I2C timing (Table 8). The caller sets up the bus first (`I2cInit` at no more than 400 kHz, external pull-ups); sample at most once a second to keep self-heating under 0.1 C (2.4). Results: temperature `Integer` in 1/100 degree C, humidity `Word` in 1/100 %RH, rounded to nearest, written only on status 0.

| Routine | Effect |
|---|---|
| `Aht30Init()` | waits 5 ms (power-up time) |
| `Aht30Start()` | sends 0xAC 0x33 0x00; returns the status |
| `Aht30Fetch(temp, rh)` | reads the 7-byte frame at least 80 ms after `Aht30Start`, checks busy and CRC8, converts; returns the status |
| `Aht30Measure(temp, rh)` | `Aht30Start`, `DelayMs(80)`, `Aht30Fetch` |

Status: 0 ok, 1..4 as `I2cStatus` (timeout, collision, no acknowledge, I2c not initialised), 5 busy (fetched too early), 6 CRC mismatch. The calibration and CRC_flag bits of the status byte are not checked.

## floatlib (Float arithmetic; included automatically)
Not included by hand: any source that mentions `Float` gets it. A Float is its IEEE-754 binary32 pattern in 4 bytes. The compiler turns
`+ - * /`, the six comparisons and the conversions into calls to `FAdd FSub FMul FDiv`, `FEq FNe FLt FLe FGt FGe`, `FFromLong FFromULong FToLong`
(on `LongWord` patterns); negation and `Abs` flip and clear the sign bit inline. Only the routines a program uses are linked. Round to nearest
even; infinities and NaN propagate; denormals are flushed to zero. Float work directly in an `Interrupt` handler is `E-ISR-CALL`: put it in a
routine and call that inside `Save(…) … Restore`. Cost: about 200 words for `+`, 195 for `*`, 150 for `/`, 86 for the comparisons, plus 53 shared (hand-written assembly). See D51, D55.

## Tests
`tests/exec/lib_serial.bas`, `lib_serial2.bas` (set-up only), `lib_adc.bas`, `lib_eeprom.bas`, `lib_flashwrite.bas`, `lib_pwm.bas`, `lib_i2c.bas`, `lib_spi.bas`, `lib_lcd.bas` and `lib_oled.bas` and `lib_aht30.bas` (set-up only; no pin model in the simulator), `lib_system.bas`, `lib_intosc.bas`, `lib_intosc_div.bas`, `lib_timer.bas` and `lib_timer12.bas` and `lib_timer_hw.bas` run in the simulator (register values, TXIF handshake,
timer overflows); `tests/programs/library_all.bas` (built by `tests/backend.rs`) includes every module. Not yet checked on hardware (D6).
