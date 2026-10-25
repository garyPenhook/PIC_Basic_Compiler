# Standard library (M6)

Written in the language, found by `Include "name"` in the project's `lib/` folder (LANGUAGE.md §9).
A routine is called as `Module.Routine(...)` or, when the name is unambiguous, by its own name.
Only what a program calls is compiled in. Each module cites the data sheet pages its register
values come from (DS40002043F, PIC18F27/47Q10); the values were checked against that document.

`DelayUs`, `DelayMs`, `Input`, `Output`, `High`, `Low` and `Toggle` are compiler intrinsics
(LANGUAGE.md §12), so there is no module for them. No library module declares an `Interrupt`
handler: that would take a vector away from the program. Modules configure peripherals and read
flags; the program writes its own handler.

## gpio
| Routine | Effect |
|---|---|
| `GpioAllDigital()` | `ANSELA/B/C = 0` (they reset to analog) |
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

## serial (EUSART1, 8N1, TX on RC6, RX on RC7)
| Routine | Effect |
|---|---|
| `SerialInit(baud)` | PPS (`RC6PPS = 9`, `RX1PPS = 23`), pin directions, `BRG16 = BRGH = 1`, enables TX and RX. `n = round(FOSC / (4 * baud)) - 1`, computed at run time from `Clock` (a 32-bit divide, executed once) |
| `SerialWriteByte(b)`, `SerialWrite(text)`, `SerialNewLine()` | blocking send (`text` up to 80 characters) |
| `SerialWriteWord(v)`, `SerialWriteHex(v)` | unsigned decimal, two hex digits |
| `SerialAvailable()`, `SerialRead()` | receive; `SerialRead` waits and clears an overrun |
| `SerialFlush()` | wait for the shift register to empty (`TRMT`) |

`Clock` must be FOSC in MHz. Baud accuracy follows the oscillator; the internal oscillator drifts
with voltage and temperature (data sheet 29.1.3), so use a crystal for anything beyond casual use.

## serial2 (EUSART2, 8N1, TX on RB6, RX on RB7)
Same routines as `serial` with the prefix `Serial2` (`Serial2Init`, `Serial2WriteByte`, `Serial2Write`,
`Serial2NewLine`, `Serial2WriteWord`, `Serial2WriteHex`, `Serial2Available`, `Serial2Read`, `Serial2Flush`).
`RB6PPS = 0x0B` (EUSART2 TX/CK, Table 18-2), `RX2PPS = 0x0F` (RB7, Table 18-1), flags `TX2IF`/`RC2IF` are
`PIR3` bits 6 and 7, registers `SP2BRG`, `TX2STA`, `RC2STA`, `BAUD2CON`. RB6/RB7 are also the ICSP pins, so
disconnect the programmer while using them. Both modules can be included and run together.

## adc (ADCC, basic mode, right-justified 10-bit results)
| Routine | Effect |
|---|---|
| `AdcInit()` | ADC on, VDD/VSS reference, FOSC clock with the smallest TAD >= 1 us (ADCLK), hardware acquisition (`ADACQ`) of 5 us; runs a 32-bit calculation once from `Clock` |
| `AdcPin(ch)` | `TRISx`/`ANSELx` bit of channel 0..23 (RA0-7 = 0..7, RB = 8..15, RC = 16..23) |
| `AdcRead(ch)` | one conversion, 0..1023. Channels `AdcChVss` 60, `AdcChTemp` 61, `AdcChDac` 62, `AdcChFvr` 63 are internal |
| `AdcReadAvg(ch, n)` | mean of n (1..64) conversions |
| `AdcMillivolts(raw, vrefMv)` | `raw * vref / 1023` |
| `AdcRefVdd()` / `AdcRefFvr(gain)` | reference VDD, or FVR at gain 1, 2, 4 (any value >= 4 is taken as 4, 0 as 1; waits for `FVRRDY`) |

Errata (DS80000832G): 1.4.4, the first conversion after a channel change is run and dropped (the
module remembers the last channel; code that writes `ADPCH` itself bypasses that). 1.4.1, `AdcRefFvr`
raises TAD to >= 8 us, which `ADCS` allows only up to `Clock` = 16 MHz; above that the slowest clock is
used and the missing-code workaround is not met, so use the VDD reference there. Not reentrant.
The temperature indicator needs `FVRCON.TSEN` (not set here). Source impedance above 10 kohm needs a
larger `ADACQ`.

## eeprom (data EEPROM, 1024 bytes)
| Routine | Effect |
|---|---|
| `EepromRead(addr)` | byte at 0..1023; 255 for a larger address |
| `EepromWrite(addr, value)` | skips the write when the byte already holds `value`; otherwise unlock sequence, waits for the write to finish. Returns 1 when the byte reads back as `value`, 0 for an invalid address or a failed write |
| `EepromReadWord(addr)` / `EepromWriteWord(addr, value)` | 16-bit value, low byte first, at addr and addr + 1 (the write returns 1 only if both bytes were stored) |
| `EepromSize` | constant 1024 |

`NVMEN` is set only around the write and global interrupts are off for the unlock sequence (the previous
`GIE` is restored). Errata 1.6.1 (DS80000832G): `NVMERR` stays set across Resets after a Reset during a write
until one write succeeds, so it is not used as the error flag: success is the read-back, and the module clears
`NVMERR`. A write takes the device's programming time, during which the routine waits (the CPU is not stalled
by the hardware, but the next write cannot start). Not reentrant: do not call it from a handler and from the
main program.

## pwm (CCP1, CCP2, PWM3, PWM4 on Timer2)
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

## i2c (MSSP1 host)
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
description, register order and the reference compilers' approach: `docs/CLOCK.md`.

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
| `FontByte(i)` | byte `i` (0..474) of the font table (kept in flash inside an `Asm` block, read with `TBLRD`) |

## floatlib (Float arithmetic; included automatically)
Not included by hand: any source that mentions `Float` gets it. A Float is its IEEE-754 binary32 pattern in 4 bytes. The compiler turns
`+ - * /`, the six comparisons and the conversions into calls to `FAdd FSub FMul FDiv`, `FEq FNe FLt FLe FGt FGe`, `FFromLong FFromULong FToLong`
(on `LongWord` patterns); negation and `Abs` flip and clear the sign bit inline. Only the routines a program uses are linked. Round to nearest
even; infinities and NaN propagate; denormals are flushed to zero. Float work directly in an `Interrupt` handler is `E-ISR-CALL`: put it in a
routine and call that inside `Save(…) … Restore`. Cost: about 700 words for `+`, 800 for `*`, 470 for `/`, plus about 250 shared. See D51.

## Tests
`tests/exec/lib_serial.bas`, `lib_serial2.bas` (set-up only), `lib_adc.bas`, `lib_eeprom.bas`, `lib_pwm.bas`, `lib_i2c.bas`, `lib_spi.bas`, `lib_lcd.bas` and `lib_oled.bas` (set-up only; no pin model in the simulator), `lib_system.bas`, `lib_intosc.bas`, `lib_intosc_div.bas`, `lib_timer.bas` and `lib_timer12.bas` and `lib_timer_hw.bas` run in the simulator (register values, TXIF handshake,
timer overflows); `tests/programs/library_all.bas` (built by `tests/backend.rs`) includes every module. Not yet checked on hardware (D6).
