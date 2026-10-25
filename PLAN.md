# Basic_Compiler — Project Plan

Status: DRAFT for approval · Drafted 2026-10-23 · Owner: Gary
Location: `/home/gary/apps/Basic_Compiler/`

A personal BASIC compiler for PIC microcontrollers. It combines a **structured core language** with a **friendly command library**, and uses
Microchip's **pic-as** assembler/linker as its back end.

**First target: PIC18F27Q10. Other microcontrollers will be added slowly, one at a time,
after the first target is solid.** The whole design (§3, §7, §9) is built so that adding a
device is a data-and-validation task, not a compiler rewrite.

---

## 0. How to read this plan

* Facts about the 18F27Q10 are marked with a source, e.g. `[DS40002043F p.108]`
  (datasheet) or `[DS80000832G p.2]` (errata). Page numbers are PDF pages.
* Facts about pic-as are marked `[XC8 PIC Assembler UG DS50002974E]` or `[observed]` when
  I ran the tool myself on this machine.
* Anything marked **TO VERIFY (Mx)** has not been confirmed yet and must be checked against the
  named document in the named milestone **before** code depends on it.
* Decisions still open are collected in §14.

---

## 1. Goals and non-goals

### Goals
1. Compile BASIC source for the **PIC18F27Q10** to a flashable `.hex`, via pic-as.
2. A language that is pleasant to write (short, friendly commands) but well-structured
   (modules, typed subroutines/functions, structures, interrupts).
3. Every device fact comes from Microchip documents/packs, never from memory and never from
   a third-party vendor's data files.
4. **Code efficiency is a top priority**: small *and* fast generated code, measured against
   XC8 on a fixed benchmark set (§7A), while staying correct. Efficiency shapes the language
   rules (§7A.2), the IR (exact bit-widths), the optimiser and the library design — it is not
   a late polishing step.
   **Every byte saved matters**: these parts have small flash and RAM, and small savings add up
   across a program, so a one-word or one-cycle gain is worth taking whenever it is safe. Compile-time checks (stack depth, RAM overflow, bank usage) also catch
   mistakes before the chip does.
5. A device-description mechanism so that **additional micros are added slowly over time**
   (§9) without redesigning anything.

### Non-goals (for now)
* Not a drop-in clone of any other BASIC compiler. Source compatibility is "close where
  cheap", not a promise.
* No IDE, no debugger, no programmer in the first phases (editor integration comes via
  Zed tasks, as already done for the other compilers).
* No devices other than the 18F27Q10 until §10 milestone M9 is accepted.
* No redistribution. Personal use only.

---

## 2. Clean-room and hygiene rules

Reference manuals of other compilers are owned by their vendors and kept in the `reference/`
folder for personal reference.

* Work from the manuals' *descriptions of behaviour*. Do not disassemble any vendor
  executable. Do not copy vendor include files, library source, `.def` files, generated
  macro code, or manual text into this project.
* Device data comes from **Microchip's own packs** (`~/.mchp_packs`) and datasheets.
* Where a manual is silent or ambiguous, define the behaviour ourselves and write it down in
  `docs/LANGUAGE.md`.
* Repository hygiene: commits, files, comments and docs carry only the owner's authorship; no tool-generated attribution lines or trailers.
* Check the licence terms of any reference compiler before work that could be read as
  building a competing product; this plan does not rely on any such licence.

---

## 3. Architecture overview

```
 source.bas ──► lexer ──► parser ──► AST ──► semantic analysis ──► IR (typed, device-agnostic)
                                                                   │
                                         device description ──────►│  (§9, from Microchip DFP)
                                                                   ▼
                                           optimiser (IR level) ──► code generator (PIC18)
                                                                   │
                                                                   ▼
                                              prog.S (pic-as assembly, with CONFIG + psects)
                                                                   │
                                                                   ▼
                                  pic-as -mcpu=18F27Q10 -mdfp=… ──► prog.hex / prog.map
```

Layers and what must stay device-independent:

| Layer | Device-aware? | Notes |
|---|---|---|
| Lexer, parser, AST | No | Language only. |
| Semantic analysis | Via device description | Type checking, scoping, constant folding; checks `Device`-dependent facts (RAM size, pin names) through the device description. |
| IR | No | Typed three-address form; 8/16/24/32-bit integers, floats, bits, pointers. |
| Code generator | Per **core family** | PIC18 first. Other families later get their own generator module. |
| Device description | Data | Generated from the DFP (§9). One file per device. |
| Standard library | Per peripheral | Written in the language itself (§6), conditionally compiled by device features. |
| Assembler/linker | pic-as | External tool, invoked by the driver. |

**Implementation language** — recommendation: **Rust** (see decision D1, §14). Reason: the
project owner's other compiler front-end is Rust, and Rust suits a compiler (enums for AST/IR,
exhaustive matches). Alternatives are fine if preferred.

---

## 4. The language

Principle: **a small, strict core language** plus **a rich standard
library written in that language** (friendly commands). The compiler implements the
core; commands like `HRSOut`, `Toggle`, `DelayMS` are library code, so adding commands never
means touching the compiler.

### 4.1 Core language

Features to support, in implementation order. "SF §" refers to the section numbers of the reference language manual kept in `reference/`.

| # | Feature | Notes |
|---|---|---|
| 1 | Identifiers, comments, constants | SF "Identifiers and Reserved Words", "Comments", "Constants" |
| 2 | Core types | `Bit/Boolean, Byte, ShortInt, Word, Integer, LongWord, LongInt, Float, Char, String` (SF "Variables", Appendix 3). Exact widths defined in `docs/LANGUAGE.md`. |
| 3 | Variables, arrays, array constants | |
| 4 | Operators, precedence | SF Appendix 1; our precedence table is written down explicitly. |
| 5 | `If/ElseIf/Else`, `Select Case` | |
| 6 | `While/Wend`, `Repeat/Until`, `For/Next`, `Break`, `Continue`, `Exit` | |
| 7 | Short-circuit boolean evaluation | |
| 8 | Subroutines and functions, parameters (by value / by reference), return types | |
| 9 | Scope (`Public/Private`), modules, `Include` | |
| 10 | Aliases and modifiers (register/bit aliasing, absolute placement) | SF "Alias and Modifiers" |
| 11 | Structures, unions, user types | |
| 12 | Overloading, compound subroutines, `Inline` | later |
| 13 | EEPROM data declarations | maps to the device's data EEPROM |
| 14 | Embedded assembler (`Asm … End Asm`) | content is **pic-as syntax** |
| 15 | Interrupts, events, context saving | see §5.4 |
| 16 | Preprocessor: `#define #if #ifdef #constant #error #option` etc. | plus device predefined constants |
| 17 | Built-ins: `AddressOf, BitOf, Bound, Clear, Inc, Dec, High, Low, Input, Output, Toggle, DelayMS, DelayUS, Terminate` | SF "Predefined Subroutines and Functions" |

### 4.2 Conveniences (provided as library + thin header syntax)

The following *ideas* from other BASIC compilers are kept:

* A short program header: `Device = 18F27Q10` and `Declare Xtal = 64` (clock in MHz), or an
  equivalent in the module header. **Note:** the device name may be written with or without a `PIC`
  prefix — we accept both `18F27Q10` and `PIC18F27Q10`.
* `Symbol` aliases (`Symbol LED = PORTB.0`).
* Friendly commands as library procedures: `HRSOut`, `HRSIn`, `Toggle`, `DelayMS`, LCD, I2C,
  SPI, ADC read, PWM, EEPROM read/write, timers.
* `Dim x As Byte` as an accepted spelling of declarations.
* `Declare` for compile-time library settings (baud rate, LCD pins, …) mapped onto constants
  in the library modules rather than a global bag of switches.

### 4.3 Example (illustrative, final syntax set in M0)

```basic
Device = 18F27Q10
Clock = 64                       ' MHz; "Declare Xtal = 64" is accepted as an alias

Include "gpio"
Include "serial"

Dim LED As PORTB.0               ' alias to a port bit; "Symbol LED = PORTB.0" also accepted
Dim Count As Byte

Interrupt OnTimer()
    Inc(Count)
End Interrupt

' there is no Main: top-level statements run in order (decision D9)
Output(LED)
While True
    Toggle(LED)
    DelayMS(250)
    SerialWrite("Count=", Count, 13)
Wend
```

### 4.4 Syntax conflicts to settle in M0 (decision D2)

Some dialects use `Proc … EndProc`, others `Sub/Function … End Sub`. Both `Dim x As Byte`
styles exist. Plan: the core grammar uses `Sub/Function`; the `Proc` spellings are accepted as
aliases where they are unambiguous. The full grammar goes in `docs/GRAMMAR.md` (EBNF) in M0.

---

## 5. Target facts: PIC18F27Q10

### 5.1 Device summary — verified `[DS40002043F p.1–4, Table 1]`

| Item | Value |
|---|---|
| Program flash | 128 KB (64 KW) |
| Data SRAM | 3615 bytes — "includes 256 bytes of SECTOR space which is not included in the data size displayed by MPLAB X" (Table 1 note 2) |
| Data EEPROM | 1024 bytes |
| I/O pins | 25 (28-pin part) |
| Max speed | 64 MHz clock input; 62.5 ns instruction cycle |
| Hardware stack | 31 levels, "separate SRAM panel, apart from all user memory panels" `[p.108 note 1]` |
| 16-bit timers | 4 (TMR0/1/3/5); 8-bit timers with HLT: 3 (TMR2/4/6) |
| Serial | 2 × EUSART, 2 × I2C/SPI |
| ADC | ADC2 with computation, 24 channels on this part |
| CCP / 10-bit PWM | 2 / 2 |
| Other | 1 CWG, 8 CLC, 2 comparators, 5-bit DAC, ZCD, CRC/memory scan, windowed WDT, PPS |
| Voltage | 1.8 V – 5.5 V |

### 5.2 Memory map — verified `[DS40002043F p.108, Fig. 11-1]`

| Address | Region |
|---|---|
| `0x00_0000` | Reset vector |
| `0x00_0008` | Interrupt vector, high priority |
| `0x00_0018` | Interrupt vector, low priority |
| `0x00_001A`–`0x01_FFFF` | Program flash (64 KW) |
| `0x02_0000`–`0x1F_FFFF` | Not present (reads 0, does not roll over) |
| `0x20_0000`–`0x20_00FF` | User IDs (128 words) |
| `0x30_0000`–`0x30_000B` | Configuration words (6 words) |
| `0x3F_FFFC`–`0x3F_FFFD` | Revision ID |
| `0x3F_FFFE`–`0x3F_FFFF` | Device ID |

### 5.3 Data memory and addressing — verified `[DS40002043F p.116–120]`

* 12-bit data addresses → up to 4096 bytes, split into **16 banks of 256 bytes**.
* Bank Select Register `BSR[3:0]`; upper 4 bits read 0. Loaded with `MOVLB`.
* **Access Bank**: 256-byte space covering the SFRs and the lower part of bank 0 without
  needing BSR. Instruction bit `a`: `a=0` → Access Bank (BSR ignored); `a=1` → BSR bank.
* Addressing modes: inherent, literal, direct, indirect; plus **indexed literal offset** when
  the extended instruction set is enabled (`XINST` config bit = 1).
* Instruction set: **75 core instructions + 8 extended** `[p.621]`. The four two-word
  instructions are `MOVFF`, `CALL`, `GOTO` and `LFSR` `[p.626–629]` (verified in M1). Extended set: `ADDFSR, ADDULNK, CALLW, MOVSF, MOVSS, PUSHL, SUBFSR, SUBULNK`
  `[p.682 Table 38-3]`.
* **Verified in M1** (`docs/FACTS-18F27Q10.md` §1–2): the Access Bank is `00h–5Fh` of bank 0
  (GPR) plus `60h–FFh` of bank 15 (SFR) `[p.118–119]`; GPR runs `0x000–0xE1E` with bank 13
  (`0xD00–0xDFF`) a reserved "SECTOR" block, leaving 3359 usable bytes (`0xD1F`), which is what
  pic-as reports. With `XINST = 1` the low 96 Access Bank bytes become FSR2-indexed
  `[p.119, p.123]`, so the default build uses `XINST = 0`.

### 5.4 Interrupts

* Two priority levels with vectors at `0x08` (high) and `0x18` (low) `[p.108]`; the datasheet
  lists "Programmable 2-Level Interrupt Priority" `[p.1]`.
* **Verified in M1** (`docs/FACTS-18F27Q10.md` §4): control registers are `INTCON`, and 8 each of
  `PIR`, `PIE`, `IPR`; `IPEN` selects priority mode; there is **no vectored-interrupt table**
  (fixed vectors only); on entry `WREG`, `STATUS` and `BSR` go to a one-level fast register
  stack (restored by `RETFIE, FAST`), which is unreliable for the low-priority handler when both
  priorities are used; and `MOVFF` must never write an interrupt control register while any
  interrupt is enabled `[p.112, p.193–195]`.

### 5.5 Errata that affect code generation / library — `[DS80000832G p.2–6]`

| Item | Effect on this project |
|---|---|
| 1.9.1 PFM self-write: first instruction after a self-write may not execute (rev A4, B2) | Workaround (read in full in M1, `[DS80000832G p.7]`): **two all-zero `NOP`s immediately after the self-write instruction.** The flash-write routine emits exactly that. |
| 1.6.2 No PFM writes above 85 °C | Document in the library; no compiler impact. |
| 1.7.2 XT mode max 2 MHz; use HS above | `Declare`/clock-validation: warn when config selects XT with Xtal > 2. |
| 1.7.1 HFINTOSC varies up to 5 % over V/T | Serial library: document baud-rate error for internal-oscillator designs. |
| 1.4.1 FVR reference → missing codes (TAD ≥ 8 µs or use VDD) | ADC library default uses VDD reference; warn on FVR with short TAD. |
| 1.4.4 first conversion after large falling slew is bad | ADC library discards first sample after a channel change. |
| 1.2.1 RMCLR flag may be cleared by POR/software reset | Reset-cause library routine must note this; no workaround exists. |
| 1.8.1 No software breakpoints | None (we have no debugger integration). |

Errata that only concern power or peripherals we do not support yet (WWDT in Doze, CWG
auto-shutdown, LPBOR, sleep current, NVMERR) are deferred until those peripherals get library
support (§6).

---

## 6. Standard library plan

Written **in the language** (so the compiler does not grow), conditionally compiled with
device feature constants (`#if Device.HasEUSART2`, …). Each library module cites its datasheet
chapter in a header comment, and its chosen register/bit names are generated from the device
pack — not typed in by hand.

| Module | Contents | Notes |
|---|---|---|
| `gpio` | `Input/Output/High/Low/Toggle`, port/bit access, pull-ups, PPS helpers | Registers from pack. |
| `delay` | `DelayMS/DelayUS/DelayCycles` | Cycle-accurate; depends on `Xtal`. |
| `timer` | TMR0/1/2 setup helpers, tick counters | |
| `serial` | EUSART1/2 init, send/receive, print numbers/strings, baud calc | Uses PPS; baud error check. |
| `adc` | ADCC single conversion, channel select | Errata 1.4.1 / 1.4.4 applied. |
| `eeprom` | Data EEPROM read/write (NVM) | |
| `flashwrite` | Program flash self-write | Errata 1.9.1; low priority. |
| `pwm` | CCP / 10-bit PWM | |
| `i2c`, `spi` | MSSP-style master | |
| `lcd` | HD44780 | `Declare`-style pin mapping. |
| `system` | Reset cause, clock setup, config helpers | |

Order of work follows §10; each module ships with at least a compile test, and a simulator or
hardware test where possible.

---

## 7. Code generation strategy (PIC18)

### 7.1 Two back-end routes

**Route A — direct emitter (baseline, always available).** Our IR is lowered by our own
PIC18 code generator straight to pic-as assembly. Simple, fully under our control, no LLVM
dependency. This is the guaranteed path.

**Route B — LLVM (optimising, optional).** Front-end emits LLVM IR text; a PIC18 LLVM
backend produces pic-as assembly. A partial **recovery of an earlier PIC LLVM backend** exists
at `~/Documents/PIC_Compiler_recovered/` (about 285 files: TableGen, ISel, GlobalISel, MC
layer, PIC18 expand-pseudo, a PIC18 simulator header and tests) plus a built binary
`~/.local/build/llvm-pic/bin/pic-llc` (2026-10-14). Its condition is **unverified**: 68 edits
could not be re-applied, and nothing has been rebuilt. Route B is therefore *gated* by
milestone M7.

Recommendation (D3): build **Route A first**, so the project works end to end early; evaluate
Route B in M7 purely on whether it builds and passes its own recovered tests, and adopt it only
if it clearly beats Route A on code size/speed.

Both routes emit the same assembly dialect and use the same device description, linker
layout and library, so they are interchangeable behind the driver.

### 7.2 Calling convention and stack (decision D4, finalise in M4)

* **Hardware stack**: 31 levels `[p.1]`. The compiler computes the maximum call depth from the
  call graph (including interrupt entry) and errors if it can exceed 31. (The recovered code
  has a `PICStackDepth` pass worth reading for ideas — treat as reference only.)
* **Default: static frame allocation with overlay.** Each function's locals/parameters get
  fixed RAM addresses; functions that can never be live at the same time share memory
  ("frame recycling"). Fast, no stack pointer. Recursion is rejected at
  compile time unless the function is marked reentrant.
* **Reentrant functions (opt-in)**: use a software stack through `FSR2`. The extended
  instruction set (`PUSHL, ADDFSR, SUBFSR, MOVSF, MOVSS, CALLW, ADDULNK, SUBULNK`) is built for
  this `[p.621, p.682]`; it requires `XINST = 1` in the configuration words. **Verified in M1:** enabling XINST
  changes the Access Bank: file addresses ≤ `5Fh` become FSR2-indexed `[p.119, p.123]`, so the
  code generator must know which mode it is in and use bank-select addressing for ordinary
  variables when `XINST = 1`.
* **Extended instruction set and Indexed Literal Offset — to be implemented (M9, with reentrant
  functions).** The extended set is off by default (`XINST = 0`) and is aimed at compiler-generated
  reentrant code, so it is not for hand-written assembly `[DS40002043F ch.38.2]`. Work items:
  1. Assembler/size table (`src/asm.rs`): all eight extended instructions with correct word counts
     and operand ranges (`ADDFSR/SUBFSR f,k`, `ADDULNK/SUBULNK k` = FSR2 form with automatic return,
     `PUSHL k`, `CALLW`, `MOVSF zs,fd`, `MOVSS zs,zd`); today only `movsf`/`movss` sizes exist.
  2. Code generator: a per-build `XINST` mode flag. In `XINST = 1`, Access Bank accesses to ≤ `5Fh`
     become FSR2 + literal-offset, so ordinary variables use bank-select (`a = 1`) addressing and
     reentrant locals/parameters use `[FSR2 + k]` frame addressing.
  3. Reentrant frames: allocate/free software-stack space with `ADDFSR`/`SUBFSR`, return with
     `ADDULNK`/`SUBULNK 2`, push literals with `PUSHL`, move between frame slots with `MOVSF`/`MOVSS`.
  4. Function pointers: indirect call through `CALLW`.
  5. Lift the `E-BACKEND` rejection of `Reentrant` routines once 1-4 pass.
  6. Simulator + tests: extend `tests/` simulator with the eight instructions and ILO addressing;
     execution tests for recursion and a mixed reentrant/static program; add a benchmark pair vs XC8
     with the extended set enabled. Confirm instruction encodings and ILO behaviour from the datasheet
     at implementation time (M9 start) rather than from this note.
* Parameters and return values: first byte(s) via WREG/fixed registers, rest in the callee's
  frame; exact layout written in `docs/ABI.md` in M4.
* Interrupts: separate frame region for ISR locals so the ISR never overwrites main-line
  locals; shared-variable access rules documented.

### 7.3 Data and bank management

* RAM allocation uses the device description's GPR ranges per bank.
* The most-used variables go in the **Access Bank** so they need no `BSR` handling
  (`a=0` form). Everything else is bank-tracked: the code generator keeps a "current BSR"
  state per basic block and inserts `MOVLB` only when needed.
* Objects larger than 256 bytes (arrays across banks) are addressed through `FSRn`
  (indirect addressing); the compiler hides this.
* Constants/strings live in program flash (`data` psect, class CONST on PIC18
  `[XC8 PIC Assembler UG Table 5-2]`) and are read with the table read instructions.

### 7.4 Optimisations (staged — superseded by the priorities and targets in §7A)

1. M5: constant folding, dead-code removal, strength reduction (shifts instead of multiply by
   powers of two), branch simplification.
2. M6: access-bank allocation by use count, BSR-redundancy elimination, byte-wise math using the
   hardware 8×8 multiplier (`MULWF`/`MULLW`, 1 cycle, verified in M1).
3. Later: inlining, register (WREG/FSR) allocation across statements, peephole pass.

---

## 7A. Code efficiency (top priority)

Efficiency means **program words (flash)**, **data RAM** and **cycles**, in that order of
measurement, with a per-routine choice of Size or Speed. The rules below are binding on the
design; each is checked by a measurement, not by intuition.

### 7A.1 Principles

1. **Measure, don't guess.** Every optimisation lands with before/after numbers from the
   benchmark harness (§7A.4). PIC18 intuitions from 32-bit CPUs are often wrong (the project's
   earlier XC8 measurements found a "shift instead of multiply" variant losing to the
   hardware multiplier).
2. **Whole-program compilation.** All modules are compiled together, so the compiler knows the
   complete call graph and every constant. That enables: dead function/data/statement removal,
   single-call inlining (the default, as in the reference language), static frame overlay,
   exact stack-depth proof, cross-call constant propagation, and cloning of small routines on
   constant arguments.
3. **Exact-width arithmetic.** The IR carries a bit-width (8/16/24/32) on every operation and
   range analysis narrows each operation to the smallest width that cannot lose information.
   24-bit is a first-class internal width because it is cheaper than 32-bit on an 8-bit core.
   No C-style "promote everything to int".
4. **Use the hardware.** Single-instruction bit set/clear/toggle/test, skip-on-condition,
   decrement/increment-and-skip loops, the 8×8 hardware multiplier, byte-aligned shifts as plain
   byte moves, short relative branches, table reads for constants in flash, and `MOVFF`.
   **Verified in M1** against the instruction tables `[DS40002043F p.626–629]`: every instruction
   named here exists on the 18F27Q10; `MULWF`/`MULLW` take 1 cycle; skips cost 1/2/3 cycles.
   The project's earlier measurements (hardware 8×8 multiply = 1 cycle; software 32×32 multiply ≈ 550+ cycles under
   XC8; shifts by 8/16 are byte moves; `uint24` cheaper than `uint32`) are *inputs to be
   re-measured*, not facts to build on blindly.
5. **Pay only for what is used.** No hidden runtime. A library routine (divide, float helper,
   string copy, …) is emitted only if reachable, and in the narrowest specialisation needed
   (8-, 16-, 24- or 32-bit variants are separate routines).
6. **Placement is part of code generation.** The Access Bank and BSR strategy (§7.3) is driven
   by loop-weighted use counts so hot variables need no bank switches.
7. **Correctness guard.** An `-O0` build is the reference. Every optimisation is
   differential-tested (optimised vs. `-O0` in the simulator) and arithmetic routines are
   checked exhaustively on the host where the input space allows (e.g. all 8×8 and 16×8
   products), as in the earlier XC8 work.

### 7A.2 Language rules that make efficient code possible (decision D16)

* **Context-width evaluation.** An arithmetic expression is evaluated at the width of the
  *widest of its operands and its assignment target* (never wider unless a conversion asks).
  So `W = B1 * B2` (Word target, Byte operands) is one hardware multiply with a 16-bit result,
  while `B3 = B1 + B2` is an 8-bit add that wraps. Precisely specified in `LANGUAGE.md` §5.
* **Integer division and modulo by constants** are strength-reduced where profitable.
* **`For` loops** with a provably in-range control variable compile to count-down
  decrement-and-skip loops when the body does not use the index.
* **Explicit width controls** are available when the programmer wants them: width conversion
  functions, `Bytes(n)`/`Byte0..3` modifiers and promotion modifiers (as in the reference
  language) for zero-cost partial access to multi-byte values.
* **Per-routine hints**: `Inline`, `NoInline`, and `Speed`/`Size` attributes; a global
  `#option Optimize = Size | Speed | Balanced`.

### 7A.3 Optimisation passes (priority order)

| Priority | Pass | Expected effect |
|---|---|---|
| 1 | Constant folding/propagation, dead-code/data removal, single-call inlining | Size, speed |
| 2 | Width narrowing (range analysis) | Size, speed — usually the biggest win on 8-bit |
| 3 | Access-Bank allocation by loop-weighted use; BSR redundancy elimination | Size, speed |
| 4 | Static frame overlay from the call graph | RAM |
| 5 | Branch selection and relaxation (short relative vs. long branches), loop-form selection | Size, speed |
| 6 | Multiply/shift/divide strength reduction using the hardware multiplier and byte moves | Speed, size |
| 7 | Tail-call (jump instead of call+return), switch lowering by cost model (compare chain vs. table) | Size, speed |
| 8 | Peephole (read-modify-write fusion, redundant `WREG` loads, bit-store patterns) | Size, speed |
| 9 | Cloning on constant arguments, cross-module specialisation | Speed |

The recovered earlier backend contains peepholes and passes for several of these
(`PICWPeephole`, `PICFoldRMW`, `PICBitStore`, `PIC18BranchRelax`, `PICFsrLoop`, …). They are a
**reference for what mattered**, to be re-derived and re-measured here, not code to trust.

### 7A.4 Measurement harness and targets

* **Harness (built in M4, before any optimisation work):** compiles each benchmark with this
  compiler, assembles with pic-as, reads program words and data bytes from the linker map, and
  runs the hex in the MDB simulator for cycle counts (`/usr/bin/mdb`; the same
  XC8 + MDB stopwatch approach already used in `~/.claude/skills/xc8-pic18-optimize/`).
  A report command (`basil --report`) prints size and RAM per routine.
* **Benchmark set (kernels, C and BASIC equivalents):** integer math at 8/16/24/32 bits,
  multiply/divide/modulo by constants and variables, CRC-8/16, fixed-point scaling, bit-banging,
  table lookup, string output, ADC averaging, buffer copy/search, a state machine, an ISR
  with a counter, a PWM-style loop. Growth continues as library modules appear.
* **Baselines — independent reference compilers, installed and verified here:**
  1. **XC8 v4.00** (`/opt/microchip/xc8/v4.00/bin/xc8-cc`) at `-Os` and `-O2` on the C version of
     each kernel; size read from the linker map (`Program space used`, `Data space used`).
  2. **Another BASIC compiler** on the BASIC version of each kernel; size from its `ROM used` /
     `RAM used` report, cycles from the same MDB runs. It is the closest like-for-like comparison
     because it is the same language family — it shows what a BASIC compiler can achieve on this
     chip, XC8 shows what a C compiler achieves.
  * **First data point (verified 2026-10-23, 18F27Q10, kernel `x = 5; loop forever: x = x + 1`,
    with `x` a byte variable):** XC8 `-Os` and `-O2`: **24 bytes** program, **1 byte** data;
    the other BASIC compiler: **32 bytes** ROM, **26 bytes** RAM (its RAM figure includes its own system and
    frame storage). This shows two things worth targeting: a BASIC compiler should not pay a
    fixed RAM tax for a one-byte program, and the code can match XC8.
  * **How the reference compilers may be used (clean-room, PLAN §2):** only as black boxes —
    feed them *our own* test programs and read the size/cycle numbers and the resulting hex
    behaviour. Do not disassemble the compilers, and do not copy their generated library code
    or assembly into this project. Their output is a yardstick, not a source.
  * Because both comparators produce a `.hex`, the same MDB harness measures cycles for all three
    compilers on identical stimulus; any behavioural difference between the three is a bug to
    explain (in ours, in a comparator, or in the spec).
* **Proposed targets (to be calibrated once baseline numbers exist at M4 — these are
  placeholders, not promises):**
  * M5 gate: program words within **+20 %** of XC8 `-Os` on the median kernel, no kernel
    worse than +50 %.
  * M9 target: **at or below XC8 `-Os`** on the median kernel for size, and not slower than
    XC8 `-O2` in cycles on the median kernel.
  * Zero regressions: the harness runs on every change that touches code generation; a size or
    cycle regression beyond a set threshold needs an explicit note.
* Results are recorded in `docs/BENCHMARKS.md` with the compiler revision.

### 7A.5 Efficiency in the library (see §6)

Library routines are written in the language and are subject to the same optimiser; each
module has a size/speed benchmark entry. Hot paths that the compiler cannot yet match (for
example a byte-serial output loop or a multi-byte shift) may use `Asm` blocks, kept small,
benchmarked, and replaced when the compiler catches up.

---

## 8. Toolchain integration (pic-as)

### 8.1 Installed tools — verified on this machine `[observed]`

* pic-as: `/opt/microchip/xc8/v4.00/pic-as/bin/pic-as` (MPLAB XC8 PIC Assembler V4.00).
* Device pack for the target: `~/.mchp_packs/Microchip/PIC18F-Q_DFP/1.31.492/`, with
  `xc8/pic/include/proc/pic18f27q10.inc` and `edc/PIC18F27Q10.PIC`.
* Assembler user guide: `/opt/microchip/xc8/v4.00/docs/MPLAB_XC8_PIC_Assembler_User_Guide.pdf`.
  MPASM→pic-as migration guide in the same folder.

### 8.2 Command line (smoke-tested) `[observed]`

```
pic-as -mcpu=18F27Q10 -mdfp=$HOME/.mchp_packs/Microchip/PIC18F-Q_DFP/1.31.492/xc8 \
       -Wl,-Map=prog.map -o prog.hex prog.S
```

A test file with `#include <xc.inc>`, a `CONFIG` line, a reset-vector psect and a toggle loop
assembled to a valid Intel-hex for the 18F27Q10 (12 bytes of code). Options documented in the
user guide: `-mcpu`, `-mdfp`, `-mreserve`, `-Wl,…` pass-through.

### 8.3 Things the generated assembly must handle

* **Configuration bits**: `CONFIG setting = value` or `CONFIG register = literal`
  `[UG §4.9.7, p.41]`. Setting/value names come from the pack's chipinfo data. An un-set word
  gives a warning `(1311)` and uses a default `[observed]`. The compiler will always emit the
  full set of config words explicitly and expose the important ones (oscillator, WDT, LVP,
  XINST, MCLR, BOR, code protect) through a `Config` section in the source.
* **Vector placement — gotcha found while testing** `[observed]`: a psect declared
  `PSECT resetVec,class=CODE,reloc=2` was placed by the linker at the *end* of flash, not at
  address 0. Vectors must be pinned explicitly: either `abs`/`org` psects, or linker position
  options (`-Wl,-p<psect>=<addr>`; the guide's linker section gives an example of the form
  `-Wl,-pInterrupt=08h` — exact page to be noted in M1). The code generator will pin reset (`0x00`), high interrupt (`0x08`) and low
  interrupt (`0x18`) and test that with a map-file check.
* **Psects**: `code`, `udata`, `udata_acs` (Access Bank RAM), `udata_bankN`, `edata`, `data`
  (flash constants) are provided once `<xc.inc>` is included `[UG Table 5-2]`.
* **Diagnostics**: pic-as errors/warnings are parsed and mapped back to BASIC source lines
  through `;` source-line comments in the emitted assembly.
* The driver wraps the whole pipeline in a `basil prog.bas` command that prints
  `file:line: error: message`, the same shape the Zed tasks already parse for the other compiler wrappers.

---

## 9. Device descriptions — how more micros get added slowly

This is the key mechanism for the "other micros later" requirement.

### 9.1 What a device description contains

One generated file per device (format: TOML or JSON, decided in M2):

* name, core family (`pic18`, later `pic16e`, `pic16`, …), instruction-set flags
  (extended instruction set available?), clock limits
* program memory size, vector addresses, page/bank structure
* data memory: GPR ranges per bank, Access Bank split, SFR map (name, address, bit fields)
* EEPROM size/address, user-ID and config-word addresses
* peripheral inventory (EUSART count, ADC type, timers, CCP, PPS, …)
* configuration-word setting names and legal values
* pin ↔ port-bit map, PPS inputs/outputs where present
* per-device errata flags used by the library

### 9.2 Where it comes from

Generated by a small tool (`devgen`) from **Microchip's own pack** (`edc/<PART>.PIC` and
`include/proc/<part>.inc`) and cross-checked against the datasheet by script where possible
(e.g. memory sizes vs. Table 1). The recovered earlier project had a similar `gen-devices`
tool; its design may be reused as a reference.

### 9.3 Checklist to add a new micro (this becomes `docs/ADDING_A_DEVICE.md`)

1. Install/locate the pack, datasheet and errata sheet for the part (via the
   `microchip-docs` and `pic-docs` tools already set up).
2. Run `devgen` → new device file. Review the diff against a sibling part.
3. Check whether the **core family** already has a code generator:
   * same family (e.g. another PIC18 Q-series) → usually no compiler change;
   * new family (e.g. enhanced mid-range PIC16, classic PIC16, PIC12) → new code-generator
     module and a family spec of its own (instruction set, banking, paging, stack rules).
4. Read that device's errata; update flags/warnings.
5. Library: **needs attention for every new device and family.** The modules were written for the
   PIC18F27/47Q10 and only some are ported (table in `docs/LIBRARY.md`, "Device support"). Confirm each
   peripheral module compiles and is correct for the new device; register-name differences are handled
   with `#if _has(REG)` / `_has(REG.FIELD)` in the module (one branch per register layout, not per part
   number), and pins, channel numbers and errata workarounds are decided per part and cited from its
   data sheet. A module not yet ported must fail with `#error`, not silently use the Q10 registers.
6. Add the regression set: compile the standard test programs for the new device and (where
   possible) run them in a simulator or on hardware.
7. Only then mark the device "supported" in `docs/DEVICES.md` **and in `docs/MANUAL.md`, "Supported device"**
   (also the library table in `docs/LIBRARY.md`).

### 9.4 Rough order (a proposal — Gary decides the real order, device by device)

1. **PIC18F27Q10** (this plan).
2. Sibling PIC18 Q-series / K-series parts: low effort, same core family.
3. Other PIC18 families.
4. PIC16 enhanced mid-range (e.g. 16F17146, 16F1829 — parts already in use on other projects).
5. Classic PIC16 / PIC12 / PIC10 last (the oldest cores, most quirks).

Each step is its own small milestone with its own acceptance test; none are scheduled until
M9 is done.

---

## 10. Milestones

Each milestone ends with something that runs and a short note in `docs/PROGRESS.md`.

| M | Name | Deliverables | Acceptance |
|---|---|---|---|
| **M0** | Foundations | Repo skeleton; `docs/LANGUAGE.md`, `docs/GRAMMAR.md` (EBNF), `docs/ABI.md` outline; decisions D1–D6 recorded; language implementation chosen | Reviewed and approved by Gary |
| **M1** | Fact base | Datasheet/pack extraction notes for 18F27Q10: full memory map, Access Bank split, SFR map, interrupt system and context save, instruction table (incl. two-word, multiplier, XINST effects), config word layout, vector details; errata read in full | Every "TO VERIFY (M1)" item in this plan resolved with page cites |
| **M2** | Device description | `devgen` produces the 18F27Q10 device file from the pack; script cross-checks sizes vs. datasheet Table 1 | Generated file passes cross-check; reviewed |
| **M3** | Front end | Lexer, parser, AST, semantic analysis for the core language subset (types, expressions, control flow, subs/functions, modules, constants); error messages with line/column | Parses and type-checks a corpus of valid and invalid programs; unit tests green |
| **M4** | Minimal back end (Route A) + measurement | **Width-annotated IR**; PIC18 code generator; static frames; pic-as driver; vectors, config, startup/RAM init; `basil prog.bas` → `.hex`; **benchmark harness (size via map file, cycles via MDB) with XC8 baseline numbers for the kernel set (§7A.4)** | "Blink" and an integer-math test assemble and link; map-file check confirms vector placement; behaviour verified in MDB or on hardware; `docs/BENCHMARKS.md` holds the first baseline table and the §7A.4 targets are calibrated from it |
| **M5** | Language breadth + first optimisations | Arrays, strings, structures, 16/32-bit math, `Select Case`, loops with `Break/Continue`, short-circuit logic, compile-time stack-depth and RAM checks; optimisation passes 1–4 of §7A.3 (folding/DCE/inlining, width narrowing, Access-Bank allocation, frame overlay) | Test suite of ≥ 50 programs; golden-assembly tests; all pass; **efficiency gate**: benchmark set meets the M5 size target in §7A.4; differential tests (optimised vs. `-O0`) pass |
| **M6** | Interrupts and library core | Interrupt handling and context saving (per M1 facts); `gpio`, `delay`, `timer`, `serial`; BSR and access-bank optimisation | Serial echo and timer-interrupt programs verified on hardware (programmer to be decided, D6) |
| **M7** | Route B evaluation | Re-point the LLVM tree at the recovered backend, build it, run its recovered tests; compare output vs. Route A on the same programs | Written decision: adopt, adopt-partly, or drop Route B |
| **M8** | Library breadth | `adc`, `eeprom`, `pwm`, `i2c`, `spi`, `lcd`, `system`; errata workarounds applied and documented | Each module has a compile test and one hardware or simulator test |
| **M9** | Hardening | Float support, `Inline`, overloading, reentrant functions via FSR2, diagnostics polish, Zed task + highlighting extension, `docs/` complete | Real small project written end-to-end in the language |
| **M10+** | More micros | Per §9.3/§9.4, **one device at a time, slowly** | Each device passes its own acceptance set before it is listed as supported |

---

## 11. Testing strategy

* **Unit tests** for lexer, parser, semantic checks, IR passes, device-file generator.
* **Golden tests**: BASIC → expected assembly text, re-baselined deliberately.
* **Assemble tests**: every golden output must assemble with pic-as without warnings other
  than allowlisted ones (the config-word `(1311)` warning disappears once the compiler emits
  all words).
* **Execution tests**: run the hex in a PIC18 instruction-set simulator and compare the
  program's observable results against a host-computed reference (the recovered project's
  simulator headers and exhaustive-style tests are a good starting point; they need
  re-verification first).
* **Behavioural comparison** with another BASIC compiler for the same source where the language
  overlaps.
* **Hardware tests**: a small suite flashed to a real 18F27Q10. Programmer choice is open (D6):
  an MPLAB X project exists at `~/MPLABXProjects/test.X`; the home-built Nucleo-based PIC
  programmer currently targets only PIC16F17146/17124, so it cannot be assumed.
* **Negative tests**: stack-depth overflow, RAM exhaustion, bad config values, wrong device
  names, recursion, etc. must produce clear errors.

---

## 12. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Scope creep: two big languages combined | Strict core + library split; M0 freezes the core grammar; features beyond M5 need a written reason. |
| Efficiency targets prove unrealistic, or optimisation introduces miscompiles | Targets are calibrated from real XC8 baselines at M4 before being enforced; `-O0` reference build plus differential testing and exhaustive arithmetic checks guard every pass (§7A.1). |
| Recovered LLVM backend is stale or broken | Route A is the baseline; Route B is gated at M7. |
| Device facts remembered wrongly | Rule: every device fact is read from the datasheet/pack and cited; "TO VERIFY" markers enforced at M1. |
| pic-as behaviours (e.g. vector placement) surprise us | Smoke-test each assumption early (done for config and vectors); keep a `tests/pic-as/` folder of tiny probes. |
| Errata missed | Read errata fully at M1; add per-device errata flags; revisit when adding each new device. |
| Licence issues with vendor manuals/tools | Clean-room rules (§2); check licence terms; personal use only. |
| Adding devices later is harder than expected | Device-file + family-module separation (§3, §9); first non-PIC18 device is a deliberate design checkpoint. |
| No programmer for 18F27Q10 | Decide D6 before M6; simulator covers M4–M5 meanwhile. |

---

## 13. Repository layout (proposed, created in M0)

```
Basic_Compiler/
  PLAN.md                  this file
  docs/                    LANGUAGE.md GRAMMAR.md ABI.md DEVICES.md ADDING_A_DEVICE.md PROGRESS.md
  src/                     compiler sources (front end, IR, codegen/pic18, driver)
  devices/                 generated device descriptions (one per part)
  tools/devgen/            device-file generator (reads Microchip packs)
  lib/                     standard library modules written in the language
  tests/                   unit, golden, execution, pic-as probes, negative tests
  reference/               vendor manuals kept for personal reference (not redistributed)
```

The two PDFs already in this folder move to `reference/` in M0.

---

## 14. Open decisions

| ID | Decision | My recommendation | Needed by |
|---|---|---|---|
| D1 | Implementation language | Rust (matches the existing AVR compiler front-end) | M0 |
| D2 | Surface syntax | Structured core, alternative spellings accepted as aliases | M0 |
| D3 | Back-end route | Route A first; evaluate Route B (recovered LLVM) at M7 | M0 / M7 |
| D4 | Calling convention | Static frames with overlay; opt-in reentrant via FSR2 | M4 |
| D5 | Device-file format | TOML (readable, diff-friendly) | M2 |
| D6 | How to flash/test on hardware | Decide the programmer before M6 (MPLAB X tool vs. extending the home-built programmer) | M6 |
| D7 | Float format | Decide after M5 (library vs. compiler support) | M9 |
| D8 | Next micro after the 18F27Q10 | Gary's call, per §9.4 | after M9 |
| D16 | Expression evaluation width | Context-width rule (§7A.2): widest of operands and assignment target | M0 (decided; see `docs/DECISIONS.md`) |
| D17 | Optimisation scope | Whole-program compilation; `-O0` reference build always available | M0 (decided) |

---

## 15. Sources used for this plan

| Source | Used for |
|---|---|
| `~/Documents/Microchip/PIC/PIC18F27Q10/PIC18F27-47Q10-…-DS40002043.pdf` (DS40002043F, 767 pp.) | §5.1–5.4: device summary (p.1–4), memory map (p.108), data memory/addressing (p.116–120), instruction set (p.621–622, 682) |
| `…/PIC18F274-7Q10-Si-Errata-…-DS80000832.pdf` (DS80000832G) | §5.5 (p.2–6; item 1.9.1 text not yet read in full — M1) |
| `/opt/microchip/xc8/v4.00/docs/MPLAB_XC8_PIC_Assembler_User_Guide.pdf` (DS50002974E) | §8: CONFIG directive (p.41), psects/classes (Table 5-2), default link line |
| Observed on this machine | pic-as smoke test; recovered-project inventory |
