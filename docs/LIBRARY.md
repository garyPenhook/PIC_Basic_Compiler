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

## Tests
`tests/exec/lib_serial.bas`, `lib_serial2.bas` (set-up only), `lib_adc.bas`, `lib_eeprom.bas`, `lib_timer.bas` and `lib_timer12.bas` and `lib_timer_hw.bas` run in the simulator (register values, TXIF handshake,
timer overflows); `tests/programs/library_all.bas` (built by `tests/backend.rs`) includes every module. Not yet checked on hardware (D6).
