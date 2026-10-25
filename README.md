# Basic_Compiler

A BASIC compiler for PIC microcontrollers, built for small, fast code. It turns a structured,
typed BASIC (modules, subroutines and functions, structures, interrupts) into a `.hex` file, and
comes with a library of ready-made modules for the common peripherals.

First target: **PIC18F27Q10**. More microcontrollers will follow, one at a time.

## A taste

```basic
Program Blink
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "gpio"
Include "serial"

Dim led As PORTB.0
Dim ticks As Word

Interrupt Tick()
    PIR0.5 = 0
    Inc(ticks)
End Interrupt

Gpio.GpioAllDigital()
Output(led)
Serial.SerialInit(115200)
T0CON1 = 65
PIE0.5 = 1
Enable(Tick)
T0CON0 = 128
While True
    Toggle(led)
    Serial.SerialWrite("tick")
    Serial.SerialNewLine()
    DelayMS(500)
Wend
```

```
basil blink.bas          # writes blink.hex (plus blink.S and blink.map)
basil --report blink.bas # also prints code and RAM sizes per routine and variable
```

## What works today

**Language**
* Types: Boolean, Bit, Char, 8/16/32-bit signed and unsigned integers (also spelled `SByte`, `SWord`, `Long`, `Dword` for the signed 8, signed 16, signed 32 and unsigned 32-bit types), `Float` (IEEE-754 binary32), strings, one-dimensional arrays (with initialisers and program-memory `Const` tables), structures
  and unions, constants.
* Full arithmetic, logic, shifts and comparisons at every integer width (hardware multiply is used),
  short-circuit conditions.
* `If`, `Select Case`, `While`, `Repeat`, `For` (with `Break`/`Continue`/`Exit`), `GoTo`.
* Subroutines and functions with by-value, `ByRef` and `ByRefConst` parameters; `Inline`/`NoInline`; modules and `Include`.
* `Abs`, `Min`, `Max`, `Inc`/`Dec` (with an optional amount), `AddressOf` / `@`.
* Preprocessor: `#define`, `#ifdef`, `#if` with `_clock` and `_device`.
* Interrupt handlers (one or two priorities) with automatic context saving and `Save … Restore`
  blocks; `Enable`/`Disable`; event handlers.
* Direct access to every device register and register bit by name, inline assembly, exact
  cycle-counted `DelayMS`/`DelayUS`.
* Compile-time checks: RAM use, hardware stack depth, recursion, array bounds, bad configuration
  values. Errors show the file, line, column and the offending source line.

**Code quality**
* Compared with Microchip XC8 on a set of small kernels, the output is typically about a third smaller
  and about as fast (see `docs/BENCHMARKS.md`, including an interrupt-plus-multiply-and-divide case).
* Optimisations include constant folding, narrowing, Access Bank placement, overlapping of
  routines' variables that are never live together, counted-loop forms and a peephole pass.
  Every test program is also built unoptimised (`-O0`) and checked to give the same results.

**Library** (`docs/LIBRARY.md`; `Float` support comes from `floatlib`, included automatically)

| Module | What it gives you |
|---|---|
| `intosc` | sets the internal oscillator to `Clock` (just `Include` it) |
| `system` | reset cause and clock check |
| `gpio` | port set-up, pull-ups, open-drain |
| `delay` | millisecond/microsecond/second delays |
| `timer` | Timer0, Timer1 (external clock, gate, pulse measurement), Timer2 (hardware-limit and one-shot modes) |
| `serial`, `serial2` | EUSART1 and EUSART2: send/receive bytes, strings and numbers |
| `adc` | 10-bit ADC reads, averaging, millivolts, FVR reference (silicon errata worked around) |
| `eeprom` | data EEPROM read/write (bytes and words) |
| `i2c` | I2C host on MSSP1: write, read, register access, bus ping, bounded waits |
| `spi` | SPI host on MSSP1: all four modes, any clock down to FOSC / 1024 |
| `lcd` | HD44780 character LCD, 4-bit: text, numbers, cursor, custom characters |
| `oled` | SSD1309 128 x 64 OLED over I2C or SPI: text (5 x 7 font), fill, contrast, invert, flip |
| `pwm` | four PWM outputs (CCP1, CCP2, PWM3, PWM4) with a shared frequency and per-channel duty |

## Still to do

* **Library:** program-flash self-write; OLED pixel drawing and bitmaps (`Const` arrays now exist, so a bitmap font table is possible).
* **Language:** overloading, `Reentrant` routines (parsed, rejected by the back end), a few remaining
  string and structure forms (the compiler reports these clearly rather than miscompiling them),
  structure initialisers, arrays of strings and multi-dimensional arrays.
* **Hardware:** everything has been verified in the Microchip simulator, **not yet on a real chip**.
  Serial output, PWM waveforms, I2C and SPI traffic, external timer inputs and the second EUSART
  are the main things that need a hardware run. `docs/MANUAL.md` Appendix B is the bench checklist.
* **More devices:** only the PIC18F27Q10 is supported; each further device is added only after it
  passes its own tests.

## Tools

* **VS Code extension** (`vscode-extension/`): highlighting, snippets, keyword and register-name
  case correction, formatting, diagnostics from `basil --check`, outline, go to definition, hover,
  completion, signature help, and Build / Check / Report commands.
* **pic-config** (`tools/pic-config/`): a Qt 6 helper that turns drop-down choices into a `Config`
  line (or XC8 `#pragma config` lines) to paste into a program. Changed settings are marked and
  can be reverted one by one or all at once.
* **devgen** (`tools/devgen/`): generates a device description (`devices/*.toml`) from a Microchip device pack and cross-checks it against numbers read from the data sheet.

## Using it

Requirements: a Rust toolchain to build the compiler, and Microchip's `pic-as` assembler (from
MPLAB XC8) to assemble and link. Simulator tests additionally need MPLAB X's `mdb`.

```
cargo build --release
target/release/basil prog.bas
```

Useful options: `--report` (sizes), `-S` (stop at assembly), `--check` (type-check only), `-O0`
(no optimisation).

Documentation: the user manual `docs/MANUAL.md` (also `docs/MANUAL.pdf`), language `docs/LANGUAGE.md` and `docs/GRAMMAR.md`, library `docs/LIBRARY.md`,
diagnostics `docs/DIAGNOSTICS.md`, clock and oscillator set-up `docs/CLOCK.md`, benchmarks `docs/BENCHMARKS.md`. For contributors: `PLAN.md`,
`docs/PROGRESS.md`, `docs/DECISIONS.md`. Tests: `cargo test`, and
`BASIL_MDB=1 cargo test --test backend` for the simulator suite.

Personal-use project. Vendor manuals under `reference/` are not part of the repository and must
not be redistributed.
