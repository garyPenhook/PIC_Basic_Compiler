# Basil Manual

Revision for **basil 0.1.37**, target devices **PIC18F27Q10** and the **PIC18F04/05/06/14/15/16Q41** family.

This manual describes exactly what the compiler accepts and generates today. It gives an overview of the
language, then one entry per command (Syntax, Overview, Parameters, Example, Notes), then one entry
per library routine. Anything not listed here is not supported; Appendix A lists the alternative
spellings that are accepted and the common BASIC features that are missing or different, and
Appendix B is a checklist to work through when testing.

Status of the code: every feature below passes the Microchip MDB simulator suite and the host test
suite. **Nothing has been run on a real chip yet** (decision D6). Where a feature depends on pin
behaviour the simulator cannot model (serial bytes on the wire, PWM waveforms, external timer
edges, I2C/SPI traffic, LCD/OLED panels), that is stated, and those are the items to test on
hardware first.

Related documents: `docs/LANGUAGE.md` (formal language rules), `docs/GRAMMAR.md`,
`docs/LIBRARY.md`, `docs/DIAGNOSTICS.md`, `docs/CLOCK.md`, `docs/ABI.md`, `QUICKSTART.md`.

---

# Contents

1. Compiler overview
   - Supported device
   - Running the compiler
   - Debugging
   - Program layout
   - Identifiers, labels, comments, line continuation
   - Numeric representations and literals
   - Variables and types
   - `Static` locals
   - `Volatile` variables
   - Aliases and register bits
   - Constants and `Symbol`
   - Arrays, strings, structures
   - Float
   - Operators and expression typing
   - Procedures (Sub, Function, Proc)
   - Interrupts, events and context saving
   - Modules and `Include`
   - Device, Clock, Config
   - Calling C
   - Preprocessor
2. Language commands (alphabetical)
3. Library modules
4. Diagnostics
5. Appendix A: Alternative spellings and unsupported forms
6. Appendix B: Test checklist

---

# 1. Compiler overview

## Supported device

<!-- MAINTENANCE: update this section, the library table in docs/LIBRARY.md ("Device support") and
     the Status column below whenever a device or family is added or changes status. A device is
     "Supported" only when it compiles, its standard test programs pass, and every library module is
     either ported for it or fails with #error (docs/DEVICE-FORMAT.md, "Adding a device", steps 7 and 8). -->

| Device | Core | Program memory | RAM | Status |
|---|---|---|---|---|
| PIC18F27Q10 | PIC18 (8-bit), legacy instruction set (`XINST = 0`) | 128 KB (65,536 words) | 3,359 usable GPR bytes (as reported by the build summary) | **Supported.** Device file `devices/18F27Q10.toml`, generated from pack `PIC18F-Q_DFP 1.31.492`. All library modules |
| PIC18F04Q41, PIC18F05Q41, PIC18F06Q41 (14-pin) | PIC18 (8-bit), legacy instruction set (`XINST = 0`), vectored interrupt controller run with `MVECEN = 0` | 16 / 32 / 64 KB (8 / 16 / 32 K words) | 1,024 / 2,048 / 4,096 usable GPR bytes; 512 bytes data EEPROM | **Supported.** Device files `devices/18F04Q41.toml` … (pack `PIC18F-Q_DFP 1.31.492`, data sheets DS40002242F and DS40002214G, facts in `docs/FACTS-18F-Q41.md`). Ports A and C. Library: every module except `floatlib`, which has not been run there (`gpio`, `delay`, `intosc`, `system`, `timer`, `serial`, `serial2`, `adc`, `eeprom`, `flashwrite`, `spi`, `lcd`, `i2c`, `pwm`, `oled`, `aht30`, and `dma`, which only the Q41 has); `i2c` is a software host and `pwm` uses the six PWM outputs (see `docs/LIBRARY.md`). Tested in the simulator (PIC18F16Q41) and built for every part; not run on hardware |
| PIC18F14Q41, PIC18F15Q41, PIC18F16Q41 (20-pin) | as above | 16 / 32 / 64 KB | 1,024 / 2,048 / 4,096 usable GPR bytes; 512 bytes data EEPROM | **Supported**, as the 14-pin parts, with port B (RB4..RB7) |
| PIC16F17126 (14/16-pin) | PIC16 enhanced mid-range (`pic16e`) | 16K words (28 KB) | 2,048 bytes | **Supported (0.1.50; library and `Float` complete in 0.1.51; assembly `Float` and peephole passes in 0.1.52).** Device file `devices/16F17126.toml` (pack `PIC16F1xxxx_DFP 1.32.471`, data sheet DS40002343F). Integer, Boolean, Char, array, structure, string, `Float`, `Interrupt`, `Reentrant`, `DelayMs/DelayUs` and every library module except `dma` (the part has no DMA) compile and run in the simulator; `AddressOf` of a `Const` array is an FSR address. **Not yet on this core:** calling C, interrupt priorities and `-g` debug information. Single-call routines are inlined (0.1.53). `Float` is assembly on this core and its routines take their operands in `__A`/`__B` (0.1.54; `FMul`/`FDiv` rewritten on them in 0.1.55: a program using `+ * /` is about 605 words, the PIC18's about 615). Nothing has run on a real part |
| PIC16F17146 (20-pin) | PIC16 enhanced mid-range (`pic16e`) | 16K words (28 KB) | 2,048 bytes | As the PIC16F17126 (`devices/16F17146.toml`) |
| PIC16F18313 (8-pin), PIC16F18323 / 18324 / 18325 / 18326 (14-pin), PIC16F18344 / 18345 / 18346 (20-pin) | PIC16 enhanced mid-range (`pic16e`) | 2K / 2K / 4K / 8K / 16K / 4K / 8K / 16K words | 256 / 256 / 512 / 1,024 / 2,048 / 512 / 1,024 / 2,048 bytes; 256 bytes of EEPROM | **Supported (0.1.87; the LF parts 0.1.88).** Device files `devices/16F18313.toml` … `16F18346.toml` (pack `PIC16F1xxxx_DFP 1.32.471`, data sheets DS40001799F, DS40001800E, DS40001795K and DS40001839E, errata DS80000666H, DS80000667E, DS80000668L and DS80000709H, facts in `docs/FACTS-16F183xx.md`). The code generator is the PIC16F171xx one. The PIC16LF18313 … 18346 (1.8 to 3.6 V) have their own device files (`devices/16LF18313.toml` …) with the same registers; their FVR has no 4.096 V gain (DS40001839E Register 16-1). The portable programs and `tests/exec_p16` that apply, with `tests/exec_p183`, pass in the simulator on the PIC16F18346 and the PIC16F18326; every part builds `tests/exec_p183_parts/small.bas`. The power-up clock is chosen with `Config RSTOSC = HFINT32` (32 MHz) or `HFINT1`. Modules: `serial2`, `dma` and `intosc` stop with `#error` (one EUSART, no DMA, `intosc` not ported); `timer` has the old Timer1 and Timer2 (no clock-select or hardware-limit registers, so no `T2Mode*`/`T2Rst*` and no `Timer2StartLimit`); `pwm` offers CCP1, CCP2, PWM5 and PWM6 (channels 1..4); the 8-pin part has port A only and the 14-pin parts no port B. Nothing has run on a real part |
| PIC16F15213 / 15214 (8-pin), PIC16F15223 / 15224 (14-pin), PIC16F15243 / 15244 (20-pin) | PIC16 enhanced mid-range (`pic16e`) | 2K / 4K words | 256 / 512 bytes; no data EEPROM | **Supported (0.1.89).** Device files `devices/16F15213.toml` … `16F15244.toml` (pack `PIC16F1xxxx_DFP 1.32.471`, data sheet DS40002195E, errata DS80000918K, facts in `docs/FACTS-16F152xx.md`). Fixed clock (no clock switching; `intosc` only sets `OSCFRQ`), 10-bit ADC, one MSSP and EUSART, CCP1/2 and PWM3/4. Library: every module is ported or stops with `#error` (`eeprom`, `serial2`, `dma`); see `docs/LIBRARY.md`. Larger parts of the family (PIC16F15225 …) are not described. |
| PIC16F13113 / 13114 / 13115 (8-pin), PIC16F13123 / 13124 / 13125 (14-pin), PIC16F13143 / 13144 / 13145 (20-pin) | PIC16 enhanced mid-range (`pic16e`) | 2K / 4K / 8K words | 256 / 512 / 1,024 bytes; no data EEPROM | **Supported (0.1.76; erratum 1.3.1 work around in 0.1.77).** Device files `devices/16F13113.toml` … `16F13145.toml` (pack `PIC16F1xxxx_DFP 1.32.471`, data sheet DS40002519D, errata DS80001115F, facts in `docs/FACTS-16F1314x.md`). The code generator is the PIC16F171xx one. The portable programs that fit the RAM and flash, `tests/exec_p16` and `tests/exec_p13` pass in the simulator on the PIC16F13145; every part builds `tests/exec_p13_parts/small.bas`. Modules: `serial2` and `eeprom` stop with `#error` (one EUSART, no data EEPROM), `dma` stops with `#error`; `pwm` offers CCP1, CCP2, PWM1 and PWM2 (channels 1..4); the 8-pin part has port A only. Nothing has run on a real part. Erratum 1.3.1 (revisions A2, A3, instruction fetch above 16 MHz) is worked around with a NOP at 0000h and at the handler start when `Clock` is above 16; `#option FetchNop = false` removes them for revision A4; an `Asm` `sleep` needs two `nop`s after it |

`Device = 18F27Q10` (or `PIC18F27Q10`), the PIC18-Q41 parts (`Device = 18F16Q41`, `18F04Q41` …) the PIC16F17126/17146, the PIC16F13113 … 13145, the PIC16F18313 … 18346 (also `16LF18313` … `16LF18346`) and the PIC16F15213 … 15244 are the values that compile today. A device is added only
after it has its own description file and passes its own tests, and **adding one means more than the
description file**:

* a new core family needs its own code generator (PLAN §9.3);
* every library module must be reviewed for the new part: the modules were written for the
  PIC18F27/47Q10 and each one names registers, interrupt flags, pins and channel numbers that can differ
  or not exist. The state of each module per device is in the table in `docs/LIBRARY.md`, "Device
  support: work still to do". A module that is not ported must stop with `#error`, not use the
  Q10 registers;
* this section and that table must be updated, and the new part listed here.

Every register and register bit of the device is available by its pack name (`PORTB`, `LATA`,
`T0CON0`, `PIE0.5`, `SSP1CON1.SSPEN` ...), case-insensitively. A program or library module can ask
whether the chosen device has a register or bit field with `#if _has(REG)` / `#if _has(REG.FIELD)`
(Preprocessor, below), which is how one module serves several layouts.

## Running the compiler

```
basil [--check] [-S] [--report] [-O0] [-g] [-o OUT.hex] [-D NAME] [-L LIBDIR]
       [--devices DIR] [--pic-as PATH] [--version] [--help] <program.bas>
```

| Option | Meaning |
|---|---|
| *(none)* | Compile, assemble and link. Writes `prog.hex`, `prog.S` (assembly), `prog.map`. |
| `--check` | Front end only (syntax, types, declarations). No output files. Fast. |
| `-S` | Stop after writing the assembly (`prog.S`). |
| `--report` | Also print words per routine and every RAM object. |
| `--keep-vars` | Keep stores to variables that nothing reads (the optimiser normally drops them), so a test can inspect them in RAM. A `Volatile` variable is always kept. |
| `-g` | Debug build: adds line, variable and routine information to `prog.elf` for a debugger (see Debugging). The hex file is identical to a build without it. |
| `-O0` | No optimisation (the test suite builds everything both ways and compares). `-O1`, `-O2`, `-Os` are accepted and mean "optimise" (the default). |
| `-o FILE` | Output hex path. |
| `-D NAME` | Define a preprocessor name (visible in every file). |
| `-L DIR` | Add a library folder (repeatable). |
| `--devices DIR` | Folder holding the device descriptions. |
| `--pic-as PATH` | The `pic-as` assembler (otherwise `$BASIL_PICAS`, then `/opt/microchip/xc8/*/pic-as/bin/pic-as`). |
| `--version`, `-V` | Print the version. |
| `--help`, `-h` | Print the option summary and exit. |

`lib/` and `devices/` are found by looking in the source file's folder and then each parent folder
(only the nearest of each is used), so keep programs inside the repository (for example
`my_src/`) or pass `-L` and `--devices`.

After a successful build the compiler prints the program size and a bar of flash and RAM used
against the device (colour only on a terminal, and not when `NO_COLOR` is set):

```
Program: 28 words (56 bytes)
basil: blink.bas -> blink.hex (28 words, 56 bytes)
```

Errors print as `file:line:col: error[CODE]: message`, with the source line and a caret. Several
errors are reported per run. Exit status is non-zero if any error was reported.

## Debugging

`basil -g prog.bas` builds as usual and also makes `prog.elf` describe the program to a debugger
in terms of the BASIC source:

* **Lines.** Every statement is preceded by a `#line` directive in `prog.S`, so pic-as writes a DWARF
  line table that points at the `.bas` files (library modules included), not at `prog.S`. Breakpoints
  and stepping work on BASIC lines. Code the compiler adds itself (start-up, runtime helpers) is shown
  under the nearest preceding statement.
* **Variables and routines.** After pic-as has run, basil appends one DWARF unit to the ELF: each
  global, and each routine's parameters and locals, with their types and fixed RAM addresses
  (`Byte`, `ShortInt`, `Word`, `Integer`, `LongWord`, `LongInt`, `Float`, `Char`, `Boolean`, strings and
  arrays; structures appear as their bytes). Interrupt handlers and routines that were not inlined
  appear as functions, so the call stack shows names and parameter values. The locals of a routine
  the compiler inlined into its one caller are not listed. Several routines may share RAM
  addresses, so only the variables of the routine being stopped in are meaningful.
* **Symbols.** Each variable is also a real ELF symbol (`BLINK_TICKS`, the assembly name), and a global is
  also known by its BASIC name (`ticks`), so command-line debuggers can find it.

`-g` changes nothing in the generated code: the hex file is byte-identical with and without it (checked
over the whole `tests/exec` suite). A build without `-g` carries none of this information.
`prog.hex` and `prog.elf` are written next to the source (or beside `-o`).

### Debugging with the MPLAB X simulator (`mdb`)

Put these lines in `cmds.txt`:

```
device PIC18F27Q10
hwtool sim
program prog.elf
break prog.bas:37
run
wait 5000
where
print ticks
step
quit
```

then run `basil -g prog.bas` and `/opt/microchip/mplabx/v*/mplab_platform/bin/mdb.sh cmds.txt`.
`break file:line` takes a BASIC line, `where` shows the routine with its parameters, `print NAME`
prints a variable and `step` moves to the next BASIC line. A library routine is found by its own file
(for example `serial.bas`).

### Debugging in VS Code

The VS Code extension (`vscode-extension/`) runs the debug build and starts Microchip's debugger on the
result. It needs the *MPLAB Extension Pack* and the device pack of the target. Hardware (PICkit, ICD,
Snap) is only needed for a real chip; the simulator needs none.

| Command (Ctrl+Shift+P, "PIC BASIC: ...") | Key | What it does |
|---|---|---|
| New Project | | Creates a folder with the `.bas`, `picbasic.json`, `.vscode/launch.json`, `tasks.json` and `dist/`. |
| Pick Target Device | | Changes the `Device` line, `picbasic.json` and `launch.json`. |
| Select Programmer/Debugger | | Simulator or a connected PICkit / ICD / Snap, stored per project. |
| Build | F7 | `basil`, then copies `.hex`, `.elf`, `.map` into `dist/`. |
| Build Debug | Ctrl+F7 | `basil -g`, then the same copy. |
| Program Device | F8 | Builds and programs `dist/<name>.hex` with the selected hardware tool. |
| Show Build Output | | Opens the output channel. |

Start debugging with F5 (configuration `PIC BASIC: Debug`; F9 breakpoint, F10 / F11 / Shift+F11 step).
Run Build Debug first, or the debugger will not find `dist/<name>.elf`. The extension's settings are
listed in `vscode-extension/README.md`.

### Editing in Zed

The Zed extension (`zed-extension/`) gives the editor side of the same workflow. It does not program
or debug a chip (use the VS Code extension or `basil -g` with Microchip's tools for that).

| Piece | What it gives |
|---|---|
| Highlighting, outline, brackets, comments | A tree-sitter grammar for basil source (`grammar/`), case-insensitive keywords, with the keyword lists of the VS Code extension. |
| Language server `basil-lsp` | `basil --check` diagnostics (on change) with the file, line and column of each error; keyword and symbol completion (also after `.`); keyword hover; the document outline (`lsp/basil-lsp.js`, Node, no dependencies). It reads the standard library only. |
| Tasks | `basil: build`, `check (front end only)`, `debug build (-g)`, `resource report`, `build + open assembly`, `clean outputs`, `version` (Run Task: `task: spawn`). |
| Snippets | Common program shapes, installed as `snippets/basil.json`. |
| Project settings | `.zed/settings.json` pins `.bas` to Basil (the Swordfish extension claims the same suffix) and turns off its language server. |

Install (needs Node, `rsync` and `basil` on the PATH):

```
cargo install tree-sitter-cli        # once
zed-extension/scripts/zed-install.sh # run from the repository root; safe to re-run
```

The script generates the parser, publishes `grammar/` as a local git repository and pins
`extension.toml` to it, links `basil-lsp` into `~/.local/bin`, and merges the tasks and snippets into
`~/.config/zed`. Then, in Zed, run `zed: install dev extension` and choose the `zed-extension` folder.
The extension is not published to the Zed extension store.

The keys are not installed by the script. To get the same keys as the VS Code extension, add
bindings to `~/.config/zed/keymap.json`:

```json
{
  "context": "Editor && extension == bas",
  "bindings": {
    "f7":       ["task::Spawn", { "task_name": "basil: build" }],
    "ctrl-f7":  ["task::Spawn", { "task_name": "basil: debug build (-g)" }],
    "f6":       ["task::Spawn", { "task_name": "basil: check (front end only)" }],
    "shift-f7": ["task::Spawn", { "task_name": "basil: resource report" }]
  }
}
```

## Program layout

A source file is a **program** or a **module**.

```basic
Program Name                        ' name is optional
    Device = 18F27Q10               ' required, before any Include or declaration
    Clock  = 16                     ' MHz; required for anything using delays or timing
    Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
    Include "module"                ' zero or more
    ' constants, types, variables, aliases
    ' subroutines, functions, interrupts, events
    ' statements - the main program
```

* There is no `Main`. The top-level statements run in order. Statements of included modules (their
  initialisation) run first, in include order.
* A program that runs off its end loops forever (a self-branch); it never runs into empty flash.
* **Order is enforced**: Device/Clock/Config, then `Include`, then constants/types/variables/aliases,
  then routines, then statements. After the first executable statement, `Include`, `Dim` and
  routine declarations are an error (`E-ORDER`).
* Identifiers must be declared before use. A routine that is defined further down can be announced with `Declare` (see *Forward declarations*).
* The program and all modules are compiled together. A module included by several files is loaded once.

A `Proc ... EndProc` flat/procedural layout is accepted (see *Procedures*).

## Identifiers, labels, comments, line continuation

* **Identifiers**: letter or `_`, then letters, digits and `_`. Not case sensitive (`Label`, `LABEL`
  and `label` are the same). A variable cannot have the name of a device register (`trisa` clashes
  with `TRISA`; `W-REGNAME`).
* **Reserved words** cannot be names (`E-RESERVED`). Notable ones that catch people out: `Inc`,
  `Dec`, `High`, `Low`, `Input`, `Output`, `Toggle`, `Clock`, `Device`, `Type`, `Result`, `Step`,
  `Next`, `Event`, `Loop`, `Do`, `Symbol`, `Proc`, `Declare`. The full list is in `src/lexer.rs`
  (`KEYWORDS`).
* **Labels**: `name:` as the first thing on a line with nothing after the colon. Labels are local to the
  routine (or to the top-level code) and must be unique there. Jump with `GoTo name`.
* **Comments**: `'` or `//` to end of line; `(* ... *)` or `{ ... }` for blocks (these nest inside
  each other, but not themselves with mixed closers).
* **Several statements on one line**: separate with `:`.
* **Line continuation**: end a line with a space and `_`.

## Numeric representations and literals

| Form | Example | Notes |
|---|---|---|
| Decimal | `100` | |
| Hexadecimal | `$FF`, `0xFF` | `0x` or `0X`; digits in either case |
| Binary | `%1010`, `0b1010` | `0b` or `0B` |
| Floating point | `3.14`, `1.0e3`, `1.5E-2` | |
| Character | `"A"` | a Char, or a one-character String, by context |
| Character code | `#65`, `#13 + #10` | Char with the given code; can be concatenated |
| String | `"Hello"` | up to 255 characters |
| Booleans | `True`, `False` | |
| `Null` | `Null` | string terminator / empty string |

## Variables and types

```basic
Dim Name As Type
Dim Name1, Name2 As Type
Dim Name As Type = constant          ' initial value
Dim Name = constant, Name2 = 5 As Type
```

| Type | Bits | Range / meaning | Alternative spelling |
|---|---|---|---|
| `Boolean` | 1 | `True` / `False`. Cannot hold a number | |
| `Bit` | 1 | 0 / 1 | `Bit` |
| `Byte` | 8 | 0 to 255 | `Byte` |
| `ShortInt` | 8 | -128 to 127 | `SByte` |
| `Word` | 16 | 0 to 65,535 | `Word` |
| `Integer` | 16 | -32,768 to 32,767 | `SWord` |
| `LongWord` | 32 | 0 to 4,294,967,295 | `Dword` |
| `LongInt` | 32 | -2,147,483,648 to 2,147,483,647 | `Long` |
| `Float` | 32 | IEEE-754 binary32, about +/-3.4e38, 6 to 7 digits | `Float` |
| `Char` | 8 | one character | |
| `String(n)` | n+1 bytes | up to n characters plus a terminating `Null` | |
| `Structure` | | see *Structures and unions* | |

**Note on `Long`:** here `Long` is the signed 32-bit type (`LongInt`), not a 24-bit
unsigned `Long`. There is no 24-bit type; 24 bits is only used inside the compiler. `SDword` and
`Double` are not accepted. A `Pin` type is not accepted.

* All variables are zeroed at start-up unless they have an initialiser. A routine's local variables
  are zeroed **at every entry**, and an initialiser is applied at every entry too (use `Static` to
  keep a local between calls).
* Declarations are `Private` by default; `Public` exports from a module.
* Name lookup order: local, then the current file, then the `Public` names of included modules.
  Qualify with `Module.Name` to resolve a clash.
* Global variables must fit the device RAM (`E-RAM`). The hardware return stack is checked at
  compile time (the device's depth: 31 levels on the Q10, 127 on the PIC18-Q41; `E-STACK`).

### Type conversion

`Byte(x)`, `Word(x)`, `Integer(x)`, `LongWord(x)`, `LongInt(x)`, `ShortInt(x)`, `Float(x)`,
`Boolean(x)`, `Bit(x)`, `Char(x)`, and the alternative spellings `SByte(x)`, `SWord(x)`, `Dword(x)`,
`Long(x)`. A constant that does not fit the target type is an error (`E-CONST-RANGE`). Conversion
to `String` is not supported. Float to integer truncates toward zero.

### `Static` locals

```basic
Static Dim Name As Type [= constant]
Static Dim Name(n) As Type [= (v1, v2, ...)]
```

**Overview.** An ordinary local is created afresh each time its routine runs: it is zero (or its
initial value) at every entry, and its RAM is shared with other routines. A `Static` local instead
keeps its value from one call to the next, like a `static` variable in C. It is still visible only
inside the routine that declares it.

**What the compiler does.** A `Static` local gets its own RAM address that no other routine uses.
It is cleared once at start-up, and an initial value (including a whole array or string
initialiser) is applied once before the main program starts, not at each call. The cost is that the
RAM is permanently reserved, whereas an ordinary local costs nothing when its routine is not
running.

**Rules.**

* Only inside a `Sub`, `Function`, `Interrupt` or `Event`. At module level every variable already
  lasts for the whole run, so `Static Dim` there is error `E-DIM`.
* Applies to a variable, not an alias (`E-DIM`). It can be combined with `Volatile`, in either order.
* It may be used in an interrupt handler (the value then persists between interrupts). `Save ...
  Restore` does not save or restore it, because it is not part of the routine's overlaid frame.
* There is one copy of it, shared by every caller. If a routine with a `Static` local is called
  from both the main program and an interrupt handler, they update the same variable, exactly as
  with a module-level variable; mark it `Volatile` as well if either side polls it.

**Example.**

```basic
Function NextId() As Byte
    Static Dim id As Byte = 100     ' set to 100 once, at start-up
    Inc(id)
    Result = id
End Function

Dim a, b As Byte
a = NextId()    ' 101
b = NextId()    ' 102
```

### `Volatile` variables

```basic
Volatile Dim Name As Type
Private Volatile Dim Name As Type
Static Volatile Dim Name As Type      ' inside a routine
```

**Overview.** `Volatile` tells the compiler that the variable can change, or be observed, by
something outside the code it is compiling: an interrupt handler, an `Asm` block, or the hardware
(for example a variable that mirrors a register). Every read and every write written in the source
is carried out, in the order written.

**What changes.** Normally the optimiser may keep a value in `WREG` or a scratch register and reuse
it, merge two reads into one, replace a variable by a known constant, or delete a store to a
variable that is never read. For a `Volatile` variable it does none of these:

| Source | Ordinary variable | `Volatile` variable |
|---|---|---|
| `x = flag : y = flag` | `flag` may be read once | read twice |
| `flag = 1 : flag = 2` | first store may be dropped | both stores happen |
| write to a variable nothing ever reads | store removed | store kept |
| `Do : If flag = 0 Then ... : Loop` | may reuse a loaded value | reloaded on every pass |

**Rules and cost.** Allowed on any scalar, array, string or structure `Dim` at any level; not on an
alias (`E-DIM`). A volatile access can be a word or two larger than the same access to an ordinary
variable, so use it only where it is needed. `Volatile` does not make a multi-byte access atomic:
a `Word` or `LongWord` shared with an interrupt handler can still change between its bytes; read it
between `Disable(Handler)` and `Enable(Handler)`, or keep the shared value to one `Byte`.

**Example.** A flag set by a handler and polled by the main program:

```basic
Volatile Dim tick As Byte

Interrupt Timer()
    tick = 1
    ' clear the flag of your interrupt source here
End Interrupt

' set up the source and its PIEx enable bit first
Enable(Timer)
Do
    If tick = 1 Then          ' reloaded on every pass of the loop
        tick = 0
        ' ... handle the event ...
    End If
Loop
```

## Aliases and register bits

An alias creates a second name for existing storage; it uses no RAM.

```basic
Dim LED As PORTB.0               ' a register bit
Dim Flags As Byte
Dim Ready As Flags.0             ' a bit of a variable
Dim LowNibble As Flags.Bits(4)   ' see the modifier table
Symbol Button = PORTA.3          ' alternative spelling, same effect
```

| Modifier | Gives |
|---|---|
| `.n` or `.Bits(n)` | bit n |
| `.Booleans(n)` | bit n as a Boolean |
| `.Byte0` ... `.Byte3`, `.Bytes(n)` | byte n of a multi-byte value |
| `.Word0`, `.Word1`, `.Words(n)` | word n |
| `.AsLongWord` and similar | a larger view of smaller storage (promotion), for example `Dim L As Arr(0).AsLongWord` |

Aliases may chain. A bit alias is a `Bit`; it cannot be used directly as a condition (`E-COND`):
write `If LED = 1 Then`. Any device register or register bit can be read and written by name
without declaring it: `PORTB`, `TRISB`, `ANSELB = 0`, `PIE0.5 = 1`, `SSP1CON1.SSPEN = 1`.

## Constants and Symbol

```basic
Const Name = expression               ' type inferred
Const Name As Type = expression
Symbol cLimit = 100                   ' the = is optional
Symbol LED = PORTB.0                  ' becomes an alias, chosen by what the value is
```

A constant without a type takes its type from the expression: `5 / 1024` is integer arithmetic and
is 0; write `5.0 / 1024` for floating point. Constants can be used in array sizes, `Case` values
and anywhere a constant expression is required. `_Clock` and `_Device` are predefined constants
(the `Clock` value and the device name), and so are `_FlashBytes` (a `LongWord`), `_EepromBytes` and
`_RamBytes` (`Word`s): the program flash, data EEPROM and allocatable RAM of the device, in bytes.

## Arrays, strings, structures

### Arrays

```basic
Dim a(5) As Byte                       ' FIVE elements: a(0) .. a(4)
Dim t(3) As Byte = (1, 2, 3)           ' initialiser: exactly 3 values
Const Tbl(4) As Byte = (10, 20, 30, 40)  ' lives in program memory
```

* The number in brackets is the **element count**. `Bound(a)` is the highest index (4 here), so
  `For i = 0 To Bound(a)` visits every element.
* Element types: the integer types, `Char`, `Boolean`, `Bit`, `Float`, `String(n)` and structures.
* More than one dimension: `Dim m(3, 4) As Byte` is 3 rows of 4, stored row by row, and is indexed
  `m(i, j)` with exactly one index per dimension (`E-ARGS` otherwise). A constant index outside its
  dimension is `E-BOUNDS`. An initialiser is one flat list in row order. The array can be copied
  and cleared as a whole, but a routine that receives it as `p() As Byte` sees one flat dimension.
* An array of strings, `Dim names(3) As String(8)`, is indexed like any array: `names(i) = "abc"`,
  `s = names(i)`, `names(i)(0)`. It can have an initialiser, `Dim names(3) As String(6) = ("one", "two", "")`, one string for each element. In a string assignment the index may read
  an array element or call a routine; in a comparison (`names(ix(j)) = s`) it must not (`E-BACKEND`).
* A constant index outside the array is a compile error (`E-BOUNDS`). A run-time index is not
  checked.
* `Const` arrays are read-only (reading by index works; assigning a `Const` array to a same-sized RAM
  array copies it).
* `Bit` and `Boolean` arrays that are only indexed are packed eight to a byte. Writing one through a
  run-time index is a read-modify-write: do not write other elements of the same array from an
  interrupt (the compiler turns interrupts off around the write).
* Arrays are passed to routines as `ByRef` (written `p() As Byte`) or `ByRefConst`.
* `Clear(a)` zeroes an array; `a = b` copies same-sized arrays.
* Not supported: `Const` arrays of Float, functions that return an array.

### Strings

```basic
Dim s As String(20)                    ' 21 bytes
Dim t As String(10) = "hi"
s = "abc"                              ' from a literal, another string, a Char
s = s + "def"                          ' in-place append
s = "x" + t + "y"                      ' + chain
s = "x" + s                            ' the target anywhere: built in a hidden copy first (more code than an append)
If s = "abc" Then ...                  ' = and <> only
If s + t = "abcd" Then ...             ' either side can be a + chain (built in a hidden String of its full size)
c = s(1)                               ' element, zero-based, a Char
Clear(s)
Left(t, s, 3)                          ' first 3 characters of s into t
Right(t, s, 3)                         ' last 3 characters
Mid(t, s, 2, 3)                        ' 3 characters from position 2 (zero-based, like s(2)); Mid(t, s, 2) takes the rest
Str(t, n)                              ' the decimal text of a whole number
n = Val(s)                             ' the whole number a String starts with (a LongInt)
```

`Left`, `Mid` and `Right` are statements, not functions: the destination comes first and must be a `String`
variable (an element of an array of strings is fine); the source is a `String` or a literal. The text is cut off at
the destination's size and always ends in `Null`. A count past the end of the source, or a position past
it, gives what is there (possibly the empty string); counts and positions can be any whole number, a negative one
counts as too large. Destination and source can be the same string. They are ordinary names that a program's own
declaration of `Left`, `Mid` or `Right` replaces. They are written out as loops, so a call costs 30 to 55 words on
the PIC18; put repeated uses in a routine.

`Str(dst, n)` is a statement too: it writes the decimal text of the whole number `n` (any integer type; a
negative one starts with `-`) into the `String` variable `dst`, cut off at its size and ended with `Null`.
`Val(s)` is a function that returns a `LongInt`: an optional `+` or `-`, then decimal digits up to the first other
character (or the `Null`). Text with no digits gives 0, a value too big for 32 bits wraps, and a literal is worked
out at compile time. Convert the result for a narrower variable (`w = Word(Val(s))`). Both are written out as loops
(`Str` of a Byte is about 60 words on the PIC18, of a Word 75 plus the 16-bit divide, of a LongInt 165 plus the
32-bit divide; `Val` about 100), so put repeated uses in a routine. A program's own `Str` or `Val` replaces them.
Neither handles a `Float`.

Oddities to know about:

* A String or structure function result is copied into a hidden object *before* the statement it is in runs, so
  in `x = F() + G(Name(1))` the call of `Name` happens first. On the right of `And` or `Or` it runs only when the
  left side does not decide the result. In an `ElseIf` or `Until` condition it is `E-BACKEND`; in a `While`
  condition it is fine (re-run on every pass).
* The same goes for an array-read index on a String element in a comparison (`If n(k(i)) = s`) and for `Val`.
* A `ByVal` String or structure costs the callee a block copy on entry; use `ByRefConst` when it only reads.
* A `Reentrant` function returning a String or structure keeps a second, static copy of its result (its size
  in RAM again) and copies into it on every return. `Save(F)` covers that copy too.
* `Val` stops at the first character that is not a digit (no leading spaces, no decimal point, no `0x`), and
  wraps past 32 bits. `Str` cuts the text off at the destination's size, keeping the leading characters
  (`Str` of 65535 into a `String(3)` gives `655`). Neither handles a `Float`.
* A concatenation passed as an argument is built in a hidden String of its full size (at most 255).

Assignments are cut off at the declared size and always terminated with `Null`. There is no run-time
bounds check on `s(i)`. String literals live in program memory and are read with `TBLRD`.
A `String` parameter is `ByRef` (size must match the callee's `String(n)` exactly), `ByRefConst`
(any size, also accepts a literal, a concatenation or a function result) or `ByVal` (any size, cut off at the parameter's size).

`Len(s)` is in the `strings` module (`Include "strings"`; see its section). `Left`, `Mid`, `Right`, `Str` and `Val` are built in (below). Not supported: `Print`. Output of text is done by the library routines
(`SerialWrite`, `LcdWrite`, `OledWrite`).

### Structures and unions

```basic
Structure TStatus
    Val       As Byte
    Enabled   As Val.0           ' alias field: shares storage with Val (a union)
    Connected As Val.1
End Structure

Structure TPoint
    X As Word
    Y As Word
End Structure

Dim p As TPoint
Dim pts(4) As TPoint             ' arrays of structures; structures may nest
p.X = 100
pts(2).Y = 7
Clear(p)
```

Fields are reached with `.`. `Clear(x)` zeroes a structure. A structure can be given initial
values in field order, `Dim p As TPoint = (3, 4)`. The list is **flat**, as for a multi-dimensional array: one
constant for each number, `Boolean`, `Bit`, `Char`, `Float` or `String` in the structure, so an array field takes one
value per element and a nested structure one per field, in order. Union members (alias fields) take none.

```basic
Structure TBox
    id   As Byte
    tab(3) As Byte
    at   As TPoint
    name As String(4)
End Structure
Dim b As TBox = (1,  10, 20, 30,  7, 300,  "hi")     ' id, tab(0..2), at.X, at.Y, name
Dim pts(2) As TPoint = (1, 2, 3, 4)                 ' an array of structures: pts(0) = (1, 2), pts(1) = (3, 4)
```

## Float

`Float` is IEEE-754 binary32 (sign, 8-bit exponent, 23-bit fraction). It is implemented in
`lib/floatlib.bas`, which the compiler adds automatically to any program that mentions `Float`; only
the routines used are linked.

* Supported: variables, constants, arrays, parameters, results; `+ - * /`; unary minus; `Abs`; the six
  comparisons; mixed integer and Float expressions (the integer is converted); `Float(x)` and the
  integer conversions `Byte(f)`, `Integer(f)`, ... (truncating).
* Rounding is to nearest even. Infinities and NaN propagate. Denormals are flushed to zero.
* Not supported: `Sqr`, `Sin`, `Cos`, `Tan`, `Log`, `Exp`, `Pow`, `fRound` and the other math
  functions; `Print`/`Str` of a Float; a Float as a `For` variable, in `Select`, or with `Inc`/`Dec`;
  `=` and `<>` between floats are available but avoid them as for any float.
* Cost: about 700 words for `+`, 800 for `*`, 470 for `/`, plus about 250 shared (roughly 2,500 words
  for a program using all three).
* In an interrupt handler, float arithmetic is an error (`E-ISR-CALL`): do it in a routine and call
  that inside `Save(...) ... Restore`. Copying a Float, negation and `Abs` are allowed. A 4-byte Float
  is not read atomically.

## Operators and expression typing

Highest precedence first:

| Level | Operators |
|---:|---|
| 1 | `@` (address), unary `-`, unary `+`, `Not` |
| 2 | `*`, `/`, `Mod` |
| 3 | `+`, `-` |
| 4 | `<<`, `>>` |
| 5 | `=`, `<>`, `<`, `>`, `<=`, `>=` |
| 6 | `And` |
| 7 | `Or`, `Xor` |

* `And`, `Or`, `Xor`, `Not` are **logical** on Booleans and **bitwise** on integers. Mixing a
  Boolean and a number is an error (`E-MIX`). Conditions short-circuit left to right.
* There is no `\`, `^`, `&`, `|`, `~`, `<<=` or `Dig`/`?`, `@` bit reverse, `Dcd`/`Ncd`.
* **Evaluation width.** An integer expression is evaluated at the width of its widest operand or its
  target, whichever is larger, and no wider. `B3 = B1 + B2` is an 8-bit add that wraps; `W = B1 * B2`
  is a full 16-bit product (hardware 8 x 8 multiply). A comparison is evaluated at the wider of its
  two sides.
* **Mixing signedness.** Signed and unsigned operands of the same width cannot be combined without a
  conversion (`E-SIGN`); a narrower unsigned operand is widened safely; a narrower signed operand
  against a wider unsigned one is rejected. Unary minus on an unsigned variable widens to the next
  signed type.
* **Narrowing.** A constant that does not fit is an error; a non-constant narrowing is the warning
  `W-NARROW` (error under `#option Strict = true`).
* **Division and `Mod`** truncate toward zero; `Mod` takes the dividend's sign. Divide by zero at run
  time gives an all-ones quotient and the dividend as remainder; in a constant expression it is an
  error. A division by a power-of-two constant becomes a shift. A constant multiplier becomes shifts
  or `MULLW` steps.
* **Shifts.** The count must be a constant or a `Byte`. Shifting by the width or more gives 0 (or the
  sign for a signed right shift). `>>` is arithmetic for signed types.
* Functions may be used in expressions; subroutines may not. Parentheses are needed when calling
  with arguments.

## Procedures (Sub, Function, Proc)

```basic
[Public|Private] [Inline|NoInline] Sub Name([params])
    ' declarations and statements
End Sub

[Public|Private] [Inline|NoInline] Function Name([params]) As Type
    ' assign to Result (or to the function name)
End Function

param := [ByVal | ByRef | ByRefConst] Name [()] As Type [= constant]
```

Equivalent alternative forms are accepted:

```basic
Proc Name(p As Byte)                 ' = Sub
    ...
    ExitProc                         ' = Exit
EndProc

Proc Double(pValue As Byte), Word    ' = Function ... As Word, value in Result
    Result = pValue * 2
EndProc
```

* Parameters are **by value** by default for scalars; arrays, `String` and structures are `ByRef`
  (or `ByRefConst`). A `ByRef` argument must be a variable, not an expression. A `ByRef` parameter
  can be a Byte/Word/etc. scalar, an array, a String or a structure. A `String` or structure can also be
  written `ByVal`: the caller passes its address and the routine copies it into its own object first thing, so
  changing the parameter leaves the caller's variable alone (the copy costs the routine one block copy; a `ByVal`
  String of any size is accepted and cut off at the parameter's size). A `ByVal` array is not allowed, and a
  `String` or structure parameter has no default value.
* A default value is allowed only on a trailing `ByVal` parameter, and must be a constant.
* A function returns a scalar, a structure or a `String` (not an array). A structure or String result is left in the
  function's frame and copied out at once, so it can be used as the whole right side of an assignment
  (`p = MakePoint(3)`, `s = Name(1)`), as a `+` operand in a String assignment (`s = "<" + Name(1) + ">"`), as an argument
  to a `ByVal` or `ByRefConst` parameter (`Show(MakePoint(3))`, `n = Count(Name(1) + "!")`) and in a String comparison
  (`If Name(1) = "cde" Then`). Such a result is copied into a hidden object of the caller's before the statement
  runs, so it is not evaluated at its place in the expression: in `x = F() + G(Name(1))` the call of `Name` comes first.
  On the right of `And` or `Or` it still runs only when the left side does not decide the result. In the condition of
  an `ElseIf` or a `Repeat ... Until` it is not supported (`E-BACKEND`); a `While` condition is fine. A `Reentrant` function
  returns a structure or String the same way; each return copies `Result` into a static object of the function's
  (its size in RAM again) that a recursive call's frame restore leaves alone. A `ByRefConst` parameter can be a
  structure, and a `ByRef` or `ByRefConst` array can hold structures or strings. Calling a function as a
  statement discards its result.
* **No recursion** (`E-RECURSION`). Because the call graph is acyclic, the compiler gives every
  routine static storage and **overlays** the storage of routines never live at the same time, so
  RAM use is the deepest call chain, not the sum. Declaring working variables locally saves RAM.
  A routine marked `Reentrant` may call itself; see *Reentrant routines* below.
* A routine called once is inlined by default; `Inline` forces and `NoInline` forbids it.
* **Overloading**: several routines may share a name when their parameter types differ. A call
  picks the overload whose parameters its arguments fit best (an exact type match first, then the
  narrowest type that holds the value); a call that fits two equally well is `E-AMBIG`, one that
  fits none is `E-OVERLOAD`, and two routines with the same parameter types are `E-REDECL`.
  `AddressOf(Name)` of an overloaded name is `E-AMBIG`. Compound subroutines are not supported.

### Reentrant routines

```basic
Reentrant Function Fact(ByVal n As Byte) As Word
    If n <= 1 Then
        Result = 1
    Else
        Result = Fact(n - 1) * n
    End If
End Function
```

A `Reentrant` routine may call itself (directly, or through other routines when the whole cycle is
reentrant). Its variables still have fixed addresses; a recursive call first pushes the caller's
variables and temporaries on a software stack (FSR2) and puts them back when the call returns, so
a recursive call costs two instructions per byte of the routine's frame. The stack is sized by
the compiler (32 pushes of the largest frame) and exists only in programs that recurse.
Each level also uses one of the 31 hardware return-address levels, so **recursion deeper than
about 30 calls resets the device** (stack overflow); the compiler does not know the depth and does
not check it. `Static` locals are shared by all levels. Mutual recursion needs a forward declaration (below).

### Forward declarations

`Declare` gives a routine's heading before its body, so that a routine defined earlier can call it:

```
Declare Reentrant Function IsOdd(ByVal n As Byte) As Boolean

Reentrant Function IsEven(ByVal n As Byte) As Boolean
    If n = 0 Then
        Result = True
    Else
        Result = IsOdd(n - 1)
    End If
End Function

Reentrant Function IsOdd(ByVal n As Byte) As Boolean
    If n = 0 Then
        Result = False
    Else
        Result = IsEven(n - 1)
    End If
End Function
```

The definition must come later in the same file and repeat the parameter types and modes, the result type, `Reentrant`
and the `Public`/`Private` word of the `Declare`; the parameter names may differ. A parameter with a default value
has one in both. A declaration that is never defined, or a definition that differs from it, is `E-FORWARD`. A
cycle of calls still needs `Reentrant` on at least one routine in it (`E-RECURSION` otherwise). `Declare` must be
among the declarations, before the first statement. Overloads are declared one by one.
* Routines are called as `Name(args)`, or `Module.Name(args)`.

## Interrupts, events and context saving

### Interrupts

```basic
Interrupt Name([priority])
    ' handler body
End Interrupt
```

An interrupt handler is a routine the hardware calls when an enabled source raises its flag. It has
no parameters, no result, and is never called by name.

* With one handler, write no priority: the compiler picks the vector. With two handlers, the low one
  is `Interrupt Name(ipLow)` (`ipLow = 1`) and the high one `Interrupt Name(ipHigh)` (`ipHigh = 2`).
  More handlers than vectors may be *declared*, but only one per priority can be *enabled*.
* The 18F27Q10 has fixed vectors. A handler is not attached to its vector until `Enable` commits it.
* Library modules never declare an `Interrupt`; they set up peripherals and read flags, and your
  program writes its own handler.
* A handler declares its own locals, which have their own storage and are never overlaid with
  main-line routines.
* **Clear the source's flag inside the handler.** Hardware never clears it, so a handler that forgets
  re-enters forever.
* The handler runs between any two instructions of the main program. Keep it short; a wide
  variable (Word, LongWord, Float) shared with the main program is **not** read or written atomically,
  so copy it with the interrupt disabled or use a Byte flag. Cycle-counted delays (`DelayMS`,
  `DelayUS`) run longer when interrupted.
* `Exit` leaves the handler early; its end restores the context and returns.

### Enabling and disabling

```basic
Enable(Name)        ' commit the handler to its vector and set the global enable
Disable(Name)       ' clear the global enable bit(s)
```

`Enable` and `Disable` touch only the **global** bits (`GIE/GIEH`, `PEIE/GIEL`). Turning on one
source is the program's job, in this order:

1. configure the peripheral;
2. clear its flag (`PIRx`);
3. set its enable bit (`PIEx`);
4. with two priorities, set its priority bit (`IPRx`; they reset to *high*);
5. `Enable(Name)`.

`Disable` does not remove the handler from its vector; `Enable` can turn it back on. Enabling two
handlers of the same priority is an error (`E-ENABLE`). Clearing the global bit inside a handler is
undone by the return from it.

### Context saving

The compiler saves what a handler needs, but a handler is not a normal routine.

* **Hardware shadow registers.** `STATUS`, `WREG` and `BSR` are saved in the fast register stack for
  a lone handler. With two priorities the high one uses the shadow registers, and the low one saves
  and restores the same three in software (a high interrupt would overwrite the shadow copies).
  `#option ISR_SHADOW = false` forces software saving for both.
* **Nothing else is saved.** Any statement that needs a library routine, a helper, or a routine's
  frame (a call, or Float arithmetic) would use
  storage the interrupted main program may be using. The compiler refuses it with `E-ISR-CALL` unless
  you protect it with `Save`.

```basic
Save(item {, item})
    ' statements
Restore
```

Each `item` is a variable, a routine, or the constant `0`. `0` saves the compiler's working
registers (including `FSR0` and `FSR1`). A routine item saves that routine's storage **and that of
everything it calls**. Inside a handler the compiler also adds the storage of every routine the
block calls, so the usual form is `Save(0, Routine)` around a call to `Routine`.

```basic
Dim total As Word
Function Cube(ByVal v As Byte) As LongWord
    Result = v * v * v
End Function

Interrupt MyInt()
    Dim big As LongWord
    Save(0, Cube)              ' working registers + Cube's parameter, temporaries and result
        big = Cube(10)
    Restore
End Interrupt
```

Without the `Save`, `Cube` would overwrite RAM the main program's own routines share with it, and
the interrupted routine would resume with damaged data. Decide what to save by reading the
datasheet, by looking at the routine you call, and by reading the generated `.S` file for registers
it touches.

`Exit`, `Break` and `Continue` that leave a `Save` block restore first. `GoTo` and labels inside it
are not supported. Float arithmetic, comparisons and conversions in a handler are `E-ISR-CALL`
directly: do them in a routine and call it inside `Save`. Copying a Float, `-f` and `Abs(f)` are
plain bit operations and are allowed.

### Events

An **event** lets one piece of code (a library module, say) run a handler that *another* piece of
code supplies, without either knowing about the other. It is the safe way to "plug code into" an
interrupt: the module owns the interrupt and its hardware, and the program supplies what happens.

```basic
Type TEvent = Event()            ' 1. a type of handler
Event Beep()                     ' 2. a handler
    Toggle(PORTB.0)
End Event
Dim OnTick As TEvent             ' 3. a variable that can hold one
OnTick = Beep                    ' 4. point it at the handler
OnTick()                         ' 5. call through the variable
```

```basic
Type TName = Event([ByVal param As Type {, ByVal param As Type}])
[Public|Private] Event Name([ByVal param As Type {, ByVal param As Type}])
    ' declarations and statements
End Event
```

* **An event cannot be called by its name.** Only through a variable of an event type
  (`Beep()` is `E-CALL`). The variable is what you hand to a module as a parameter.
* **Parameters.** An event type and its handlers can take `ByVal` parameters of an integer type,
  `Boolean` or `Char` (nothing else: no `ByRef`, arrays, strings, structures or default values, `E-PARAM`).
  A handler fits a variable only if its parameter types are exactly those of the type
  (`Type TRx = Event(ByVal c As Byte)` takes `Event OnByte(ByVal c As Byte)` but not
  `Event OnByte(ByVal c As Word)`; the assignment is `E-TYPE`). The parameter names may differ. A
  call gives the right number of arguments (`E-ARGS`), each converted as for a routine.
* An event has no result. To get data back, use a variable both sides can see.
* A handler name is assigned to a variable of an event type (`OnTick = Beep`). A variable that has
  never been assigned does nothing when called, so a module can call its event without testing it.
  Assign again to change the handler at run time.
* **Comparing.** `=` and `<>` compare two event variables of one type, or a variable and a handler
  name: `If OnTick = Beep Then ...`. Nothing else compares (`<`, `>` and so on are `E-TYPE`).
* **Arrays.** `Dim Table(4) As TEvent` makes five event variables, called through an index:
  `Table(i)()` or, with arguments, `Table(i)(3)`. An array of events starts empty: assign its elements one by one
  (`Table(0) = Beep`); an initialiser list is refused (`E-DIM`). Unassigned elements do nothing.
* A variable of an event type holds **one byte**: 0 for none, otherwise the number of a handler. It
  is not an address.
* Event variables can be copied (`B = A`), passed `ByVal` to a routine, and be module-level or
  local variables.
* Only handlers that are named in an assignment or comparison are compiled. An event nobody assigns
  costs nothing.
* `Event` is `Private` by default; mark it `Public` to use it from another module. The type, the
  variable and the parameter use the same `Public`/`Private` rules as any other name.
* `Exit` leaves the handler early.

**How a call works.** A call through a variable is a call to one shared dispatcher routine (one
per parameter list), which compares the byte and calls the matching handler, passing the arguments
on. Handlers are ordinary routines to the compiler: they get frames laid out by the call graph and
overlaid like those of any routine, and are only reachable through the dispatcher.

**Events and interrupts.** Calling an event from an interrupt handler is the intended use, and it
needs no `Save`: the compiler wraps the call as `Save(0) ... Restore` itself, which preserves the
working registers and the storage of the dispatcher and every handler (and what they call). Writing
your own `Save` around it is allowed; then no second one is added. Keep two things in mind:

* A handler that runs from an interrupt gets the same respect as the interrupt itself. It
  interrupts the main program at any point, so keep it short, and do not make it call routines the
  main program also uses unless you save them (those calls still need `Save`, `E-ISR-CALL`).
* A **high and a low priority interrupt must never call the same event handler**, because one could
  interrupt the other halfway through it.

**Example: a module that raises an event from an interrupt.** `MyRX.bas` owns the interrupt and
the receive hardware; the program decides what a received byte means. The handler gets the byte as
an argument.

```basic
Module MyRX

Public Type TRxEvent = Event(ByVal c As Byte)
Dim FOnData As TRxEvent

Interrupt OnRX()
    FOnData(RC1REG)            ' the module reads the byte and passes it on
End Interrupt

Public Sub Initialize(ByVal pOnData As TRxEvent)
    FOnData = pOnData
    ' ... set up the receiver and its PIEx bit here ...
    Enable(OnRX)
End Sub
```

```basic
Program MyRXProgram
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "myrx"

Event GotChar(ByVal c As Byte)
    If c = 32 Then
        High(PORTB.0)
    ElseIf c = 42 Then
        High(PORTB.1)
    EndIf
End Event

MyRX.Initialize(GotChar)
While True
Wend
```

The program reacts to every received byte without containing or knowing about the interrupt, and the
module can be reused with a different handler (or none: an unassigned `FOnData` does nothing).

**Events and the library.** The library modules never declare an `Interrupt` themselves, because
a vector can be claimed only once and a handler without a priority would clash with a program that
uses two priorities. The `timer` and `serial` modules instead provide an event variable and a
`...Service` routine: assign your handler, then call the service routine from the main loop, or from
your own interrupt (`Save(0, Timer0Service)` around the call). See `Timer0OnExpire` and
`SerialOnRx` in section 3.

```basic
Include "timer"
Dim ticks As Byte
Event Tick()
    Inc(ticks)
End Event
Timer0OnExpire = Tick
Timer0Start(15, 255)
While True
    Timer0Service()          ' calls Tick once per Timer0 overflow
Wend
```

**Differences from Swordfish.** Swordfish gives every event its own frame that is never shared;
here handler frames overlay by the call graph, which saves RAM, and the compiler's implicit `Save`
(above) is what makes the call from an interrupt safe. Event parameters, comparison and arrays are
additions.

## Modules and Include

```basic
Module Name
    Public Sub Hello()
    End Sub
    ' statements here are start-up code, run before the main program
```

`Include "name"` loads `name.bas` from the including file's folder, then the project `lib/` folder,
then any `-L` folder, once per compile. Only `Public` names are visible. Call as `Name.Routine()`
or by the bare routine name when unambiguous. The spelling of a module's own name is what you write
after the `.`: `Include "serial"` then `Serial.SerialInit(115200)`.

## Device, Clock, Config

* **`Device = 18F27Q10`**: required (`E-NODEVICE`).
* **`Clock = n`** (or `Declare Xtal = n`): the instruction-clock source frequency in MHz that the
  program is built for, fractions allowed (`Clock = 0.5`). Delays, baud rates and timer periods are
  computed from it.
* **`Clock` does not set the hardware.** The oscillator is set by `Config RSTOSC` and by register writes. Either
  start the part at the speed you declare (`RSTOSC = HFINTOSC_64MHZ` with `Clock = 64`), or add
  `CSWEN = ON` and `Include "intosc"`, which writes `OSCFRQ`/`OSCCON1` for you. A mismatch with nothing
  setting the oscillator gives `W-CLOCK`. Details: `docs/CLOCK.md`.
* **`Config NAME = VALUE, ...`**: configuration words by pack names, validated against the device
  (`E-CONFIG`). Settings not mentioned take the pack default and the compiler prints a note listing
  them. Typical line:

```basic
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
```

### Choosing Config values with pic-config

`tools/pic-config/` is a small Qt 6 program that builds the `Config` line from drop-downs, so the setting
and value names do not have to be looked up. It knows PIC18F27Q10, PIC18F04/05/06/14/15/16Q41, PIC16F17126/17146, the
nine PIC16F13113 … 13145 parts, the sixteen PIC16F183xx / PIC16LF183xx parts and the six PIC16F152xx parts.

![pic-config showing a PIC18F05Q41](images/pic-config.png)

* **Device** lists the parts it has data for; one drop-down per configuration setting, grouped by
  configuration word with its address. Each value shows its meaning.
* **Output** is `Config NAME = VALUE` for basil or `#pragma config` lines for XC8. The text pane is what you
  paste into the program; **Copy to clipboard** copies it. Below it are the resulting configuration word
  values.
* A setting changed from its default is shown in bold with a revert button; **Clear all changes** puts
  every setting back. **Only settings changed from default** limits the output to those. **Comments**
  adds a line explaining each changed value.
* **Clock** adds `Device`, `Clock` and `Include "intosc"` lines so the output is a whole program header, and
  warns when the chosen speed needs `CSWEN = ON`.
* **Add device file...** loads another Microchip `.cfgdata` (found under `xc8/pic/dat/cfgdata/` in the
  device pack) without rebuilding.

Build and run (needs Qt 6 and CMake):

```
cmake -S tools/pic-config -B tools/pic-config/build -G Ninja -DCMAKE_PREFIX_PATH=$HOME/Qt/6.12.0/gcc_64
cmake --build tools/pic-config/build
tools/pic-config/build/pic-config
```

To add a part, drop its `<device>.cfgdata` into `tools/pic-config/data/devices/` and re-run cmake.

## Calling C

A Basic program can call functions written in C. Use this for code that already exists in C (a checksum, a protocol
parser, a vendor driver) or that is easier to write there. The C is built by the MPLAB XC8 C compiler, which must be
installed (`xc8-cc` is looked for beside `pic-as`; `BASIL_XC8CC` names it explicitly). C can also call Basic routines
(*Calling Basic from C*, below).

Two things are written in the Basic program:

* `CFile "name.c"` names the C source (or an XC8 object or library) to link in. It is a header line, written with
  `Device`, `Clock` and `Config`, before the first `Include`. The path is relative to the folder of the main program.
* `Extern Function name(...) As Type` or `Extern Sub name(...)` declares one C function, with no body. The name is the C
  name, **spelled exactly as in the C file** (C is case-sensitive; Basic is not). The parameters and the result have the
  types of the C function. After that, the function is called like any other routine.

### A complete example

`checksum.c` is an ordinary C file; it has no `main()`:

```c
static unsigned char total;            /* C data: zero at start, like any C program */

/* CRC-8, polynomial 0x07, one byte at a time. */
unsigned char crc8(unsigned char crc, unsigned char data)
{
    unsigned char i;
    crc ^= data;
    for (i = 0; i < 8; i++)
        crc = (crc & 0x80) ? (unsigned char)((crc << 1) ^ 0x07) : (unsigned char)(crc << 1);
    return crc;
}

void total_add(unsigned char v) { total += v; }

unsigned int total_get(void) { return total; }

long scale(int v, unsigned char mul) { return (long)v * mul; }
```

`main.bas`, in the same folder:

```basic
Program CallC
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF

CFile "checksum.c"
Extern Function crc8(crc As Byte, data As Byte) As Byte
Extern Sub total_add(v As Byte)
Extern Function total_get() As Word
Extern Function scale(v As Integer, mul As Byte) As LongInt

Dim crc As Byte
Dim tot As Word
Dim r As LongInt
Dim i As Byte

crc = 0
For i = 1 To 9
    crc = crc8(crc, 48 + i)        ' the bytes of "123456789"; the CRC-8 of that text is 0xF4
    total_add(i)
Next
tot = total_get()                  ' 1 + 2 + ... + 9 = 45

r = scale(-300, 7)                 ' -2100: a signed argument and a signed 32-bit result
```

Build it with `basil main.bas`. When the run reaches the end, `crc` is 244 (0xF4), `tot` is 45 and `r` is -2100. This
program is `tests/exec_c/c_example.bas` and is run in the simulator by the test suite.

### Types

| Basic | C | Bytes |
|---|---|---|
| `Byte`, `Char`, `Boolean` | `unsigned char` | 1 |
| `ShortInt` | `signed char` | 1 |
| `Word` | `unsigned int` | 2 |
| `Integer` | `int` | 2 |
| `LongWord` | `unsigned long` | 4 |
| `LongInt` | `long` | 4 |

A `Float` is a C `float` (four bytes, IEEE 754 single precision, the same bits as in Basic). A function result is one of
these types or `Float`; a `Sub` returns nothing (`void`). `Bit`, a `String`, array or structure passed by value, and default
values are not supported (`E-EXTERN`). Declare the C function with the same types and number of parameters as the
`Extern` line; basil cannot check the C file against it, but the linker refuses a C definition whose types differ from
the ones basil uses (`conflicting declarations`).

**By reference.** A `ByRef` (or `ByRefConst`) parameter passes the address of the variable, and the C parameter is a
pointer to the element type, written exactly so:

| Basic parameter | C parameter |
|---|---|
| `ByRef a As Word` | `unsigned int *a` |
| `ByRef a As Float` | `float *a` |
| `ByRef a() As Byte` (an array) | `unsigned char *a` (the length is not passed; pass it as another parameter) |
| `ByRef a() As Pt` (an array of structures) | `struct Pt *a` (the structures are packed one after the other) |
| `ByRef s As String(16)` | `char *s` (the characters, then a Null) |
| `ByRef p As Pt` (a `Structure`) | `struct Pt *p` (the tag is the Basic name, case included) |
| `ByRefConst s As String(16)` | `const char *s` |

The fields of a structure are stored in order with no padding, which is what XC8 does for PIC18, so the C `struct` lists
the same fields with the same types (a `String(n)` field is `char f[n+1]`, an array field `T f[n]`). C may read and
write through the pointer during the call only.

### What happens when the program runs and when it is built

* The XC8 start-up code runs first and sets up the C data (zeroed variables, variables with initial values). It then
  calls the program, which runs the Basic start-up code and your statements. C variables keep their value between
  calls, so C can hold state (`total` above).
* RAM is shared without overlap: the RAM that the Basic program uses is kept away from the C data and C stack.
* `basil` writes `<name>_basil.S` (the Basic program as assembly), `<name>_cstub.c` (a small generated C file) and the
  `.hex` and `.map`, and links them with your C files through `xc8-cc` (C is compiled with `-Os`). The linker's messages
  are shown if it fails.
* An `Extern` routine that the program never calls is not linked, and `CFile` alone changes nothing.

### Cost and limits

* Each call copies the arguments and the result through a small RAM buffer (`basil_io`, as large as the biggest
  argument list or result) and a generated C wrapper: about two program words per argument or result byte plus the
  wrapper, and the buffer's RAM. Call C for work that is worth that, not for one-instruction operations.
* The call into C uses a hardware stack level, and the C function's own calls use more. `E-STACK` counts the call but
  not what happens inside the C code, so check the depth of nested C calls yourself.
* A program that calls C can have `Interrupt` handlers; basil writes their vectors itself (at 08h and 18h). Do not write
  `__interrupt` functions in the C files; they would use the same vectors. The handler saves what it uses, so C code
  that is interrupted carries on unharmed.
* **A handler may call an `Extern` routine**, like any routine, inside `Save(…) … Restore` (without it, `E-ISR-CALL`);
  `Save` also saves everything C may change (FSR0 to FSR2, `TBLPTR`, `TABLAT`, `PROD`, `PCLATH`/`PCLATU`). C uses static
  frames and the shared `basil_io`, so it must never be entered twice: when any handler (or a routine it calls) calls
  C, **every call into C runs with the global interrupt enable off** (it is put back only if it was on), from the first
  argument byte to the last result byte. Costs: about ten more program words per `Extern` routine, and an interrupt
  that comes during a C call waits for it, so keep the C routines a handler shares short. A program in which no handler
  reaches C has none of this. The hardware stack is shared with the handler, so allow for the C code's depth on top of
  the handler's.
* `-g` works: the debugger sees the Basic variables beside the C debug information.
* The names `main` and `basil_...` are used by the generated C and cannot be `Extern` names.
* The flash used by a C build starts at 0x1002 in the XC8 layout.
* Not yet run on hardware.

### Calling Basic from C

`Export Function name(...) As Type` or `Export Sub name(...)` is an ordinary routine, with a body, that C code may call:

```basic
CFile "work.c"
Extern Function run(n As Byte) As Word

Dim total As Word

Export Function Square(x As Byte) As Word
    Result = x * x
End Function

Export Sub Accum(v As Word)
    total = total + v
End Sub

Dim r As Word
r = run(6)
```

```c
extern unsigned int Square(unsigned char x);
extern void Accum(unsigned int v);

unsigned int run(unsigned char n)
{
    unsigned char i;
    unsigned int s = 0;
    for (i = 0; i < n; i++) { s += Square(i); Accum(s); }
    return s;
}
```

The C declaration has the types the table above gives (an `Export` parameter or result is an integer, `Char`, `Boolean`
or `Float`, or a `ByRef` scalar, `String` or structure; no arrays, no defaults, no `Reentrant`). An exported routine can
also be called from Basic as usual.

* C reaches Basic only from inside an `Extern` routine, because the Basic program is the one that runs first and never
  returns. The frames of the exported routines are therefore never shared with those of the routines waiting for the C
  call; basil takes care of that.
* **No recursion through C.** If an exported routine (or a routine it calls) calls an `Extern` routine, `E-RECURSION`
  is reported, as the exported routine could be called again while it runs. `Reentrant` does not apply.
* An `Interrupt` handler may call C (see above), and C called from a handler may call an exported routine; the routine runs
  in the handler, so its frame is saved by the handler's `Save` like that of any routine the handler calls.
* The cost is the same as for a call into C: the arguments pass through `basil_io`.

### If the build fails

| Message | Cause |
|---|---|
| `xc8-cc not found` | MPLAB XC8 C compiler not installed beside `pic-as`; set `BASIL_XC8CC` |
| `C file ... not found` | the `CFile` path is relative to the main program's folder |
| `undefined symbol _name` from the linker | the C function is not in a `CFile`, or the `Extern` name differs from the C name in case or spelling, or the C function is `static` |
| `E-EXTERN` | parameter or result type not supported, a default value, a reserved name, or the same name declared twice with different types |
| `conflicting declarations for variable "_name"` from the linker | the C definition has other types than the `Extern` line gives (see the tables above) |

## Preprocessor

| Directive | Notes |
|---|---|
| `#define NAME [value]`, `#undefine NAME` | scoped to the file that defines them (only `-D` names are shared) |
| `#ifdef`, `#ifndef`, `#else`, `#endif` | |
| `#if`, `#elseif`, `#else`, `#endif` | expressions with numbers, `_clock`, `_device`, `_has(REG)` (true when the device description defines that register, or with `REG.FIELD` that bit field, any letter case: `#if _has(ANSELB)`, `#if _has(OSCFRQ.HFFRQ)`; `_ram` and `_eeprom` are the part's usable data RAM and data EEPROM in bytes (`_eeprom` is 0 on the PIC16F13145 family); the older (legacy) field names of a register count too: `_has(ADREF.ADPREF)` is true on the PIC18-Q41, whose field is `PREF`), `= <> < > <= >=`, `in (a, b, ...)`, `not`, `and`, `or`, parentheses. A device name is written bare: `#if _device = 18F27Q10` |
| `#error "text"`, `#warning "text"` | |
| `#option Optimize = Size\|Speed\|Balanced`, `Strict = true\|false`, `ISR_SHADOW`, `FetchNop = true\|false` (PIC16F13145 family above 16 MHz: a NOP at 0000h and at the start of the handler for erratum 1.3.1, default true), `Warn.<id> = true\|false` | |

Not supported: `#constant`, `#variable` (`E-PP-UNSUPPORTED`). Of the predefined names, only `_clock`,
`_device`, `_ram` and `_eeprom` exist in `#if`. Directives inside `(* *)` or `{ }` comments are ignored.

---

# 2. Language commands

Entries are alphabetical. In the syntax lines `[x]` is optional and `{x}` is repeated. Every command
is written with parentheses where it takes arguments (`High(led)`, not `High led`). Keywords are
case-insensitive. The examples are fragments that assume the program header

```basic
Program Demo
Device = 18F27Q10
Clock = 16
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, CSWEN = ON, WDTE = OFF, LVP = ON
Include "intosc"
```

followed by the lines shown. `Dim` lines come first, as the language requires.

---

## Abs

**Syntax**
```basic
result = Abs(value)
```
**Overview** Absolute value of a number.

**Parameters** `value` is any numeric expression: a signed or unsigned integer, or a `Float`. The result
has the type of `value`. An unsigned value is returned unchanged.

**Example 1** An integer variable.
```basic
Dim a As Integer
Dim b As Integer
a = -1234
b = Abs(a)                ' 1234
```
**Example 2** A `Float`: the sign bit is cleared.
```basic
Dim f As Float
Dim g As Float
f = -2.5
g = Abs(f)                ' 2.5
```
**Notes** A constant argument is folded at compile time. `Abs(-32768)` of an `Integer` (and the most
negative value of any signed type) overflows and stays negative, as in any two's-complement system. The
argument is evaluated more than once, so it must not contain a function call (a back-end error
otherwise); assign the call to a variable first.

**See also** `Min`, `Max`.

## AddressOf  (and `@`)

**Syntax**
```basic
p = AddressOf(item)
p = @item
```
**Overview** The address of a variable, register, array, array element, structure field, constant array
or routine.

**Parameters** `item` is the thing whose address is wanted. For RAM objects and registers the result
is a `Word` holding the data-memory address (an array element with a run-time index gives the address of
that element). For a `Const` array or a routine the result is a `LongWord` holding the 24-bit
program-memory address (for a `Const` array, of its first byte). Anything else is `E-ADDR`.

**Example 1** The address of a variable and of an array element.
```basic
Dim x As Byte
Dim a(4) As Byte
Dim k As Byte
Dim px As Word
Dim pe As Word
k = 2
px = AddressOf(x)
pe = @a(k)
```
**Example 2** A routine and a constant table, as program-memory addresses.
```basic
Const Tbl(3) As Byte = (1, 2, 3)
Dim pr As LongWord
Dim pt As LongWord
Sub Blink()
    Inc(PORTB)
End Sub
pr = AddressOf(Blink)
pt = @Tbl
```
**Notes** The address of a routine keeps it in the program even if nothing calls it. The address of a
bit, a `Const` array element chosen at run time, or an expression is not supported. An index in the
operand must not contain a call. The address of a `ByRef` parameter is the address of the caller's
variable.

**See also** `Asm`, `Bound`.

## Asm ... End Asm

**Syntax**
```basic
Asm [Preserves(W, STATUS, BSR)]
    instruction ...
End Asm
```
**Overview** Raw `pic-as` source, passed through unchanged. The compiler assumes the block changes
`WREG`, `STATUS` and `BSR` unless `Preserves(...)` says otherwise, and will not move its own code across
it. A variable used only inside `Asm` still gets storage. Variables are referred to by their emitted
symbol names (see `docs/ABI.md`; the names are in the `.S` and `.map` files).

**Parameters** `Preserves(...)` is optional and lists the registers the block leaves unchanged.

**Example**
```basic
Asm Preserves(W, STATUS, BSR)
    nop
    nop
End Asm
```
**Notes** Comments inside the block are assembler comments (`;`). The block ends at a line holding
`End Asm`. Stack use of `call` in raw `Asm` is counted by the `E-STACK` check.

## Bound

**Syntax**
```basic
n = Bound(array)
```
**Overview** Highest valid index of an array. For a declared array it is a constant (`Dim a(5)` gives
4, because an array of 5 has indexes 0..4). For an array **parameter** it is a run-time `Word`.

**Example**
```basic
Dim a(5) As Byte
Dim i As Byte
For i = 0 To Bound(a)
    a(i) = i
Next
```
**See also** `For ... Next`, `Clear`.

## Break

**Syntax**
```basic
Break
```
**Overview** Leaves the innermost `For`, `While`, `Repeat` or `Do` loop. Outside a loop it is an error
(`E-LOOP`).

**Example**
```basic
Dim x As Byte
While True
    Inc(x)
    If x > 3 Then
        Break
    EndIf
Wend
```
**See also** `Continue`, `Exit`.

## CFile, Extern

**Syntax**
```basic
CFile "file.c"
Extern Function name(param As Type, ...) As Type
Extern Sub name(param As Type, ...)
```
**Overview** `CFile` names a C source file, XC8 object or library that is linked into the program. `Extern` declares a
function of that code, with no body. The C name is the name written in the `Extern` line, case included. A program that
calls an `Extern` routine is linked by `xc8-cc` (see *Calling C* in chapter 1 for the whole picture and the full example).

**Parameters** `file.c` is relative to the folder of the main program. `CFile` goes with the `Device`, `Clock` and
`Config` lines, before the first `Include`, and can be given more than once. Each `Extern` parameter is `ByVal` and
`Byte`, `Char`, `Boolean`, `ShortInt`, `Word`, `Integer`, `LongWord`, `LongInt` or `Float`, with no default value, or
`ByRef`/`ByRefConst` (a variable, array, `String` or structure, passed as a pointer); the result is one of the
by-value types, or none for a `Sub`. `Export` (below) is the same declaration with a body, for a routine C calls.

**Example**
```basic
CFile "checksum.c"
Extern Function crc8(crc As Byte, data As Byte) As Byte    ' unsigned char crc8(unsigned char, unsigned char)
Extern Sub total_add(v As Byte)                            ' void total_add(unsigned char)

Dim c As Byte
c = crc8(c, 0x31)
total_add(c)
```
**Notes**
* Errors: `E-EXTERN` for an unsupported type, a default value, `Reentrant`/`Inline`, a name that is `main` or
  starts with `basil_`, two `Extern`s of one name with different types, or a call to an `Extern` routine from an
  `Interrupt` handler. `E-EXPORT` for a name exported twice or also declared `Extern`; `E-RECURSION` for a call cycle
  through C. An `Export` array parameter is `E-EXTERN`.
* The generated assembly is `<name>_basil.S`; the stub is `<name>_cstub.c`.
* Not yet run on hardware.

**See also** `Asm`, *Calling C* (chapter 1), `docs/ABI.md` section 7.

## Clear

**Syntax**
```basic
Clear(variable)
```
**Overview** Sets a variable, array, string or structure to zero.

**Example**
```basic
Dim a(4) As Byte
Dim w As Word
Clear(a)
Clear(w)
```

## Continue

**Syntax**
```basic
Continue
```
**Overview** Jumps to the next iteration of the innermost loop (`E-LOOP` outside a loop). In a `For`
loop the variable is stepped first.

**Example**
```basic
Dim i As Byte
Dim n As Byte
For i = 0 To 9
    If i = 5 Then
        Continue
    EndIf
    Inc(n)
Next
```
**See also** `Break`.

## Dec

**Syntax**
```basic
Dec(variable [, amount])
```
**Overview** Subtract one from an integer variable, array element or structure field, or subtract
`amount`. Not for `Float`.

**Parameters** `variable` is the item to decrement. `amount` is an optional integer constant, variable
or expression; it is converted to the type of `variable`.

**Example 1**
```basic
Dim n As Byte
n = 10
Repeat
    Dec(n)
Until n = 0
```
**Example 2** Subtracting an amount.
```basic
Dim level As Word
Dim amt As Byte
level = 1000
amt = 25
Dec(level, amt)          ' 975
Dec(level, 75)            ' 900
```
**Notes** On an array element with a run-time index the index is evaluated twice, so it must not
contain a call. The result wraps like any assignment. A bit cannot take an amount.
**See also** `Inc`.

## DelayMS / DelayUS

**Syntax**
```basic
DelayMS(milliseconds)
DelayUS(microseconds)
```
**Overview** Cycle-counted delays computed from `Clock`. The compiler works out the loop counts at
compile time. With a constant argument the achieved error is reported.

**Parameters** A constant, or a variable of any integer type. A negative constant is an error. A
**variable** delay needs an integral number of instruction cycles per unit at the given `Clock`;
otherwise the build fails rather than rounding silently.

**Example**
```basic
Dim led As PORTB.0
ANSELB = 0
Output(led)
While True
    Toggle(led)
    DelayMS(500)
Wend
```
**Notes** Interrupts lengthen a delay. The simulator suite checks exact cycle counts (for example
1,600, 16,000 and 8,000,000 cycles for the test delays). `DelaySeconds` is in the `delay` module.

**See also** `Clock` (section 1), `delay` module.

## Disable / Enable

**Syntax**
```basic
Enable(HandlerName)
Disable(HandlerName)
```
**Overview** `Enable` assigns the handler to its vector and sets the global interrupt bits (`GIE/GIEH`,
`PEIE/GIEL`); `Disable` clears them. They do not enable a particular source: set its `PIEx` bit
yourself. Enabling two handlers of the same priority is an error (`E-ENABLE`).

**Example**
```basic
Dim ticks As Byte
Sub Count()
    Inc(ticks)
End Sub
Interrupt Tick()
    Save(0, Count)
        Count()
    Restore
    ' clear the flag of your interrupt source here
End Interrupt
' set up the source and its PIEx enable bit first (the timer module has TimerNEnableInterrupt)
Enable(Tick)
Disable(Tick)
```
**See also** *Interrupts, events and context saving* (section 1), `Save`.

## Do ... Loop

**Syntax**
```basic
Do
    ...
Loop

Do While condition ... Loop
Do Until condition ... Loop
Do ... Loop While condition
Do ... Loop Until condition
```
**Overview** Accepted as spellings of `While`/`Repeat`: `Do...Loop` = `While True`; `Do While c` =
`While c`; `Do Until c` = `While Not c`; `Loop While c` = `Repeat ... Until Not c`; `Loop Until c` =
`Repeat ... Until c`.

**Example**
```basic
Dim x As Byte
Do
    Inc(x)
Loop Until x > 3
Do While x > 0
    Dec(x)
Loop
```
**See also** `While`, `Repeat`.

## Exit / ExitProc

**Syntax**
```basic
Exit
ExitProc                     ' alternative spelling
```
**Overview** Leaves the current `Sub`, `Function` or `Proc`. For a `Function` the current `Result` is
returned.

**Example**
```basic
Function Clamp(ByVal a As Byte) As Byte
    Result = 100
    If a >= 100 Then
        Exit
    EndIf
    Result = a
End Function
Dim x As Byte
x = Clamp(42)
```
**See also** `Break`.

## For ... Next ... Step

**Syntax**
```basic
For variable = start To end [Step constant]
    ...
Next
```
**Overview** `variable` must be an integer variable (not `Float`, not a bit). `end` is evaluated once.
`Step` must be a constant; a negative `Step` counts down. After a loop that ran, the variable holds
the last value it took. The variable must not be changed inside the loop (`E-LOOPVAR`). A `Byte`
loop to 255 is safe (it does not wrap forever).

**Example 1**
```basic
Dim i As Byte
Dim a(8) As Byte
For i = 0 To Bound(a)
    a(i) = i * 2
Next
```
**Example 2** Counting down by two.
```basic
Dim i As Byte
For i = 10 To 0 Step -2
    DelayMS(1)
Next
```
**See also** `Break`, `Continue`, `Bound`.

## GoTo

**Syntax**
```basic
GoTo label
If condition GoTo label
```
**Overview** Jump to a label in the same routine. A label is a name followed by a colon at the start
of a line. `GoSub`/`Return`, `Call` and computed `On GoTo` are not supported.

**Example**
```basic
Dim x As Byte
Again:
Inc(x)
If x < 5 GoTo Again
```
**Notes** `GoTo` and labels are not allowed inside a `Save` block.

## High / Low / Toggle / Input / Output

**Syntax**
```basic
High(bit)         ' drive 1
Low(bit)          ' drive 0
Toggle(bit)       ' invert
Input(bit)        ' make an input (TRIS = 1)
Output(bit)       ' make an output (TRIS = 0)
```
**Overview** `bit` is a `Bit`/`Boolean` variable or alias, or a register bit such as `PORTB.4`. `High`,
`Low` and `Toggle` act on the **latch** (`LATx`), and `Input`/`Output` on `TRISx`, so a pin set high is
not disturbed by read-modify-write of other pins (`High(led)` on `PORTB.0` generates `bsf LATB,0`).
To set a whole port direction or value, write the register: `TRISB = 0`, `LATB = $FF`.

**Example**
```basic
Dim led As PORTB.0
GpioAllDigital()          ' needs Include "gpio"; or write ANSELB = 0
Output(led)
High(led)
Toggle(led)
If led = 1 Then           ' a bit alias is compared, not used bare
    Low(led)
EndIf
```
**Notes** Parentheses are required: `High LED` and `High 1` (pin numbers) are **not** accepted. Pins
reset to analog, so make them digital first. Pin numbers for the library routines are 0..23 (`RA0` = 0,
`RB0` = 8, `RC0` = 16).

**See also** `gpio` module, `PinMode`.

## PinMode

**Syntax**
```basic
PinMode(pin, Mode)
```
**Overview** Makes a pin an input or an output, or turns on its internal pull-up resistor.

**Parameters** `pin` is a port bit (`PORTB.0`, or a `Bit` alias of one), a whole port (`PORTB`), or a
pin number: `RA0` = 0 … `RA7` = 7, `RB0` = 8, `RC0` = 16 and so on, 8 numbers to a port. A pin number may be a
constant or any `Byte` expression. `Mode` is a word, not an expression:

| Mode | Effect |
|---|---|
| `Input` | `TRISx` bit = 1 (same as `Input(pin)`) |
| `Output` | `TRISx` bit = 0 (same as `Output(pin)`) |
| `PullUp` | `WPUx` bit = 1; the pin should already be an input |
| `Input_PullUp` | `Input`, then `PullUp` |

**Example**
```basic
PinMode(PORTB.0, Input)            ' RB0 an input
PinMode(0, Output)                 ' RA0 an output
PinMode(8, Input_PullUp)           ' RB0 an input with its pull-up on
For p = 0 To 15                    ' p is a Byte: flash every pin of ports A and B
    PinMode(p, Output)
    DelayMs(500)
    PinMode(p, Input)
Next
```
**Notes**
* `PinMode(PORTB, PullUp)` writes `WPUB = 0xFF`: every pin of the port gets its pull-up, whatever its direction. A run-time pin number must fit a Byte.
* A port bit or a constant pin number compiles to one `bsf`/`bcf` (PIC18) per register, as `Input(pin)` does. A pin number in a variable
  compiles to a short run-time sequence that picks the port by `pin >> 3`; it changes `TRISx`/`WPUx` by read-modify-write, so do not use it on a
  port that an interrupt handler also changes. A run-time pin number the device has no port for changes nothing; a constant one is the error `E-PIN`.
* Like `Input`/`Output`, `PinMode` does not clear `ANSELx`: a pin that resets to analog must be made digital first.
* A device with no `WPUx` register for the port has no individual pull-ups: the pull-up part of `PullUp` and `Input_PullUp` is skipped with the warning `W-NOPULLUP`.
* Parentheses are required (`PinMode PORTB.0, Input` is not accepted), and `Pin_A0` style names do not exist: use the number or `PORTA.0`.

## PinSet / PinClear

**Syntax**
```basic
PinSet(pin)
PinClear(pin)
```
**Overview** Sets (`PinSet`) or clears (`PinClear`) the output latch of a pin without changing its direction, so a pin that is an input
takes the level when it is later made an output. `pin` is as for `PinMode`: a port bit, a whole port, or a pin number (constant, or any `Byte`
expression, `RA0` = 0, `RB0` = 8 ...).

**Example**
```basic
Dim p As Byte
Output(PORTB)
PinSet(PORTB.0)        ' RB0 high
PinClear(9)            ' RB1 low
For p = 8 To 15
    PinClear(p)        ' each pin of port B in turn
    DelayMS(100)
    PinSet(p)
Next
```
**Notes**
* `PinSet(PORTB.0)` is the same code as `High(PORTB.0)`; `PinSet(PORTB)` writes `LATB = 0xFF`, `PinClear(PORTB)` writes `LATB = 0`.
* A run-time pin number changes `LATx` by read-modify-write (see `PinMode`); do not use it on a port that an interrupt handler also changes.
  A pin number the device has no port for changes nothing; a constant one is the error `E-PIN`.
* The `pinio` module has a routine `PinSet(pin, level)` of its own; it is called as `Pinio.PinSet(pin, level)`, and a bare `PinSet(pin)` is this command.

**See also** `PinMode`, `PinPullup`, `High`, `Low`.

## PinPullup

**Syntax**
```basic
PinPullup(pin)
PinPullup(Enable, pin)        ' also On
PinPullup(Disable, pin)       ' also Off
```
**Overview** Turns the internal pull-up resistor of a pin, or of every pin of a port, on or off by writing its `WPUx` bit. With no mode it turns it on.
The mode is a word (`Enable`, `On`, `Disable` or `Off`), not an expression.

**Example**
```basic
PinPullup(PORTB.0)             ' RB0 pull-up on
PinPullup(Enable, PORTB)       ' every pull-up of port B on
PinPullup(Disable, 9)          ' RB1 off
PinPullup(Off, p)              ' the pin number in the Byte p
```
**Notes** A device with no `WPUx` register for the port has no individual pull-ups: the request is skipped with the warning `W-NOPULLUP`.
There are no `Pin_A0` style names: use `PORTA.0` or the number. The pull-up works only while the pin is an input.

**See also** `PinMode`, `PinSet`, `PinClear`.

## If ... Then ... ElseIf ... Else ... EndIf

**Syntax**
```basic
If condition Then
    ...
ElseIf condition Then
    ...
Else
    ...
EndIf

If condition GoTo label
```
**Overview** The condition must be Boolean (`E-COND`); `And` and `Or` short-circuit. Bit aliases are
compared: `If led = 1 Then`.

**Example**
```basic
Dim x As Byte
x = 7
If x < 5 Then
    x = 0
ElseIf x < 10 Then
    x = 1
Else
    x = 2
EndIf
```
**Notes** The single-line form `If x Then y = 2` is rejected with a message; use a block or
`If c GoTo label`.

## Inc

**Syntax**
```basic
Inc(variable [, amount])
```
**Overview** Add one to an integer variable, array element or structure field, or add `amount`. Not for
`Float`.

**Parameters** `variable` is the item to increment. `amount` is an optional integer constant, variable
or expression; it is converted to the type of `variable`.

**Example 1**
```basic
Dim n As Byte
Repeat
    Inc(n)
Until n > 10
```
The loop above is the equivalent of `For n = 1 To 10`.

**Example 2** Adding an amount.
```basic
Dim w As Word
Dim amt As Byte
w = 1
amt = 10
Repeat
    Inc(w, amt)
Until w > 100
```
**Notes** On an array element with a run-time index the index is evaluated twice, so it must not
contain a call. The result wraps like any assignment. A bit cannot take an amount.

**See also** `Dec`.

## Min / Max

**Syntax**
```basic
r = Min(a, b)
r = Max(a, b)
```
**Overview** Smaller / larger of two integers (`E-TYPE` for `Float`). The result has the common type of
the two arguments, and mixed signedness compares in that common type.

**Example 1**
```basic
Dim a As Word
Dim hi As Word
a = 500
hi = Max(a, 1000)         ' 1000
```
**Example 2** Limiting a value to a range.
```basic
Dim v As Integer
v = -40
v = Max(v, -10)           ' lower limit
v = Min(v, 10)            ' upper limit
```
**Notes** Constant arguments are folded at compile time. Both arguments are evaluated more than once,
so they must not contain a function call; assign the call to a variable first.

**See also** `Abs`.

## Repeat ... Until

**Syntax**
```basic
Repeat
    ...
Until condition
```
**Overview** The body runs at least once; the loop ends when the condition is true.

**Example**
```basic
Dim x As Byte
Repeat
    Inc(x)
Until x = 3
```
**See also** `While`, `Do`.

## Save ... Restore

**Syntax**
```basic
Save(item {, item})
    ...
Restore
```
**Overview** Preserves the named variables, routines' storage (including what those routines call)
and, with `0`, the compiler's working registers around the block. Required around any call to a routine made
from an interrupt handler (otherwise `E-ISR-CALL`); a call through an event variable adds its own.

**Parameters** Each `item` is a variable, a routine, or `0`.

**Example**
```basic
Dim count As Byte
Sub Bump()
    Inc(count)
End Sub
Interrupt Tick()
    Save(0, Bump)
        Bump()
    Restore
End Interrupt
```
**Notes** `Exit`, `Break` and `Continue` inside a `Save` block restore first; `GoTo` and labels inside
it are not supported.

**See also** *Interrupts, events and context saving* (section 1).

## Select ... Case ... EndSelect

**Syntax**
```basic
Select expression
    Case 1
        ...
    Case 2, 3
        ...
    Case 10 To 20
        ...
    Case < 0
        ...
    Case Else          ' or: Else
        ...
EndSelect
```
**Overview** `Select` takes an integer expression. Case values are constants; a case can be a list, a
range (`lo To hi`) or a relation (`< v`, `> v`, ...). Overlapping cases are an error
(`E-CASE-OVERLAP`); an `Else` that can never run is the warning `W-CASE-ELSE`.

**Example**
```basic
Dim x As Byte
x = 7
Select x
    Case 1
        x = 10
    Case 2, 3
        x = 20
    Case 5 To 9
        x = 30
    Case > 100
        x = 40
    Case Else
        x = 0
EndSelect
```
**Notes** The form `Select Case x` is **not** accepted: write `Select x`. Strings and
`Float`s cannot be selected on.

## Terminate

**Syntax**
```basic
Terminate()
```
**Overview** Stops the program: it falls into the halt loop (a self-branch).

**Example**
```basic
Dim x As Byte
x = 1
Terminate()
```

## While ... Wend

**Syntax**
```basic
While condition
    ...
Wend
```
**Overview** The condition is tested first. `While True ... Wend` is the usual main loop.

**Example**
```basic
Dim led As PORTB.0
ANSELB = 0
Output(led)
While True
    Toggle(led)
    DelayMS(250)
Wend
```
**See also** `Repeat`, `Do`, `Break`.

---

# 3. Library modules

Modules are in `lib/` and loaded with `Include "name"`. Call as `Module.Routine(...)` or by the bare
routine name when unambiguous. **A routine is only known after its module is included**: without
`Include "gpio"`, `GpioAllDigital()` is `E-UNDECLARED`. Only the routines a program calls are linked.
All modules cite the PIC18F27Q10 data sheet (DS40002043F) and errata (DS80000832G) for their register
values.

Each entry below has a **Syntax**, an **Overview**, **Parameters**, what it **Returns** (functions),
and a short **Example**. The examples are fragments: they assume the program header

```basic
Program Demo
Device = 18F27Q10
Clock = 16
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, CSWEN = ON, WDTE = OFF, LVP = ON
Include "intosc"
```

followed by the `Include` named in the module heading, and then the lines shown. `Dim` lines come
first, as the language requires.

**Common rules**

* **Pins** are given by number: `RA0..RA7` = 0..7, `RB0..RB7` = 8..15, `RC0..RC7` = 16..23.
* **Return codes**: functions that can fail return a `Byte`: 1 = success, 0 = refused (bad pin, bad
  argument, conflict), unless the entry says otherwise. Bus modules also keep a status code.
* The reset state of port pins is **analog** (`ANSELx = 1`). Call `GpioAllDigital()` (after
  `Include "gpio"`) or write `ANSELx` before using pins digitally.
* **No module is reentrant.** Do not call a module routine from an interrupt handler and from the main
  program, or from two handlers, without `Save`.
* Library timing is computed from the compile-time `Clock`. If you change the oscillator at run time
  (`SetClock`) the library timing is then wrong (by design).
* **Not yet checked on hardware** for any module.

---

## gpio  (`Include "gpio"`)

Port-level helpers for ports A, B and C. Single pins need no library: `Input`, `Output`, `High`,
`Low`, `Toggle` are language commands and `Dim led As PORTB.0` names a pin.

### GpioAllDigital

**Syntax**
```basic
GpioAllDigital()
```
**Overview** Makes every pin of ports A, B and C a digital pin (`ANSELA/B/C = 0`). `ANSELx` resets to
1 (analog, input buffer off), so a pin read as digital stays 0 until this runs [DS40002043F p.247].

**Example**
```basic
Dim led As PORTB.0
GpioAllDigital()
Output(led)
High(led)
```
**Notes** Call it before `AdcPin` if the same program also uses analog inputs, then re-select those
pins with `AdcPin`.

### GpioPullUps

**Syntax**
```basic
GpioPullUps(maskA, maskB, maskC)
```
**Overview** Writes `WPUA/B/C`. A 1 bit enables the weak pull-up of that pin [p.251].

**Parameters** `maskA`, `maskB`, `maskC` are `Byte` constants or variables, bit n = pin Rx*n*.

**Example**
```basic
GpioAllDigital()
GpioPullUps(0, 0, %00000001)      ' pull-up on RC0
```
**Notes** The mask replaces the whole register: pins not set in the mask lose their pull-up.

### GpioOpenDrain

**Syntax**
```basic
GpioOpenDrain(maskA, maskB, maskC)
```
**Overview** Writes `ODCONA/B/C`. A 1 bit makes the pin drive low only (open drain) [p.256].

**Parameters** As `GpioPullUps`.

**Example**
```basic
GpioOpenDrain(0, %00000010, 0)    ' RB1 open drain
```

---

## delay  (`Include "delay"`)

`DelayMS` and `DelayUS` are language commands (section 2). The module adds:

### DelaySeconds

**Syntax**
```basic
DelaySeconds(s)
```
**Overview** Waits `s` seconds, as `s` calls of `DelayMS(1000)`.

**Parameters** `s` is a `Byte` (0..255).

**Example**
```basic
DelaySeconds(5)
```
**Notes** Interrupts lengthen the delay.

### DelayNop

**Syntax**
```basic
DelayNop()
```
**Overview** Waits exactly one instruction cycle.

**Example**
```basic
Dim p As PORTB.0
Output(p)
High(p) : DelayNop() : Low(p)
```

---

## intosc  (`Include "intosc"`, internal oscillator set-up)

`Clock` only tells the compiler what speed to expect; it does not touch the hardware. Including
`intosc` makes the hardware match it. Its start-up code (run before the main program) writes
`OSCFRQ` and `OSCCON1` and waits, each wait bounded, for `OSCCON3.ORDY` and `OSCSTAT.HFOR`. Include
it **first**: module start-up code runs in include order. For `Clock` of 1 MHz or more the divider is
never raised, so start-up writes `OSCFRQ` then `OSCCON1` without reading `OSCCON2`; below 1 MHz it
reads `OSCCON2` to pick the order.

Accepted `Clock` values (anything else is a compile error): 64, 48, 32, 16, 12, 8, 4, 2, 1 MHz, and
0.5, 0.25, 0.125, 0.0625, 0.03125 MHz (1 MHz divided by 2 to 32). `Config` needs `CSWEN = ON` unless
`Clock` already equals the `RSTOSC` speed. If a write is ignored, `SysClockOk()` is False.

```basic
Program Blink
Device = 18F27Q10
Clock = 16
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, CSWEN = ON, WDTE = OFF, LVP = ON
Include "intosc"
```

### SetClock

**Syntax**
```basic
ok = SetClock(mhz)
```
**Overview** Runs HFINTOSC at `mhz` with no divider, at run time.

**Parameters** `mhz` is a `Byte`: 1, 2, 4, 8, 12, 16, 32, 48 or 64.

**Returns** `Boolean`: True when the switch completed and read back; False (nothing written) for
another value, or when the clock did not switch.

**Example**
```basic
Dim ok As Boolean
ok = SetClock(4)
```
**Notes** `DelayMS`, `DelayUS` and the serial, I2C, SPI and PWM modules keep timing for the
compile-time `Clock`, so they are wrong until the clock is back at `Clock`.

### SetClockDiv

**Syntax**
```basic
ok = SetClockDiv(mhz, shift)
```
**Overview** As `SetClock`, with the clock divided by 2^`shift`.

**Parameters** `mhz` as `SetClock`; `shift` is 0..9 (1:1 to 1:512).

**Returns** `Boolean`, as `SetClock`.

**Example**
```basic
Dim ok As Boolean
ok = SetClockDiv(16, 2)           ' 16 MHz / 4 = 4 MHz
```

---

## system  (`Include "system"`, reset cause and clock check)

### SysResetCause

**Syntax**
```basic
cause = SysResetCause()
```
**Overview** Reports the cause of the latest Reset whose `PCON0` flags are not yet cleared.

**Returns** `Byte`: 1 power-on, 2 brown-out, 3 MCLR pin, 4 watchdog time-out, 5 watchdog window
violation, 6 `RESET` instruction, 7 stack overflow, 8 stack underflow, 0 none. Tested in the order
1, 2, 7, 8, 5, 4, 3, 6.

**Example**
```basic
Dim c As Byte
c = SysResetCause()
SysClearResetFlags()
```
**Notes** Hardware never clears the flags, so read the cause at start and then call
`SysClearResetFlags`; otherwise an old cause is reported again.

### SysResetFlags

**Syntax**
```basic
raw = SysResetFlags()
```
**Overview** Returns the raw `PCON0` value.

**Returns** `Byte`.

**Example**
```basic
Dim f As Byte
f = SysResetFlags()
```

### SysClearResetFlags

**Syntax**
```basic
SysClearResetFlags()
```
**Overview** Puts every `PCON0` flag to its inactive state so the next Reset shows only its own cause.

**Example**
```basic
SysClearResetFlags()
```

### SysClockHz

**Syntax**
```basic
hz = SysClockHz()
```
**Overview** The system clock in Hz as the oscillator is set now (from `OSCCON2` and `OSCFRQ`).

**Returns** `LongWord`; 0 when the source is not HFINTOSC (external and low-frequency sources have no
frequency the module knows). The nominal HFINTOSC frequency is used; `OSCTUNE` is not applied.

**Example**
```basic
Dim hz As LongWord
hz = SysClockHz()
```

### SysClockFrom

**Syntax**
```basic
hz = SysClockFrom(cosc, cdiv, hffrq)
```
**Overview** The same conversion from given field values.

**Parameters** `cosc` is `OSCCON2` bits 6:4 (6 = HFINTOSC); `cdiv` is `OSCCON2` bits 3:0 (divider
code 0..9); `hffrq` is `OSCFRQ` bits 3:0 (codes 0..8 = 1, 2, 4, 8, 12, 16, 32, 48, 64 MHz).

**Returns** `LongWord`; 0 for any other source or a reserved code.

**Example**
```basic
Dim hz As LongWord
hz = SysClockFrom(6, 0, 5)        ' HFINTOSC, 1:1, 16 MHz
```

### SysClockOk

**Syntax**
```basic
ok = SysClockOk()
```
**Overview** True when the oscillator runs at the frequency the program was compiled for (`Clock`).

**Returns** `Boolean`.

**Example**
```basic
If SysClockOk() = False Then
    Terminate()
EndIf
```

---

## timer  (`Include "timer"`, Timer0, Timer1, Timer2)

The module configures a timer and reads its flag. It declares no interrupt handler: to be
interrupted, call `TimerNEnableInterrupt`, write your own `Interrupt`, and call `TimerNAck` in it
(flags are not cleared by hardware). All timers count FOSC/4 unless a Timer1 source says otherwise.
`prescale` ranges are per timer. External pins (T1CKI, T1G, T2IN) must be digital inputs; the
module does not set them up.

### Timer0Start

**Syntax**
```basic
Timer0Start(prescale, period)
```
**Overview** Starts Timer0 as an 8-bit periodic timer counting 0..`period`. One overflow takes
`(period + 1) * 2^prescale` instruction cycles.

**Parameters** `prescale` 0..15 (1:1 to 1:32768); `period` 0..255.

**Example**
```basic
Timer0Start(7, 124)               ' 16 MHz: 125 * 128 cycles = 4 ms
```

### Timer0Start16

**Syntax**
```basic
Timer0Start16(prescale)
```
**Overview** Starts Timer0 as a 16-bit free-running timer, read with `Timer0Read`.

**Parameters** `prescale` 0..15.

**Example**
```basic
Timer0Start16(4)
```

### Timer0Read

**Syntax**
```basic
count = Timer0Read()
```
**Overview** Reads the 16-bit count (`TMR0L` first, which latches `TMR0H`).

**Returns** `Word`.

**Example**
```basic
Dim t As Word
Timer0Start16(4)
t = Timer0Read()
```

### Timer0Expired

**Syntax**
```basic
flag = Timer0Expired()
```
**Overview** True once per overflow; clears the flag when it reports it.

**Returns** `Boolean`.

**Example**
```basic
Dim led As PORTB.0
ANSELB = 0
Output(led)
Timer0Start(15, 244)
While True
    If Timer0Expired() Then
        Toggle(led)
    EndIf
Wend
```

### Timer0Ack

**Syntax**
```basic
Timer0Ack()
```
**Overview** Clears the Timer0 flag. Call it from your own interrupt handler, wrapped in `Save`
(a call from a handler is otherwise `E-ISR-CALL`).

**Example**
```basic
Interrupt Tick()
    Save(0, Timer0Ack)
        Timer0Ack()
    Restore
End Interrupt
Timer0Start(15, 244)
Timer0EnableInterrupt()
Enable(Tick)
```

### Timer0EnableInterrupt / Timer0DisableInterrupt

**Syntax**
```basic
Timer0EnableInterrupt()
Timer0DisableInterrupt()
```
**Overview** Set or clear `PIE0.TMR0IE`. Global interrupts are enabled separately with `Enable`.

**Example**
```basic
Timer0EnableInterrupt()
Timer0DisableInterrupt()
```

### Timer0OnExpire / Timer0Service

**Syntax**
```basic
Timer0OnExpire = Handler          ' Type TTimerEvent = Event()
Timer0Service()
```
**Overview** `Timer0OnExpire` is an event variable (type `TTimerEvent`, declared by the module).
`Timer0Service` checks the Timer0 flag; if the timer has overflowed it clears the flag and calls
the handler once. `Timer1OnExpire`/`Timer1Service` and `Timer2OnExpire`/`Timer2Service` do the same for
Timer1 and Timer2. With no handler assigned nothing is called, but the flag is still cleared.
Call the service routine from the main loop, or from your own interrupt (wrap it in
`Save(0, Timer0Service)`). The module declares no `Interrupt`, so it never claims a vector.

**Example**
```basic
Dim ticks As Byte
Event Tick()
    Inc(ticks)
End Event
Timer0OnExpire = Tick
Timer0Start(15, 255)
While ticks < 10
    Timer0Service()
Wend
```
**See also** *Events* (section 1), `Timer0Expired`, `Timer0EnableInterrupt`.

### Timer0Stop

**Syntax**
```basic
Timer0Stop()
```
**Overview** Stops Timer0.

**Example**
```basic
Timer0Stop()
```

### Timer1Start

**Syntax**
```basic
Timer1Start(prescale)
```
**Overview** Starts Timer1 as a 16-bit timer on FOSC/4, ungated. It overflows every
`65536 * 2^prescale` cycles.

**Parameters** `prescale` 0..3 (1:1 to 1:8).

**Example**
```basic
Timer1Start(3)                    ' 16 MHz / 4 / 8 = 500 kHz
While Timer1Expired() = False
Wend
```

### Timer1StartSource

**Syntax**
```basic
Timer1StartSource(clk, prescale)
```
**Overview** Timer1 from any clock source, free-running and ungated. External sources are
synchronised to the system clock (`SYNC = 0`), so pulses must be longer than a system clock cycle;
asynchronous operation is not offered.

**Parameters** `clk` is one of `T1ClkPin` (T1CKI pin, rising edges, default RC0), `T1ClkFosc4`,
`T1ClkFosc`, `T1ClkHfIntOsc`, `T1ClkLfIntOsc`, `T1ClkMfIntOsc`, `T1ClkSosc`, `T1ClkTmr0` (the PIC16F13145 family has no secondary oscillator, so no `T1ClkSosc`; it has `T1ClkMfIntOsc32` and `T1ClkExtOsc`; the PIC16F152xx has no secondary oscillator either, and has `T1ClkSfIntOsc` and `T1ClkMfIntOsc32` with the gate sources `T1GatePin`, `T1GateTmr0`, `T1GateTmr2`, `T1GateCcp1`, `T1GateCcp2`, `T1GatePwm3` and `T1GatePwm4`; the PIC16F183xx has only `T1ClkFosc4`, `T1ClkFosc`, `T1ClkPin` and `T1ClkLfIntOsc`, with the gate sources `T1GatePin`, `T1GateTmr0`, `T1GateCmp1` and `T1GateCmp2`).
`prescale` 0..3.

**Example**
```basic
Timer1StartSource(T1ClkFosc, 0)
```
**Notes** `T1ClkSosc` needs `OSCEN.SOSCEN` set and time to stabilise. In counter mode a falling edge
must be seen before the first rising edge counts, so the first pulse after a start may be missed
(data sheet 20.2.2).

### Timer1StartCounter

**Syntax**
```basic
Timer1StartCounter(prescale)
```
**Overview** Counts rising edges on the T1CKI pin; the same as `Timer1StartSource(T1ClkPin, prescale)`.

**Example**
```basic
Dim n As Word
Dim t1cki As PORTC.0
GpioAllDigital()
Input(t1cki)
Timer1StartCounter(0)
n = Timer1Read()
```

### Timer1StartGated

**Syntax**
```basic
Timer1StartGated(clk, prescale, source, activeHigh)
```
**Overview** Counts only while the gate source is at the given level. The gate is set up before the
timer is switched on, so no count is taken ungated.

**Parameters** `clk` and `prescale` as `Timer1StartSource`. `source` is `T1GatePin` (T1G, RB5),
`T1GateTmr0`, `T1GateTmr2`, `T1GateCcp1`, `T1GateCcp2`, `T1GateCmp1` or `T1GateCmp2`. `activeHigh`
is True to count while the gate is high, False while low.

**Example**
```basic
Timer1StartGated(T1ClkFosc4, 0, T1GatePin, True)
```

### Timer1StartPulse

**Syntax**
```basic
Timer1StartPulse(clk, prescale, source, activeHigh, fullCycle)
```
**Overview** Times the first pulse of the gate source after the call, then holds. Poll
`Timer1PulseDone`, then read `Timer1Read` for the length in clock counts.

**Parameters** As `Timer1StartGated`, plus `fullCycle`: True toggles the gate on every rising edge, so
the measured time is a whole period of the source instead of its high (or low) time.

**Example**
```basic
Dim w As Word
Timer1StartPulse(T1ClkFosc4, 0, T1GatePin, True, False)
While Timer1PulseDone() = False
Wend
w = Timer1Read()
```

### Timer1PulseDone

**Syntax**
```basic
flag = Timer1PulseDone()
```
**Overview** True once the pulse started by `Timer1StartPulse` has ended.

**Returns** `Boolean`.

**Example**
```basic
While Timer1PulseDone() = False
Wend
```

### Timer1GateState

**Syntax**
```basic
level = Timer1GateState()
```
**Overview** The live state of the gate (`T1GCON.GVAL`); it is not affected by the gate enable.

**Returns** `Boolean`.

**Example**
```basic
Dim g As Boolean
g = Timer1GateState()
```

### Timer1Read / Timer1Expired / Timer1Ack / Timer1Stop

**Syntax**
```basic
count = Timer1Read()
flag  = Timer1Expired()
Timer1Ack()
Timer1Stop()
```
**Overview** As the Timer0 routines, on `PIR4.TMR1IF`. `Timer1Read` returns a `Word` (with `RD16` set,
reading `TMR1L` latches `TMR1H`).

**Example**
```basic
Dim t As Word
Timer1Start(0)
t = Timer1Read()
Timer1Stop()
```

### Timer1EnableInterrupt / Timer1DisableInterrupt

**Syntax**
```basic
Timer1EnableInterrupt()
Timer1DisableInterrupt()
```
**Overview** Set or clear `PIE4.TMR1IE`.

**Example**
```basic
Timer1EnableInterrupt()
```

### Timer2Start

**Syntax**
```basic
Timer2Start(prescale, postscale, period)
```
**Overview** Starts Timer2 as a free-running 8-bit timer on FOSC/4, counting 0..`period`. The flag
is set every `(period + 1) * 2^prescale * (postscale + 1)` cycles.

**Parameters** `prescale` 0..7 (1:1 to 1:128); `postscale` 0..15 (1:1 to 1:16); `period` 0..255.

**Example**
```basic
Timer2Start(7, 0, 249)            ' 16 MHz: 250 * 128 cycles = 8 ms
```
**Notes** `T2TMR` is not cleared by a `T2CON` write. The `pwm` module owns Timer2 while a channel runs.

### Timer2StartLimit

**Syntax**
```basic
Timer2StartLimit(prescale, postscale, period, mode, source)
```
**Overview** Timer2 with a hardware-limit mode. Writing `ON` arms the timer: in the edge and level
modes it waits for the reset source; in the one-shot modes it runs once and clears `ON`.

**Parameters** `prescale`, `postscale`, `period` as `Timer2Start`. `mode` is one of `T2ModeSoftware`,
`T2ModeGateHigh`, `T2ModeGateLow`, `T2ModeResetAnyEdge`, `T2ModeResetRising`, `T2ModeResetFalling`,
`T2ModeResetLow`, `T2ModeResetHigh`, `T2ModeOneShot`, `T2ModeOneShotRising`, `T2ModeOneShotFalling`,
`T2ModeOneShotAnyEdge`, `T2ModeOneShotRisingReset`, `T2ModeOneShotFallingReset`,
`T2ModeOneShotRisingLow`, `T2ModeOneShotFallingHigh`, `T2ModeMonoRising`, `T2ModeMonoFalling`,
`T2ModeMonoAnyEdge`, `T2ModeOneShotLevelHigh`, `T2ModeOneShotLevelLow`. `source` is `T2RstPin` (T2IN,
default RC3), `T2RstTmr4`, `T2RstTmr6`, `T2RstCcp1`, `T2RstCcp2`, `T2RstPwm3`, `T2RstPwm4`,
`T2RstCmp1`, `T2RstCmp2`.

**Example**
```basic
Timer2StartLimit(7, 0, 249, T2ModeOneShot, T2RstPin)
While Timer2Running()
Wend
```
**Notes** Edge-triggered modes need six timer clocks between triggers, level modes a level of at least
three (data sheet 21.5).

### Timer2Running

**Syntax**
```basic
flag = Timer2Running()
```
**Overview** True while the timer is on (`T2CON.ON`). Use this, not the flag, to detect the end of a
one-shot: the data sheet does not say `TMR2IF` is set when `ON` clears.

**Returns** `Boolean`.

**Example**
```basic
Dim r As Boolean
r = Timer2Running()
```

### Timer2Read / Timer2Expired / Timer2Ack / Timer2Stop

**Syntax**
```basic
count = Timer2Read()
flag  = Timer2Expired()
Timer2Ack()
Timer2Stop()
```
**Overview** As the Timer0 routines, on `PIR4.TMR2IF`. `Timer2Read` returns a `Byte`. Stopping the timer
also resets its counters.

**Example**
```basic
Dim t As Byte
Timer2Start(0, 0, 255)
t = Timer2Read()
Timer2Stop()
```

### Timer2EnableInterrupt / Timer2DisableInterrupt

**Syntax**
```basic
Timer2EnableInterrupt()
Timer2DisableInterrupt()
```
**Overview** Set or clear `PIE4.TMR2IE`.

**Example**
```basic
Timer2EnableInterrupt()
```

**Hardware untested** for external clock, gate and pulse use.

---

## serial  (`Include "serial"`, EUSART1, 8N1, TX = RC6, RX = RC7)

`Clock` must be FOSC in MHz. The internal oscillator drifts with temperature and voltage, so use a
crystal for anything beyond casual use. There is no formatted `Print`: build output from the routines
below (for a signed number or a `Float`, convert in your own code).

### SerialInit

**Syntax**
```basic
SerialInit(baud)
```
**Overview** Routes EUSART1 through PPS (TX on RC6, RX on RC7), sets the pin directions and
`BRG16 = BRGH = 1`, computes the baud divisor from `Clock` (one 32-bit divide at run time, rounded to
the nearest value) and enables TX and RX.

**Parameters** `baud` is a `LongWord`, for example 9600 or 115200.

**Example**
```basic
SerialInit(115200)
```

### SerialWriteByte

**Syntax**
```basic
SerialWriteByte(b)
```
**Overview** Sends one byte, waiting until the transmit register is free.

**Example**
```basic
SerialWriteByte(65)               ' "A"
```

### SerialWrite

**Syntax**
```basic
SerialWrite(text)
```
**Overview** Sends a string or literal, up to 80 characters.

**Example**
```basic
SerialWrite("hello")
```

### SerialNewLine

**Syntax**
```basic
SerialNewLine()
```
**Overview** Sends CR + LF.

**Example**
```basic
SerialWrite("done")
SerialNewLine()
```

### SerialWriteWord

**Syntax**
```basic
SerialWriteWord(v)
```
**Overview** Sends a `Word` as unsigned decimal, without leading zeros.

**Example**
```basic
SerialWriteWord(1234)
```

### SerialWriteHex

**Syntax**
```basic
SerialWriteHex(v)
```
**Overview** Sends a `Byte` as two hexadecimal digits.

**Example**
```basic
SerialWriteHex($A5)               ' "A5"
```

### SerialAvailable

**Syntax**
```basic
flag = SerialAvailable()
```
**Overview** True when a received byte is waiting.

**Returns** `Boolean`.

**Example**
```basic
Dim b As Byte
If SerialAvailable() Then
    b = SerialRead()
EndIf
```

### SerialRead

**Syntax**
```basic
b = SerialRead()
```
**Overview** Waits for a byte and returns it. An overrun stops the receiver until `CREN` is cycled; this
routine cycles it.

**Returns** `Byte`.

**Example**
```basic
Dim b As Byte
b = SerialRead()
SerialWriteByte(b)                ' echo
```

### SerialOnRx / SerialRxService

**Syntax**
```basic
SerialOnRx = Handler              ' Type TRxEvent = Event(ByVal c As Byte)
SerialRxService()
```
**Overview** `SerialOnRx` is an event variable whose handler receives each byte. `SerialRxService`
clears an overrun (as `SerialRead` does) and, if a byte has arrived, reads it (which clears `RCIF`)
and calls the handler with it. With no handler assigned the byte is read and dropped. Call it from
the main loop, or from your own interrupt wrapped in `Save(0, SerialRxService)`.

**Example**
```basic
Dim last As Byte
Event OnByte(ByVal c As Byte)
    last = c
End Event
SerialInit(115200)
SerialOnRx = OnByte
While True
    SerialRxService()
Wend
```
**See also** *Events* (section 1), `SerialAvailable`, `SerialRead`.

### SerialFlush

**Syntax**
```basic
SerialFlush()
```
**Overview** Waits until the last byte has left the shift register (`TRMT`).

**Example**
```basic
SerialWrite("bye")
SerialFlush()
```

---

## serial2  (`Include "serial2"`, EUSART2, TX = RB6, RX = RB7)

The same nine routines with the prefix `Serial2`: `Serial2Init`, `Serial2WriteByte`, `Serial2Write`,
`Serial2NewLine`, `Serial2WriteWord`, `Serial2WriteHex`, `Serial2Available`, `Serial2Read`,
`Serial2Flush`. Syntax, parameters and returns are as in `serial`.

**Example**
```basic
Serial2Init(9600)
Serial2Write("hi")
Serial2NewLine()
```
**Notes** RB6/RB7 are the ICSP pins: disconnect the programmer while using them. Both serial modules can
be used together. **Set-up verified only**: the simulator does not set `TX2IF`, so a real transmit is
unproven.

---

## adc  (`Include "adc"`, ADCC, 10-bit, right-justified)

Software-started conversions with the clock derived from FOSC (`Clock` must be FOSC in MHz). Channel
numbers 0..23 are pins (`RA0..RA7` = 0..7, `RB0..RB7` = 8..15, `RC0..RC7` = 16..23). Internal
channels: `AdcChVss` 60, `AdcChTemp` 61, `AdcChDac` 62, `AdcChFvr` 63.

Errata handling: (1.4.4) the first conversion after a channel change is run and dropped; code that
writes `ADPCH` itself bypasses this. (1.4.1) `AdcRefFvr` needs TAD of at least 8 us, which `ADCS`
allows only up to `Clock` = 16 MHz; above that use the VDD reference.

### AdcInit

**Syntax**
```basic
AdcInit()
```
**Overview** Turns the ADC on with VDD/VSS references and the FOSC clock chosen so TAD is at least
1 us (and at most 9 us). Hardware acquisition is set to 5 us, which suits a source impedance up to
10 kohm.

**Example**
```basic
AdcInit()
```
**Notes** A higher source impedance needs a longer time: write `ADACQ` after `AdcInit`.

### AdcPin

**Syntax**
```basic
AdcPin(ch)
```
**Overview** Makes the pin of channel `ch` an analog input (`TRISx = 1`, `ANSELx = 1`).

**Parameters** `ch` 0..23. Other channel numbers are internal and need no pin.

**Example**
```basic
AdcPin(0)                         ' RA0
```

### AdcRead

**Syntax**
```basic
raw = AdcRead(ch)
```
**Overview** Converts channel `ch` once.

**Parameters** `ch` 0..63.

**Returns** `Word`, 0..1023.

**Example**
```basic
Dim v As Word
AdcInit()
AdcPin(0)
v = AdcRead(0)
```

### AdcReadAvg

**Syntax**
```basic
raw = AdcReadAvg(ch, count)
```
**Overview** Mean of `count` conversions, rounded down.

**Parameters** `ch` as `AdcRead`; `count` 1..64.

**Returns** `Word`; 0 for a `count` of 0.

**Example**
```basic
Dim v As Word
AdcInit()
AdcPin(1)
v = AdcReadAvg(1, 16)
```

### AdcMillivolts

**Syntax**
```basic
mv = AdcMillivolts(raw, vrefMv)
```
**Overview** Converts a result to millivolts: `raw * vrefMv / 1023`.

**Parameters** `raw` a `Word` from `AdcRead`; `vrefMv` the reference in millivolts.

**Returns** `Word`.

**Example**
```basic
Dim v As Word
Dim mv As Word
AdcInit()
AdcPin(0)
v = AdcRead(0)
mv = AdcMillivolts(v, 3300)
```

### AdcRefVdd

**Syntax**
```basic
AdcRefVdd()
```
**Overview** Positive reference = VDD, negative = VSS (the reset state).

**Example**
```basic
AdcRefVdd()
```

### AdcRefFvr

**Syntax**
```basic
AdcRefFvr(gain)
```
**Overview** Positive reference = the fixed voltage reference; waits for `FVRRDY`.

**Parameters** `gain` 1, 2 or 4 (1.024, 2.048 or 4.096 V; the output cannot exceed VDD). 4 or more is
taken as 4, 0 as 1.

**Example**
```basic
AdcRefFvr(2)                      ' 2.048 V
```
**Notes** Slows the conversion clock to TAD of at least 8 us (errata 1.4.1); not possible above
`Clock` = 16 MHz. The temperature indicator needs `FVRCON.TSEN`, which the module does not set.

---

## eeprom  (`Include "eeprom"`, data EEPROM, 1024 bytes)

Global interrupts are held off for the unlock sequence and their previous state is restored. Success
is judged by read-back (errata 1.6.1), not `NVMERR`. Reading stored values is **not verifiable in the
simulator** (it does not model DFM reads); test on hardware.

### EepromSize

**Syntax**
```basic
EepromSize
```
**Overview** Constant, 1024: the number of bytes.

**Example**
```basic
Dim last As Word
last = EepromSize - 1
```

### EepromRead

**Syntax**
```basic
b = EepromRead(addr)
```
**Overview** Reads one byte.

**Parameters** `addr` is a `Word`, 0..1023.

**Returns** `Byte`; 255 for an address above 1023.

**Example**
```basic
Dim b As Byte
b = EepromRead(0)
```

### EepromWrite

**Syntax**
```basic
ok = EepromWrite(addr, value)
```
**Overview** Skips the write if the byte already holds `value` (saves a cycle); otherwise erases and
programs it with the unlock sequence and waits.

**Parameters** `addr` 0..1023; `value` a `Byte`.

**Returns** `Byte`: 1 when the byte reads back as `value`, 0 for a bad address or a failed write.

**Example**
```basic
Dim ok As Byte
ok = EepromWrite(0, 42)
```

### EepromReadWord / EepromWriteWord

**Syntax**
```basic
w  = EepromReadWord(addr)
ok = EepromWriteWord(addr, value)
```
**Overview** 16-bit forms, low byte first at `addr` and `addr + 1`.

**Parameters** `addr` 0..1022; `value` a `Word`.

**Returns** `EepromReadWord` a `Word`; `EepromWriteWord` a `Byte`, 1 when both bytes were stored.

**Example**
```basic
Dim w As Word
Dim ok As Byte
ok = EepromWriteWord(10, 1234)
w = EepromReadWord(10)
```

---

## flashwrite  (`Include "flashwrite"`, program flash self-write)

Addresses are program flash **word** addresses, 0..65535 (byte address / 2). A sector is 128 words (256
bytes); there are 512 sectors. The compiler fills flash from address 0, so keep data in the last sector
(`FlashLastSector`) unless `basil --report` shows the code ends well below it: erasing a sector that holds
code destroys that code. Global interrupts are held off for each operation and restored; the CPU stalls
while a sector erases (10 ms typical) or writes, so interrupts are served late. Errata 1.9.1: the module
puts two all-zero `NOP`s straight after every self-write instruction. Errata 1.6.2: do not write flash
above 85 degrees C. Endurance is 10k erase/write cycles per sector. Reading stored values is **not
verifiable in the simulator** (it does not model flash reads); test on hardware.

### FlashReadWord

**Syntax**
```basic
w = FlashReadWord(addr)
```
**Overview** Reads one 16-bit word; needs no unlock sequence.

**Parameters** `addr` a `Word`, 0..65535.

**Returns** `Word`; 65535 when the word is erased.

### FlashEraseSector

**Syntax**
```basic
ok = FlashEraseSector(sector)
```
**Parameters** `sector` a `Word`, 0..511.

**Returns** `Byte`: 1; 0 for a sector above 511 (nothing is erased) or when `NVMERR` was set (write-protected sector).

### FlashWriteWord

**Syntax**
```basic
ok = FlashWriteWord(addr, value)
```
**Overview** Programs one word that is still erased, about 50 us. A word that was not erased fails the
read-back.

**Returns** `Byte`: 1 when the word reads back as `value`, 0 otherwise.

### FlashUpdateWord

**Syntax**
```basic
ok = FlashUpdateWord(addr, value)
```
**Overview** Replaces one word and keeps the rest of its sector, about 20 ms. Does nothing if the word
already holds `value`; uses the quick word write if it is erased; otherwise reads the sector into the
holding registers, erases it, writes the two bytes with `TBLWT` and writes the sector back. If it fails
part way the sector may be left erased.

**Returns** `Byte`: 1 when the word reads back as `value`, 0 otherwise.

### FlashSectorAddr / FlashSectorWords / FlashLastSector

`FlashSectorAddr(sector)` is the word address of the sector's first word; `FlashSectorWords` is 128 and
`FlashLastSector` is 511.

**Example**
```basic
Include "flashwrite"
Dim ok As Byte
Dim a As Word
a = FlashSectorAddr(FlashLastSector)
ok = FlashEraseSector(FlashLastSector)
ok = FlashWriteWord(a, 1234)
ok = FlashUpdateWord(a + 1, 99)
```

---

## pwm  (`Include "pwm"`, CCP1, CCP2, PWM3, PWM4 on Timer2)

Four outputs on one timebase: channel 1 = CCP1, 2 = CCP2, 3 = PWM3, 4 = PWM4. All channels share the
Timer2 period (the frequency); each has its own duty cycle. The module owns Timer2 while a channel
runs, so do not use `Timer2` routines at the same time. CCP1/CCP2 can output on ports B and C
(pins 8..23); PWM3/PWM4 on ports A and C. The duty is a number of steps out of `PwmSteps()`.

### PwmInit

**Syntax**
```basic
ok = PwmInit(hz)
```
**Overview** Chooses the Timer2 prescale (1..128) and period for `hz`. Timer2 is started by `PwmStart`.

**Parameters** `hz` is a `LongWord`, 1..1000000.

**Returns** `Byte`: 1, or 0 when no prescale reaches `hz` or a channel is running (the period is shared).

**Example**
```basic
Dim ok As Byte
ok = PwmInit(1000)
```

### PwmFrequency

**Syntax**
```basic
hz = PwmFrequency()
```
**Overview** The achieved frequency.

**Returns** `LongWord`; 0 before a successful `PwmInit`.

**Example**
```basic
Dim f As LongWord
PwmInit(1000)
f = PwmFrequency()
```

### PwmSteps

**Syntax**
```basic
n = PwmSteps()
```
**Overview** Number of duty steps in one period: `4 * (T2PR + 1)`, at most 1024. The 10-bit resolution is
reached only when `T2PR` = 255; a higher frequency gives fewer steps.

**Returns** `Word`.

**Example**
```basic
Dim n As Word
PwmInit(1000)
n = PwmSteps()
```

### PwmStart

**Syntax**
```basic
ok = PwmStart(ch, pin, duty)
```
**Overview** Starts a channel on a pin, following the data sheet set-up order (driver off, routing,
duty, Timer2 on, wait for its first overflow, then driver on) so the first period is complete.

**Parameters** `ch` 1..4; `pin` 0..23 (see the heading for valid pins); `duty` in steps, 0..`PwmSteps()`.

**Returns** `Byte`: 0 (and nothing done) without a successful `PwmInit`, for a channel or pin that cannot
be used, or for a pin another running channel uses. A running channel is restarted.

**Example**
```basic
Dim ok As Byte
PwmInit(1000)
ok = PwmStart(1, 18, 512)         ' CCP1 on RC2, half duty at 1024 steps
```

### PwmDuty

**Syntax**
```basic
PwmDuty(ch, duty)
```
**Overview** Sets the duty in steps. No effect on a stopped channel.

**Parameters** `ch` 1..4; `duty` 0..`PwmSteps()` (at most 1023 is representable).

**Example**
```basic
PwmDuty(1, 256)
```
**Notes** Duty registers are double buffered and copied at the period match; if the match falls between
the two byte writes, one period can use a mixed value.

### PwmPercent

**Syntax**
```basic
PwmPercent(ch, pct)
```
**Overview** Sets the duty as a percentage, rounded down to a step.

**Parameters** `ch` 1..4; `pct` 0..100. 100 gives the highest representable duty, which with 1024
steps is 1023/1024: the output cannot reach a true 100 %.

**Example**
```basic
PwmPercent(1, 25)
```

### PwmInvert

**Syntax**
```basic
ok = PwmInvert(ch, inverted)
```
**Overview** Sets the output polarity of PWM3 or PWM4 (`PWMxCON.POL`); on a running channel it applies at
once.

**Parameters** `ch` 3 or 4; `inverted` a `Boolean`.

**Returns** `Byte`: 0 for channels 1 and 2, which have no polarity bit.

**Example**
```basic
Dim ok As Byte
ok = PwmInvert(3, True)
```

### PwmStop

**Syntax**
```basic
PwmStop(ch)
```
**Overview** Stops a channel: the pin becomes an input again and returns to its `LATxy` bit and the module
is disabled. Timer2 is stopped when the last channel stops.

**Parameters** `ch` 1..4.

**Example**
```basic
PwmStop(1)
```

---

---

## dma  (`Include "dma"`, PIC18-Q41 DMA: copies, trigger-started feeds, abort triggers)

Four channels move bytes between SFR/GPR addresses while the program keeps running (DS40002214G chapter 16).
All channels share one register set selected by `DMASELECT`, so do not call the module from a handler and from
the main program at once. The module sets `PRLOCKED` (the arbiter grants the DMA memory access only then) and leaves the
priorities at their reset value, so the DMA uses cycles the CPU does not need. A part without DMA registers
(the PIC18F27Q10) stops with `#error`. **Not checked on hardware**: MPLAB X's simulator does not model DMA, so the tests run it with a DMA model
written from the data sheet (`scripts/dma_sim.py`): they check the registers `DmaCopy`, `DmaCopyFlash`, `DmaCopyEeprom`, `DmaOnTrigger` and `DmaAbortOn` leave behind
and that the bytes arrive, but that is the model's reading of the data sheet, not a result from a part.

### Testing DMA code in the simulator

MPLAB X's simulator (MDB) has no DMA model for the Q41 parts and keeps a single DMA register set instead of one per channel. The repository adds both in `scripts/dma_sim.py`, a
four-channel DMA engine written from the data sheet (DS40002214G chapter 16). `scripts/exec-test.py` uses it for any test program whose header has a `' dma:` line. The simulator stops
on every write to `DMASELECT` and `DMAnCON0`, the engine acts on it (starts or stops a message, moves the bytes, updates counters, pointers, `DMAnCON0` and the interrupt flags) and the
results are written back into the simulator.

| Header line | Meaning |
|---|---|
| `' dma: mailbox=SYMBOL` | A variable the program writes to raise a peripheral request or an abort. Bits 7:6 are the command (0 start requests, 1 abort after n transactions, 2 run n transactions, 3 level request), bits 5:4 the channel minus 1, bits 3:0 the count. |
| `' dma: slow` | A started message waits for the step commands instead of completing at once. |
| `' dma: sfr=U1RXB:9,8,7` | The bytes a DMA read of that SFR returns. |
| `' dma: ee=16:1,2,3,4` | Data put in the EEPROM before the run (offset, bytes). |
| `' dma-writes: U1TXB=1,2,3` | The bytes the DMA must have written to that SFR, in order. |

`' expect:` lines may name SFRs of the part as well as program variables. Examples: `tests/exec_q41/lib_dma_move.bas`, `lib_dma_trigmove.bas`, `lib_dma_srcmove.bas`, `lib_dma_abortmove.bas`.
Run them with `BASIL_MDB=1 cargo test q41`; each takes one to three minutes. `python3 scripts/test_dma_sim.py` checks the engine alone and runs with plain `cargo test`.

The same header lines carry per-part expectations for programs that run on more than one part (`exec-test.py --device PART` replaces the program's `Device` line):

| Header line | Meaning |
|---|---|
| `' expect-18F16Q41: T_P1=1292` | For that part, each name given overrides the same name in the `' expect:` lines; names not given keep their value (RAM addresses differ between families). |
| `' devices: 18F27Q10 18F16Q41` | Run the program only on the listed parts (separated by spaces or commas), for a program that tests `_device` or uses a pin the other part lacks. Skipped programs are counted, and a run in which every program is skipped fails. |

**Limits.** The engine is the data sheet as read here, not silicon. It does not model bus timing (a message completes at once), the one-cycle stop latency, `XIP` or `DMAnBUF` in flight,
the trigger sources (the test decides when a request arrives), interrupt vectors or channel priorities. The EEPROM source address is taken as a byte offset (see `DmaCopyEeprom`).
A pass in the simulator is not a hardware result.

### DmaCopy

**Syntax**
```basic
ok = DmaCopy(channel, src, dst, count)
```
**Overview** Sets `channel` up to copy `count` bytes from address `src` to address `dst`, both incrementing, and starts it.
Returns at once.

**Parameters** `channel` 1..4 (`DmaChannels`); `src`, `dst` `Word` addresses (`@x`); `count` 1..4095 (`DmaMaxBytes`).

**Returns** `Byte`: 1 when started; 0 for a channel outside 1..4, a bad count, a channel still copying or armed for a hardware trigger, or a priority lock that did not take.

**Example**
```basic
Dim a(8) As Byte
Dim b(8) As Byte
Dim ok As Byte
ok = DmaCopy(1, @a, @b, 8)
If ok = 1 Then
    While DmaDone(1) = 0
    Wend
End If
```
**Notes** Nothing checks that `count` fits the destination: too large a count overwrites the variables after it. Do not read the destination or change the source until `DmaDone`. The source and destination should not overlap.

### DmaOnTrigger

**Syntax**
```basic
ok = DmaOnTrigger(channel, trigger, src, dst, count, options)
```
**Overview** Arms `channel` so that each request from the peripheral `trigger` starts a message, and returns at once. The side that is a buffer has `count` bytes and its pointer increments; a fixed side (one register) has size 1, so each request moves one byte and the buffer pointer carries on from request to request.

**Parameters** `trigger` 1..93: the number of Table 16-6 of the data sheet, `DmaTrigU1Tx`, `DmaTrigU1Rx`, `DmaTrigU2Tx`, `DmaTrigU2Rx`, `DmaTrigSpi1Tx`, `DmaTrigSpi1Rx`, `DmaTrigI2c1Tx`, `DmaTrigI2c1Rx`, `DmaTrigAdc`, `DmaTrigTmr0`, `DmaTrigTmr1`, `DmaTrigTmr2`, `DmaTrigIoc` (a reserved number is not checked; the part must have the peripheral). `options` is the sum of `DmaFixedSrc` (the source is one register, e.g. a receive buffer), `DmaFixedDst` (the destination is one register, e.g. a transmit buffer) and `DmaOnce` (stop after `count` bytes). Other parameters as `DmaCopy`.

**Returns** `Byte`: 1 when armed; 0 for the refusals of `DmaCopy` or a trigger outside 1..93.

**Example**
```basic
Dim msg(8) As Byte
Dim ok As Byte
ok = DmaOnTrigger(1, DmaTrigU1Tx, @msg, @U1TXB, 8, DmaFixedDst + DmaOnce)
While DmaDone(1) = 0
Wend
```
**Notes** With both sides fixed `count` is ignored. Without `DmaOnce` the channel goes on round the buffer for as long as requests come. A UART, SPI or I2C request is a level: it stays up while the peripheral wants data, so use `DmaOnce` or the channel runs past the end of the buffer. The abort trigger (`DMAnAIRQ`) and the DMA interrupt flags are not used by the module (the flags are in `PIR`). The peripheral itself must be set up by the program.

### DmaAbortOn

**Syntax**
```basic
ok = DmaAbortOn(channel, trigger)
```
**Overview** Makes requests from `trigger` (the numbers of `DmaOnTrigger`) abort `channel`. The channel soft-stops: `DGO`, `SIRQEN` and `AIRQEN` are cleared and a message in progress is cut after the access under way. Call it after `DmaOnTrigger` or `DmaCopy`.

**Returns** `Byte`: 1 when set; 0 for a channel outside 1..4, a trigger outside 1..93, or a channel that is not enabled.

**Notes** The abort fires once; call `DmaAbortOn` again to re-arm it. After an abort `DmaDone` returns 1; use `DmaAborted` to tell an abort from a normal end. The channel keeps its set-up, but the module re-arms it with `DmaStop` and `DmaOnTrigger`.

### DmaAborted

**Syntax**
```basic
a = DmaAborted(channel)
```
**Overview** Returns 1 if `channel` has been aborted since the last call (its `DMAxAIF` flag was set) and clears the flag.

**Returns** `Byte`: 1 or 0; 0 for a channel outside 1..4.

### DmaCopyFlash

**Syntax**
```basic
ok = DmaCopyFlash(channel, src, dst, count)
```
**Overview** As `DmaCopy`, but `src` is a program-flash byte address (`@table` of a `Const` array gives one) and `dst` a SFR/GPR address. The flash pointer increments, as does the destination.

**Parameters** `src` `LongWord`; the others as `DmaCopy`.

**Returns** `Byte`, as `DmaCopy`.

**Example**
```basic
Const msg(5) As Byte = (1, 2, 3, 4, 5)
Dim buf(5) As Byte
ok = DmaCopyFlash(1, @msg, @buf, 5)
```
**Notes** `DmaDone` and `DmaStop` apply as for `DmaCopy`. For the data EEPROM see `DmaCopyEeprom`.

### DmaCopyEeprom

**Syntax**
```basic
ok = DmaCopyEeprom(channel, src, dst, count)
```
**Overview** As `DmaCopy`, but the source is the data EEPROM: `src` is a byte offset into it (0 is the first byte) and `dst` a SFR/GPR address.

**Returns** `Byte`, as `DmaCopy`; also 0 when `src + count` runs past the end of the EEPROM (`_EepromBytes`).

**Example**
```basic
Dim buf(16) As Byte
ok = DmaCopyEeprom(1, 0, @buf, 16)
```
**Notes** **Not confirmed for the Q41.** The data sheet (DS40002214G) gives the source-region bits (`SMR = 1x` is the EEPROM) but not the value of `DMAnSSA` that addresses it. The module uses the offset form of Microchip's example in the technical brief TB3164 (section 7.1: `DMA1SSA = 0`, `DMA1CON1 = 0x7A` with `SMR = 11`, 512 bytes of EEPROM to RAM), which covers 8-bit PIC DMA in general. The simulator does not model the engine, so only the registers are checked. If the bytes read are wrong on a real part, try the NVM address (`380000h`) in `DMAnSSA` and report it.

### DmaDone

**Syntax**
```basic
d = DmaDone(channel)
```
**Overview** Tells whether `channel` is idle (`DGO` and `SIRQEN` clear).

**Returns** `Byte`: 1 when idle or the channel is outside 1..4, 0 while a copy is in progress or the channel is armed for triggers.

### DmaStop

**Syntax**
```basic
DmaStop(channel)
```
**Overview** Clears `EN`: stops the channel and returns its registers to their reset values. A copy in progress is cut short.

---

## i2c  (`Include "i2c"`, MSSP1 host)

I2C host (master). SCL and SDA go to any pin of ports B and C (8..23); the reset selection is SCL = RC3
(19) and SDA = RC4 (20). The module is the only host on the bus (no multi-master): a collision is an
error. The bus needs external pull-ups. `Clock` must be FOSC in MHz. Every step is done by the hardware
one at a time and each wait is bounded, so a stuck bus returns an error instead of hanging.

**Status codes** (`I2cStatus`, and the return of Start, Restart, Stop and Send): 0 ok, 1 timeout (a bus
line held low or no pull-up), 2 bus collision, 3 no acknowledge, 4 module not initialised.

The module polls and clears `SSP1IF` itself; keep the MSSP1 interrupt disabled. It owns MSSP1: do not
use `spi` at the same time.

### I2cInit

**Syntax**
```basic
ok = I2cInit(hz, scl, sda)
```
**Overview** Sets up MSSP1 as an I2C host at about `hz`. The clock is `FOSC / (4 * (SSPxADD + 1))`; the
divider is rounded up so the clock is at or below `hz`. The highest clock is FOSC/16 and the lowest
FOSC/1024. Slew rate control is disabled for 100 kHz or less and for 1 MHz and above, enabled in between.

**Parameters** `hz` a `LongWord`, 1..1000000; `scl` and `sda` pin numbers 8..23, different.

**Returns** `Byte`: 1 when set up, 0 when a pin is not allowed or no divider of 3..255 reaches `hz`.

**Example**
```basic
Dim ok As Byte
ok = I2cInit(100000, 19, 20)
```

### I2cOff

**Syntax**
```basic
I2cOff(scl, sda)
```
**Overview** Disables the MSSP and gives both pins back to their `LATxy` bits.

**Parameters** The same pins given to `I2cInit`.

**Example**
```basic
I2cOff(19, 20)
```

### I2cStatus

**Syntax**
```basic
s = I2cStatus()
```
**Overview** The status of the last Start, Restart, Stop, byte or register routine.

**Returns** `Byte`, the codes above.

**Example**
```basic
Dim s As Byte
s = I2cStatus()
```

### I2cStart / I2cRestart / I2cStop

**Syntax**
```basic
s = I2cStart()
s = I2cRestart()
s = I2cStop()
```
**Overview** Generate a start, repeated-start or stop condition.

**Returns** `Byte`, the status code.

**Example**
```basic
Dim s As Byte
s = I2cStart()
s = I2cSend($A0)                  ' address 0x50 + write
s = I2cStop()
```

### I2cSend

**Syntax**
```basic
s = I2cSend(b)
```
**Overview** Sends one byte (an address with its R/W bit, or data).

**Parameters** `b` a `Byte`.

**Returns** `Byte`: 0 when the client acknowledged, 3 when it did not.

**Example**
```basic
Dim s As Byte
s = I2cStart()
s = I2cSend($A0)
s = I2cSend(0)
s = I2cStop()
```

### I2cReceive

**Syntax**
```basic
b = I2cReceive(ack)
```
**Overview** Receives a byte, then sends an acknowledge or not-acknowledge.

**Parameters** `ack` True when more bytes follow, False for the last byte.

**Returns** `Byte`. On an error it returns 0 and `I2cStatus` is not 0.

**Example**
```basic
Dim b As Byte
Dim s As Byte
s = I2cStart()
s = I2cSend($A1)                  ' address 0x50 + read
b = I2cReceive(False)
s = I2cStop()
```

### I2cPing

**Syntax**
```basic
found = I2cPing(addr)
```
**Overview** Tests whether a client acknowledges its address for writing.

**Parameters** `addr` the 7-bit address, 0..127.

**Returns** `Boolean`.

**Example**
```basic
Dim here As Boolean
here = I2cPing($50)
```

### I2cWriteReg

**Syntax**
```basic
s = I2cWriteReg(addr, reg, value)
```
**Overview** Start, address + W, `reg`, `value`, Stop.

**Parameters** `addr` 7-bit address; `reg` and `value` are `Byte`s.

**Returns** `Byte`: the first status code that was not 0 (the Stop is always attempted).

**Example**
```basic
Dim s As Byte
s = I2cWriteReg($68, $6B, 0)
```

### I2cReadReg

**Syntax**
```basic
v = I2cReadReg(addr, reg)
```
**Overview** Start, address + W, `reg`, Restart, address + R, one byte with not-acknowledge, Stop.

**Returns** `Byte`. On an error it returns 0 and `I2cStatus` is not 0.

**Example**
```basic
Dim v As Byte
v = I2cReadReg($68, $75)
```

---

## spi  (`Include "spi"`, MSSP1 host)

SPI host (master). SCK, SDO and SDI go to pins of ports B and C (8..23); SDO can be 255 for a
receive-only host. The chip select is not part of the module: drive it with a port bit. `Clock` must be
FOSC in MHz. The module owns MSSP1 (do not use `i2c` together) and does not use its interrupt.

**Modes**: 0 = idle low, data changes on the falling edge; 1 = idle low, rising; 2 = idle high,
falling; 3 = idle high, rising (CPOL/CPHA as `CKP`/`CKE`). **Status** (`SpiStatus`): 0 after the last
transfer completed, 1 after a timeout, 4 when not initialised.

### SpiInit

**Syntax**
```basic
ok = SpiInit(hz, mode, sck, sdo, sdi)
```
**Overview** Sets up MSSP1 as an SPI host. The clock is FOSC/4 for `hz` of FOSC/4 or more, otherwise
`FOSC / (4 * (SSPxADD + 1))`, rounded so the clock is at or below `hz`. The lowest is FOSC/1024.

**Parameters** `hz` a `LongWord`, 1..16000000; `mode` 0..3; `sck`, `sdo`, `sdi` pins 8..23 (`sdo` may
be 255).

**Returns** `Byte`: 1, or 0 for a bad pin, a pin used twice, a mode above 3, or a clock below FOSC/1024.

**Example**
```basic
Dim ok As Byte
ok = SpiInit(1000000, 0, 19, 20, 21)
```
**Notes** Use `SpiOff` before changing pins.

### SpiOff

**Syntax**
```basic
SpiOff(sck, sdo)
```
**Overview** Disables the MSSP and gives the pins back to their `LATxy` bits.

**Parameters** The pins given to `SpiInit`.

**Example**
```basic
SpiOff(19, 20)
```

### SpiStatus

**Syntax**
```basic
s = SpiStatus()
```
**Returns** `Byte`, the codes above.

**Example**
```basic
Dim s As Byte
s = SpiStatus()
```

### SpiTransfer

**Syntax**
```basic
r = SpiTransfer(b)
```
**Overview** Sends one byte and returns the byte received at the same time. The wait is bounded.

**Returns** `Byte`; 0 on an error (see `SpiStatus`).

**Example**
```basic
Dim r As Byte
r = SpiTransfer($9F)
```

### SpiWrite

**Syntax**
```basic
SpiWrite(b)
```
**Overview** Sends one byte and ignores the byte received.

**Example**
```basic
SpiWrite($06)
```

### SpiRead

**Syntax**
```basic
r = SpiRead()
```
**Overview** Receives one byte (sends 255 on SDO).

**Returns** `Byte`.

**Example**
```basic
Dim r As Byte
r = SpiRead()
```

---

## lcd  (`Include "lcd"`, HD44780 character LCD, 4-bit)

Six port pins are used: RS, E and DB4..DB7 (pins 0..23). R/W is not used: tie it to ground. The busy
flag is not read; every instruction is followed by a fixed wait longer than its worst case. The pins
are set by read-modify-write of `LATA/B/C`, so do not use the module from a handler and from the main
program together, and do not change those `LATx` registers elsewhere while a routine runs.

A 2-line display has line 1 at DDRAM address 00H..27H and line 2 at 40H..67H; a 1-line display uses
00H..4FH. Four-line displays are not described by the data sheet: address them with `LcdSetAddress`.

### LcdInit

**Syntax**
```basic
ok = LcdInit(rs, en, d4, d5, d6, d7, lines)
```
**Overview** Makes the six pins digital outputs, runs the 4-bit initialisation by instruction, turns the
display on with no cursor, clears it and selects increment, no shift. Takes about 55 ms.

**Parameters** `rs`, `en`, `d4`..`d7` pin numbers 0..23, all different; `lines` 1 or 2 (5 x 8 dot font).

**Returns** `Byte`: 1, or 0 when `lines` is not 1 or 2, a pin is above 23 or a pin is used twice.

**Example**
```basic
Dim ok As Byte
ok = LcdInit(16, 17, 18, 19, 20, 21, 2)   ' RS=RC0 E=RC1 D4..D7=RC2..RC5
```

### LcdCommand

**Syntax**
```basic
LcdCommand(c)
```
**Overview** Sends any instruction byte (see the data sheet's instruction table). Waits 2 ms after Clear
display and Return home, 50 us after the rest.

**Example**
```basic
LcdCommand($01)                   ' clear display
```

### LcdClear / LcdHome

**Syntax**
```basic
LcdClear()
LcdHome()
```
**Overview** `LcdClear` clears the display and puts the cursor at line 1, column 0. `LcdHome` puts the
cursor there and shifts the display back to its unshifted position.

**Example**
```basic
LcdClear()
LcdHome()
```

### LcdDisplay

**Syntax**
```basic
LcdDisplay(on, cursor, blink)
```
**Overview** Display on/off control.

**Parameters** Three `Boolean`s: display on, cursor shown, character at the cursor blinks.

**Example**
```basic
LcdDisplay(True, True, False)
```

### LcdShift

**Syntax**
```basic
LcdShift(whole, right)
```
**Overview** Shifts the whole display (`whole` True) or only the cursor, one position right (`right`
True) or left.

**Example**
```basic
LcdShift(True, False)             ' whole display one place left
```

### LcdGoto

**Syntax**
```basic
LcdGoto(col, row)
```
**Overview** Moves the cursor.

**Parameters** `col` 0..39 (0..79 on a one-line display); `row` 0 or 1. A position the display does not
have is ignored.

**Example**
```basic
LcdGoto(0, 1)                     ' start of line 2
```

### LcdSetAddress

**Syntax**
```basic
LcdSetAddress(addr)
```
**Overview** Sets the raw DDRAM address; the next character is written there.

**Parameters** `addr` 0..127.

**Example**
```basic
LcdSetAddress($14)                ' line 3 of a common four-line display
```

### LcdWriteChar

**Syntax**
```basic
LcdWriteChar(ch)
```
**Overview** Writes one character code at the cursor. Codes 32..126 are ASCII (A00 character ROM);
0..7 are the user characters of `LcdCustomRow`.

**Example**
```basic
LcdWriteChar(65)                  ' "A"
```

### LcdWrite

**Syntax**
```basic
LcdWrite(text)
```
**Overview** Writes a string or literal (up to 80 characters) at the cursor.

**Example**
```basic
LcdWrite("Hello")
```

### LcdWriteWord

**Syntax**
```basic
LcdWriteWord(v)
```
**Overview** Writes a `Word` as unsigned decimal, without leading zeros.

**Example**
```basic
LcdWriteWord(2048)
```

### LcdWriteHex

**Syntax**
```basic
LcdWriteHex(v)
```
**Overview** Writes a `Byte` as two hexadecimal digits.

**Example**
```basic
LcdWriteHex($3C)
```

### LcdCustomRow

**Syntax**
```basic
LcdCustomRow(slot, row, bits)
```
**Overview** Sets one dot row of a user-defined character.

**Parameters** `slot` 0..7 (shown as character code 0..7); `row` 0..7; `bits` uses the low five bits
(bit 4 = leftmost dot). Keep row 7 at 0 if the cursor is used.

**Example**
```basic
LcdCustomRow(0, 0, %00001110)
LcdCustomRow(0, 1, %00010001)
LcdGoto(0, 0)                     ' leave CGRAM before writing text
LcdWriteChar(0)
```
**Notes** The write leaves the address counter in CGRAM: call `LcdGoto`, `LcdClear` or `LcdHome` before
writing text.

---

## oled  (`Include "oled"`, SSD1309, 128 x 64, I2C or 4-wire SPI)

Set up the bus first: `I2cInit` at no more than 400 kHz, or `SpiInit` in mode 0 at no more than 10 MHz.
The module owns no pins except D/C#, CS# and RES# (pins 0..23; 255 for CS# or RES# means not
controlled). The panel supply (about 12 V) is external: switch it on after RES#. The serial interfaces
are write-only, so text and `OledBitmap` write pages of 8 pixel rows straight to the display, one byte
per column, bit 0 on top (`OledGoto`, `OledData`); pixel drawing uses a 1024-byte frame buffer in RAM
(see "Pixel drawing" below), which is linked only by a program that calls one of those commands. Text uses a 5 x 7 font in 6 x 8 cells (21 characters on
each of 8 lines) for ASCII 32..126. If a module shows every
other line or an upside-down picture, use `OledFlip`.

### OledInitI2c

**Syntax**
```basic
ok = OledInitI2c(addr, res)
```
**Overview** Starts the display on I2C, runs the start-up command sequence, clears the RAM and switches
the display on.

**Parameters** `addr` the 7-bit address, 60 or 61 (0x3C/0x3D); `res` the RES# pin, or 255.

**Returns** `Byte`: 1 when every byte was acknowledged, else 0 (`OledStatus` gives the I2C code).

**Example**
```basic
Dim ok As Byte
ok = I2cInit(400000, 19, 20)
ok = OledInitI2c(60, 255)
```

### OledInitSpi

**Syntax**
```basic
ok = OledInitSpi(dc, cs, res)
```
**Overview** Starts the display on 4-wire SPI.

**Parameters** `dc` the D/C# pin; `cs` the CS# pin or 255; `res` the RES# pin or 255.

**Returns** `Byte`: 1, or 0 for a pin above 23 or a pin used twice.

**Example**
```basic
Dim ok As Byte
ok = SpiInit(4000000, 0, 19, 20, 255)
ok = OledInitSpi(16, 17, 18)
```

### OledStatus / OledClearStatus

**Syntax**
```basic
s = OledStatus()
OledClearStatus()
```
**Overview** `OledStatus` is 0 when all I2C bytes since the init (or the last `OledClearStatus`) were
acknowledged, else the first I2C status code (3 = no acknowledge). Always 0 for SPI.

**Returns** `Byte`.

**Example**
```basic
Dim s As Byte
s = OledStatus()
OledClearStatus()
```

### OledOn

**Syntax**
```basic
OledOn(isOn)
```
**Overview** Display on, or off (sleep). The RAM keeps its content.

**Example**
```basic
OledOn(False)
```

### OledContrast

**Syntax**
```basic
OledContrast(level)
```
**Overview** Sets the contrast; reset value is 127.

**Parameters** `level` 0..255.

**Example**
```basic
OledContrast(200)
```

### OledInvert

**Syntax**
```basic
OledInvert(inverse)
```
**Overview** Inverse display (True) or normal (False).

**Example**
```basic
OledInvert(True)
```

### OledAllOn

**Syntax**
```basic
OledAllOn(allOn)
```
**Overview** Every pixel on regardless of the RAM (True), or the RAM content (False).

**Example**
```basic
OledAllOn(True)
```

### OledFlip

**Syntax**
```basic
OledFlip(rotated)
```
**Overview** Turns the picture through 180 degrees (True) or normal (False). Takes effect for data
written afterwards; the RAM is not rewritten.

**Example**
```basic
OledFlip(True)
OledClear()
```

### OledGoto

**Syntax**
```basic
OledGoto(col, page)
```
**Overview** The next data byte goes to column `col` of page `page`. After each byte the column advances
and wraps to the next page at the end of the line.

**Parameters** `col` 0..127; `page` 0..7.

**Example**
```basic
OledGoto(0, 0)
```

### OledTextGoto

**Syntax**
```basic
OledTextGoto(x, line)
```
**Overview** The next character goes to cell `x` of text line `line`.

**Parameters** `x` 0..20; `line` 0..7. An `x` above 20 is ignored.

**Example**
```basic
OledTextGoto(0, 3)
```

### OledData

**Syntax**
```basic
OledData(b)
```
**Overview** Writes one column byte (bit 0 on top) at the current position.

**Example**
```basic
OledGoto(10, 2)
OledData(%11111111)               ' a vertical bar 8 pixels high
```

### OledFill / OledClear

**Syntax**
```basic
OledFill(pattern)
OledClear()
```
**Overview** `OledFill` writes `pattern` to the whole RAM and returns to column 0, page 0. `OledClear`
is `OledFill(0)`.

**Example**
```basic
OledFill($AA)                     ' stripes
OledClear()
```

### OledWriteChar

**Syntax**
```basic
OledWriteChar(ch)
```
**Overview** One character at the current position: five font columns and one blank. Codes outside
32..126 show `?`.

**Example**
```basic
OledTextGoto(0, 0)
OledWriteChar(65)
```

### OledWrite

**Syntax**
```basic
OledWrite(text)
```
**Overview** Writes a string or literal (up to 80 characters).

**Example**
```basic
OledTextGoto(0, 0)
OledWrite("Hello")
```

### OledWriteWord / OledWriteHex

**Syntax**
```basic
OledWriteWord(v)
OledWriteHex(v)
```
**Overview** A `Word` as unsigned decimal without leading zeros; a `Byte` as two hex digits.

**Example**
```basic
OledTextGoto(0, 1)
OledWriteWord(1234)
OledWriteHex($FF)
```

### OledBitmap

**Syntax**
```basic
OledBitmap(x, page, w, img)
```
**Overview** Draws `w` columns of the `Const` byte array `img` straight to the display, starting at column `x` of `page` (no frame buffer). One byte per column, bit 0 on top, so the image is 8 pixel rows high; draw a taller image one strip at a time. Columns past 127 are dropped.

**Parameters** `x` 0..127, `page` 0..7, `w` columns, `img` a `Const` `Byte` array.

**Example**
```basic
Const Logo(8) As Byte = (60, 66, 165, 129, 165, 153, 66, 60)
OledBitmap(0, 0, 8, Logo)
```

---

### Pixel drawing

The commands below draw into a 1024-byte frame buffer (the layout of the display RAM: byte `x + 128 * page`, bit 0 on top); `OledUpdate` sends it to the display. `x` is 0..127 from the left, `y` 0..63 from the top; points outside the screen are ignored. `OledClear` and `OledFill` clear the display, not the buffer.

### OledPixel / OledPoint

**Syntax**
```basic
OledPixel(x, y, on)
b = OledPoint(x, y)
```
**Overview** Sets (`on` = True) or clears one pixel / reads it back (1 or 0; 0 outside the screen).

---

### OledBufFill / OledBufClear / OledUpdate

**Syntax**
```basic
OledBufFill(pattern)
OledBufClear()
OledUpdate()
```
**Overview** Fills the buffer with a byte (0 = all pixels off, 255 = all on) / clears it / sends the whole buffer to the display in one transfer.

---

### OledLine

**Syntax**
```basic
OledLine(x0, y0, x1, y1, on)
```
**Overview** Line between two points, both ends included (Bresenham). The coordinates are `Integer`, so a line may start or end off screen; the visible part is drawn.

---

### OledRect / OledFillRect

**Syntax**
```basic
OledRect(x, y, w, h, on)
OledFillRect(x, y, w, h, on)
```
**Overview** Rectangle outline / filled rectangle with its top left corner at (`x`, `y`), `w` wide and `h` high. Keep `x + w` and `y + h` within 255 (the sums wrap).

---

### OledBufBitmap

**Syntax**
```basic
OledBufBitmap(x, y, w, pages, opaque, img)
```
**Overview** Draws a `Const` image into the buffer at any pixel position: `w` columns and `pages` rows of 8 pixels, `img` holding `w * pages` bytes (the first row of columns first, bit 0 on top). Set pixels of the image are set in the buffer; clear ones are left alone, or cleared when `opaque` is True.

**Example**
```basic
OledBufClear()
OledBufBitmap(20, 13, 8, 1, False, Logo)
OledUpdate()
```

---

### OledBufChar / OledBufText

**Syntax**
```basic
OledBufChar(x, y, ch, on)
OledBufText(x, y, on, s)
```
**Overview** 5 x 7 text with its top left pixel at (`x`, `y`) (6 pixels per character), at any pixel position. Only the set pixels of the font are drawn, so text can be laid over a picture.

**Example**
```basic
OledBufText(10, 50, True, "Hello")
OledUpdate()
```

---

### FontByte

**Syntax**
```basic
b = FontByte(idx)
```
**Overview** Byte `idx` of the font table (a `Const` array in program memory): 5 column bytes for each code 32..126, bit 0 on top.

**Parameters** `idx` a `Word`, 0..474.

**Returns** `Byte`.

**Example**
```basic
Dim b As Byte
b = FontByte(0)
```

---

## strings  (`Include "strings"`)

`Len(s)` returns a `Byte`: the number of characters before the `Null` (0 for `Null` or an empty string, at most 255).
`s` can be a `String` of any size or a literal.

```basic
Include "strings"
Dim name As String(20) = "basil"
n = Len(name)        ' 5
n = Len("abc")       ' 3
```

---

## aht30  (`Include "aht30"`, AHT30 temperature and humidity sensor, I2C)

Set up the bus first: `I2cInit` at no more than 400 kHz, with pull-ups of 2.0 to 4.7 kOhm. The sensor is at
7-bit address 0x38. A reading is two steps: `Aht30Start` triggers a measurement, and `Aht30Fetch` reads it
at least 80 ms later; `Aht30Measure` does both and waits. Sample at most once a second, or the sensor's
self-heating passes 0.1 C. The temperature comes back as an `Integer` in 1/100 degree C (2512 = 25.12 C)
and the humidity as a `Word` in 1/100 %RH (4560 = 45.60 %RH); they are written only when the status is 0.

**Status codes** 0 ok; 1 timeout; 2 bus collision; 3 no acknowledge; 4 `I2c` not initialised; 5 busy
(`Aht30Fetch` was called before the measurement finished); 6 CRC mismatch.

**Example**
```basic
Dim t As Integer
Dim rh As Word
Dim st As Byte
st = I2cInit(100000, 19, 20)
Aht30Init()
st = Aht30Measure(t, rh)
If st = 0 Then
    ' t = 2512 and rh = 4560 mean 25.12 C and 45.60 %RH
End If
```

## rtcc and rtccspi  (`Include "rtcc"`, `Include "rtccspi"`, Microchip real-time clock/calendar chips)

`rtcc` drives the I2C parts MCP7940M, MCP7940N, MCP79400/1/2 and MCP79410/1/2 over the `I2c` module (set it up
first); `rtccspi` drives the SPI parts MCP7951x/7952x and MCP795W1x/2x over the `Spi` module (mode 0; the parts
run at 1.8 to 3.6 V) and takes the chip select pin in `RtccspiInit`. Times are plain numbers (year 0..99 for
2000..2099, hours 0..23). Set the clock once with `RtccSet`, then `RtccRead` takes a snapshot that the accessors
(`RtccHour()`, `RtccMinute()` ...) decode. `RtccSet` blocks until the crystal runs (up to 2 s). Every routine
returns a status: 0 ok, 1..4 as the bus module, 5 argument out of range, 6 a wait ran out. See `docs/LIBRARY.md`
for the routines, the parts each block exists on and the errata the code handles.

```basic
Dim st As Byte
st = I2cInit(100000, 19, 20)
st = RtccSet(26, 3, 14, 6, 9, 30, 0)     ' 2026-03-14, weekday 6, 09:30:00
st = RtccAlarm(0, 1, 1, 1, 1, 0, 31, 0)  ' alarm 0 when minutes = 31
st = RtccAlarmEnable(0, True)
st = RtccRead()
If st = 0 Then
    ' RtccHour(), RtccMinute(), RtccSecond() ...
End If
```

## pulse, irremote and x10  (`Include "pulse"`, `Include "irremote"`, `Include "x10"`)

Bit-banged commands on any pin, called as `Pulse.PulseIn(pin, True)` and so on. Pins are numbers 0..23 (`RA0` = 0, `RB0` = 8, `RC0` = 16); a pin the part lacks
makes a routine do nothing (a measurement returns 0). Timing is by polling and cycle-counted delays, so it follows `Clock`: a "unit" of `PulseIn`, `PulseOut`
and `RCin` is a 10 us poll plus loop time (10 to 14 us at 16 MHz and above), and interrupts lengthen every time. Calibrate against a known pulse where the number matters.

| Routine | Effect |
|---|---|
| `PulseOut(pin, period, level)`, `PulseOut(pin, period)` | pulse of `period` units, high or low (two-argument form: opposite of the present level); pin becomes an output |
| `w = PulseIn(pin, level)` | `Word` width in units of the next pulse at `level`; 0 after about 0.65 s |
| `w = RCin(pin, level)` | `Word` units the pin stays at `level` (1 if not at `level` at the call, 0 after 65535) |
| `b = Pot(pin, scale)` | `Byte`: 1 ms discharge, `RCin` of the rise, `units * scale / 256`, at most 255 |
| `Servo(pin, width)` | one pulse of `width` us, 500..2500; repeat every 20 ms |
| `PwmPin(pin, duty, cycles)` | software PWM for an R-C filter: 256 steps of 10 us per cycle, high for `duty` steps |
| `Sound(pin, note, duration)` | note 0 silence, 1..127 tone (about 78.74 x note Hz), 128..255 noise; `duration` in 10 ms |
| `Sound2(pin1, pin2, f1, f2, ms)` | two tones at once, exact to about 10 % |
| `w = SonyIn(pin)`, `w = RC5In(pin)` | Sony SIRC 12-bit / Philips RC5 frame from an active-low receiver module: command in the low byte, system in the high byte, 65535 for no valid frame in 0.65 s. `RC5In` needs a clock of 16 MHz or more |
| `ok = Xout(dataPin, zeroPin, house, key, reps)` | X-10 code through a PL513 / TW523: house 0..15, key 0..15 unit or 16 + function (`X10.UnitOn` ...); returns False when the zero-cross pulses fail |
| `ok = Xin(dataPin, zeroPin, timeout, value)` | receives one X-10 code (house in the high byte of `value`, key in the low); `timeout` in half-cycles, 0 = wait |

**Notes** Never connect a pin to the AC line; use the X-10 interface module. The X-10 line codes follow the protocol as cross-checked against the Positron key-code table, not
measured on a real interface. Tests: `tests/exec/lib_pulse.bas`, and `tests/exec_pins/lib_pins_model.bas` against a pin model. See `docs/LIBRARY.md`.

## floatlib  (automatic)

Not included by hand. Routines `FAdd FSub FMul FDiv`, `FEq FNe FLt FLe FGt FGe`, `FFromLong FFromULong
FToLong` operate on `LongWord` bit patterns. You do not call them; the compiler does when a program
uses `Float`.

---

# 4. Diagnostics

Every message has a code, `error[E-TYPE]` or `warning[W-NARROW]`. Full list with meanings:
`docs/DIAGNOSTICS.md`. The ones met most often:

| Code | Cause |
|---|---|
| `E-NODEVICE`, `E-DEVICE` | no `Device`, or no description for it |
| `E-SYNTAX` | the text does not match the grammar (for example a single-line `If`, `High 1`, `Select Case`) |
| `E-ORDER` | a `Dim`, `Include` or routine after the first statement |
| `E-UNDECLARED` | misspelled name, or a module not `Include`d |
| `E-CONFIG` | unknown `Config` name or value |
| `E-TYPE`, `E-SIGN`, `E-MIX`, `E-NARROW` / `W-NARROW` | type rules |
| `E-COND` | condition is not Boolean (a bare bit alias) |
| `E-CONST-RANGE`, `E-BOUNDS` | constant does not fit; constant index out of range |
| `E-RAM`, `E-STACK` | variables exceed RAM; hardware stack deeper than the device has (31 / 127) |
| `E-RECURSION` | call cycle |
| `E-FORWARD` | a `Declare` with no definition, or a definition that does not match its `Declare` |
| `E-ISR-CALL` | call from a handler without `Save ... Restore` (also float maths) |
| `E-BACKEND` | valid per the front end but not generated yet (see below) |
| `E-EXTERN` | bad `Extern` or `Export` declaration (parameter or result type, `Reentrant`), two `Extern`s of one C name with different types, |
| `E-EXPORT` | a name given to `Export` twice, or to `Export` and `Extern` |
| `E-UNSUPPORTED` | reserved but not available (`BitOf`, `Declare` other than `Xtal`, ...) |
| `W-CLOCK` | `Clock` differs from the `RSTOSC` speed and nothing sets the oscillator |
| `W-REGNAME` | a declaration hides a register name |

`E-BACKEND` ("not supported by the back end yet") means the front end accepted a rare form that the
code generator does not handle: a bit passed `ByRef`, a call inside the index
of a bit, a String or structure function result in an `ElseIf` or `Until` condition, and similar. The compiler
reports these rather than miscompiling them.

---

# Appendix A: Alternative spellings and unsupported forms

## Accepted alternative spellings

`Declare Xtal = n`; `Symbol`; `Proc`/`EndProc`/`ExitProc`; `Do`/`Loop` forms; type names `SByte`, `SWord`,
`Dword`, `Long` (and conversions); `$FF`/`0xFF`, `%1010`/`0b1010`; `:` between statements; `'` and `(* *)` comments;
` _` continuation; `Dim x As Type`; `Toggle`, `Inc`, `Dec`, `DelayMS`, `DelayUS`, `High`, `Low`,
`Input`, `Output` **with parentheses**; `Abs`; `Bound`.

## Not available (or different)

| Feature of other BASIC compilers | basil 0.1.37 |
|---|---|
| Other devices | only PIC18F27Q10 and the PIC18F04/05/06/14/15/16Q41 parts compile (see *Supported device*) |
| Statements without parentheses (`High LED`, `DelayMs 500`, `HRsout "x"`) | parentheses required |
| `Declare` switches (LCD pins, baud, pin routing) | only `Declare Xtal`; peripherals take arguments in `...Init(...)` calls |
| `PinHigh`, `PinLow`, `PinGet`, pin numbers in `High` | use register bits / aliases; `PinMode`, `PinSet`, `PinClear` and `PinPullup` are available (see *PinMode*, *PinSet / PinClear*, *PinPullup*) |
| `Pin` type, `SDword`, `Double`, 24-bit `Long`, `Global`/`Shared` variables | not accepted (`Static` and `Volatile` are supported, see *Variables and types*) |
| `Print`, `Cls`, `Cursor`, `Plot`, `Line`, graphic LCD commands | `lcd` module routines; no graphics |
| `HRsout`, `HRsin`, `HSerout`, `Rsout`, `Serin`, `Serout` | `serial` / `serial2` routines |
| `Dec`, `Hex`, `Bin`, `Str$`, `Val` formatting modifiers | `SerialWriteWord`, `SerialWriteHex` only |
| `ADin` | `adc` module |
| `Pot`, `RCin`, `PulseIn`, `PulseOut`, `Servo`, `PWM` (software), `Sound`, `Sound2` | `pulse` module (see *pulse, irremote and x10*) |
| `SonyIn`, `RC5in`, `Xin`, `Xout` | `irremote` and `x10` modules |
| `HPWM`, `Freqout` | `pwm` module (hardware PWM; no `Freqout`) |
| `Busin/Busout`, `I2Cin/I2Cout`, `Hbusin`, `Shin/Shout`, `Owrite/Oread`, `USBin`, `USBout`, `USBinit`, `USBpoll` | `i2c`, `spi` modules; `Shin`/`Shout` are `ShiftIn`/`ShiftOut` of the `shift` module; no 1-wire; no USB (no supported device has a USB peripheral) |
| `Read`/`Write` EEPROM, `Edata`, `Cdata`, `LookUp`, `LookDown` | `eeprom` module; `Const` arrays |
| `Branch`, `On GoTo`, `On GoSub`, `GoSub`, `Return`, `Call` | not available; use `Select` and routines |
| `Select Case x` | `Select x` |
| `Break`, `Continue`, `While/Wend`, `Repeat/Until`, `For/Next` | supported |
| `Sin`, `Cos`, `Sqr`, `Log`, `Exp`, `Pow`, `ISqr`, `Div32`, `Dcd`, `Ncd`, `@`, `?` | not available; `Abs`, `Min`, `Max` and arithmetic only |
| `Len`, `Left$`, `Mid$`, `Right$` | not available; string arrays are `Dim s(3) As String(8)` |
| `Tern`, `SizeOf` | not available |
| `$config`, `Config` directive | `Config NAME = VALUE` with pack names |
| `$include`, `$asm`, `Asm` | `Include "name"`, `Asm ... End Asm` (pic-as syntax) |
| Interrupt via `On_Hardware_Interrupt` | `Interrupt Name() ... End Interrupt` plus `Enable` |
| `0x` and `0b` literals | accepted, as are `$` and `%` |
| Overloading, `Reentrant` routines | supported (see *Routines*) |

---

# Appendix B: Test checklist

Work down this list. Each item names what to observe.

**Build and size**
1. `basil --version` prints `0.1.37`. `basil --check` on a program with a deliberate error prints a
   code, line, column and caret.
2. Compile `my_src/first_test/main.bas`; confirm `.hex`, `.S`, `.map` appear and the size line prints.
3. Compile the same program with `-O0`; it should behave the same and be larger.

**Language (all verifiable on the bench with one LED and a scope or serial port)**
4. Blink with `DelayMS(500)` at your `Clock`: measure the period (should be 1.000 s). Repeat at 64, 32, 16, 8, 4, 1 MHz.
5. `DelayUS` with a pin toggle: measure 10, 100, 1000 us.
6. Integer arithmetic at each width: results printed over serial for `+ - * / Mod << >>` against known values.
7. `Select` with list, range and relational cases; `For` with negative `Step`; `Break`/`Continue`.
8. Arrays: initialiser, `Bound`, `Const` array read, copy; string append and compare.
9. Structure and union field access; `ByRef` parameter modifying the caller's variable.
10. Float: `+ - * /`, comparison, conversion to integer, print the integer part.
11. Interrupt: Timer0 interrupt toggling a pin; then a second priority; a call from the handler wrapped in `Save`.

**Library (hardware only; the simulator cannot show these)**
12. `serial`: 9600 and 115200 baud at 16 MHz and 64 MHz; check the characters and the error at each.
    Echo using `SerialAvailable`/`SerialRead`.
13. `serial2` on RB6/RB7 with the programmer disconnected.
14. `adc`: a potentiometer on RA0, readings 0..1023; the internal FVR channel; `AdcRefFvr(1)` scale.
15. `pwm`: frequency and duty on a scope on CCP1/CCP2/PWM3/PWM4 pins; `PwmInvert`; 100 % corner case.
16. `i2c`: `I2cPing` against a known device; read a register; remove the pull-up and confirm status 1.
17. `spi`: loop MOSI to MISO and confirm `SpiTransfer` returns what was sent, in all four modes.
18. `eeprom`: write, power-cycle, read back; byte and word forms; an out-of-range address.
    `flashwrite`: erase the last sector, write and update words, power-cycle, read back; confirm the program still runs after a write (errata 1.9.1).
19. `timer`: Timer0/1/2 flag periods; Timer1 as an external counter on RC0; gate and pulse measurement.
20. `lcd` and `oled`: text, cursor, custom character, contrast, invert, flip.
    `dma` (Q41): `DmaCopy` between two arrays on each of the four channels, `DmaDone` going to 1 when the bytes have arrived; a refused copy on a busy channel; `PRLOCKED` set afterwards.
    `DmaCopyFlash` from a `Const` table; `DmaCopyEeprom` of bytes written with `EepromWrite` (the first check of the offset convention); `DmaOnTrigger` feeding the UART1 transmit buffer (`DmaTrigU1Tx`, `DmaFixedDst + DmaOnce`) and filling a buffer from the receive buffer (`DmaFixedSrc + DmaOnce`), `DmaDone` going to 1 at the end; `DmaAbortOn` with a second trigger stopping a feed part-way, `DmaAborted` returning 1 once. Data movement has not been seen on any part.
21. `intosc`/`system`: `Clock` at several values; `SysClockHz()` and `SysClockOk()` agree with a scope;
    `SysResetCause()` after power-on, MCLR and a watchdog reset.

Record anything that disagrees with this manual as a bug against the entry it came from.
