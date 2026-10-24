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

## Tests
`tests/exec/lib_serial.bas`, `lib_timer.bas` and `lib_timer12.bas` and `lib_timer_hw.bas` run in the simulator (register values, TXIF handshake,
timer overflows); `tests/programs/library_all.bas` (built by `tests/backend.rs`) includes every module. Not yet checked on hardware (D6).
