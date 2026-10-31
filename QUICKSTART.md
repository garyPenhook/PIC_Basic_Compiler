# Quick start

From nothing to a `.hex` file for a PIC18F27Q10 (the same steps work for the PIC18F04/05/06/14/15/16Q41: write `Device = 18F16Q41`; the device pack is `PIC18F-Q_DFP` for both families; the PIC16 parts (PIC16F17126/17146, PIC16F13113 … 13145, PIC16F18313 … 18346 and the PIC16LF18313 … 18346) use `PIC16F1xxxx_DFP`, and `docs/MANUAL.md` "Supported device" lists what each part has).

## 1. Prerequisites

* **Rust** (to build the compiler) and **MPLAB XC8**, installed by you from Microchip (its `pic-as` assembler does the
  last step; basil does not bundle it and its licence does not allow redistribution).
  `basil` looks for `pic-as` in `/opt/microchip/xc8/*/pic-as/bin/pic-as`; to use another one set
  `BASIL_PICAS=/path/to/pic-as` or pass `--pic-as PATH`.
* The **device pack** for the part under `~/.mchp_packs/Microchip/<pack>/<version>/xc8`.
  If it is missing, `basil` says which pack and version it wants.

## 2. Build and install the compiler

```
cargo build --release
ln -sf "$PWD/target/release/basil" ~/.local/bin/basil     # any folder on your PATH
basil --version
```

`basil` finds the `lib/` and `devices/` folders of the nearest parent directory of your source file.
It also carries a copy of both, so the binary works from any folder; a `lib/` or `devices/` next to
your program, or `-L LIBDIR` and `--devices DIR`, take priority over the built-in copy. The built-in copy
is unpacked on first use into `~/.cache/basil/` (or `$XDG_CACHE_HOME/basil/`).

## 3. First program

Save as `blink.bas`:

```basic
Program Blink
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON

Dim led As PORTB.0

ANSELB = 0          ' make port B digital
Output(led)
While True
    Toggle(led)
    DelayMS(500)
Wend
```

* `Device` and `Clock` (MHz) must come first, then `Config` (oscillator and watchdog settings), then
  `Include`s, then declarations, then statements.
* `Clock` only tells the compiler the speed to expect; `Config` (`RSTOSC`) and register writes set it.
  `RSTOSC = HFINTOSC_64MHZ` starts the part at 64 MHz, so use `Clock = 64`. For another speed add
  `CSWEN = ON` to `Config` and `Include "intosc"` (it sets the oscillator to `Clock`), or write `OSCFRQ` yourself.
  See `docs/CLOCK.md`. A mismatch gives the warning `W-CLOCK`.
* Keywords are case-insensitive; the VS Code extension rewrites them to `Dim`, `While`, …, and with a `Device` line it also rewrites register and bit names to the device file's spelling (`lata` becomes `LATA`).

## 4. Compile

```
basil blink.bas            # blink.hex, plus blink.S (assembly) and blink.map
basil --report blink.bas   # also prints code and RAM use per routine and variable
basil --check blink.bas    # front end only: fast syntax and type check, no hex
```

Expected output of the program above:

```
Program: 28 words (56 bytes)
basil: blink.bas -> blink.hex (28 words, 56 bytes)
```

Program the `.hex` with your usual tool (MPLAB IPE, a Curiosity Nano, …).

## 5. Using a library module

Modules live in `lib/` (`gpio`, `serial`, `i2c`, `spi`, `adc`, `pwm`, `timer`, `lcd`, `oled`, `eeprom`, `dma`, …).
Add `Include "name"` after `Config`, and call routines as `Module.Routine`:

```basic
Include "serial"
...
Serial.SerialInit(115200)
Serial.SerialWrite("hello")
Serial.SerialNewLine()
```

See `docs/LIBRARY.md` for every module and `docs/LANGUAGE.md` for the language.

## 6. Editor support

```
cd vscode-extension && npm test && npx @vscode/vsce package
code --install-extension picbasic-0.2.4.vsix
```

Highlighting, keyword case correction, formatting, error squiggles from `basil --check`, go to
definition and build commands. Details in `vscode-extension/README.md`.

## Common problems

| Message | Fix |
|---|---|
| `E-NODEVICE` / `E-DEVICE` | Add `Device = 18F27Q10` as the first line after `Program`; the description must exist in `devices/`. |
| `E-UNDECLARED` | Name is misspelled, or a module is not `Include`d. Device registers (`PORTB`, `ANSELB`) are always known. |
| `E-CONFIG` | Unknown `Config` setting or value; copy the line from the example. |
| `device pack … not found` | Install the pack under `~/.mchp_packs` (MPLAB X or `mplab_platform` downloads it). |
| `pic-as` not found | Set `BASIL_PICAS` or use `--pic-as`. |
| Full list | `docs/DIAGNOSTICS.md` |
