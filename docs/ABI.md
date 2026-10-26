# ABI (M4: sections 1, 3, 5 implemented; 2 and 4 partly)

Status: M4 implementation for scalar programs; sections not marked otherwise are still the plan. Every device-specific statement is marked
**TO VERIFY (M1)** until it has a datasheet page cite. The aim is the cheapest correct convention
on an 8-bit PIC18 (PLAN §7A), not compatibility with any other compiler.

## 1. Storage classes

| Class | Where | Notes |
|---|---|---|
| Global/static variables | Data RAM, banked or Access Bank | Allocated by loop-weighted use count (PLAN §7A.3 #3). Zero-initialised unless provably written before read. |
| Routine frames (locals + parameters) | Data RAM, **overlaid** | One static frame per routine; routines never live together share addresses (call graph). No frame pointer. |
| Interrupt frames | Data RAM, **not overlaid** with main-line frames | A handler owns its storage (LANGUAGE.md §8). |
| Event frames | Data RAM, own unique frame | LANGUAGE.md §8. |
| Constants (strings, `Const` arrays) | Program flash, read with `TBLRD` through `TBLPTR`/`TABLAT` (2 cycles each) | Verified M1 `[DS40002043F p.629]`. |
| Hardware return stack | Dedicated 31-level stack `[DS40002043F p.1, p.108]` | Depth proven at compile time; error if the proven maximum can exceed the device's depth (31 on the Q10; 127 on the PIC18-Q41, `hw_stack` in the device file). |
| Reentrant software stack (opt-in) | Data RAM through `FSR2` | Needs `XINST = 1`; then Access Bank addresses ≤ `5Fh` become FSR2-indexed, so ordinary variables must use bank-select (`a = 1`) addressing in such builds (verified M1 `[DS40002043F p.119, p.123]`). |

## 2. Registers (provisional; interrupt-related facts verified in M1)

| Register | Use |
|---|---|
| `WREG` | Scratch, first byte of an argument, 8-bit return value |
| `FSR0` | Compiler-owned: array and pointer access in generated code |
| `FSR1` | Compiler-owned secondary pointer (block copies, strings) |
| `FSR2` | Reserved for the optional reentrant software stack; otherwise free for the programmer |
| `BSR` | Tracked per basic block; MOVLB inserted only when the bank actually changes |
| `PRODH:PRODL` | Hardware-multiplier result; treated as scratch across calls |
| `TBLPTR`, `TABLAT` | Table reads; treated as scratch across calls |

Interrupts (verified M1, `docs/FACTS-18F27Q10.md` §4; implemented M6, D40–D45): `WREG`, `STATUS`
and `BSR` are saved on entry in a one-level fast register stack and the handler returns with
`RETFIE, FAST`; with both priorities in use the low-priority handler saves them in software
(`movff WREG/STATUS/BSR` into its save area, restored `BSR`, `STATUS`, `WREG` last, plain `RETFIE`).
Everything else a handler touches (`PRODH:PRODL`, `FSR0..2`, `TBLPTR`, `TABLAT`, the used bytes of
`__A`..`__D`) is saved by the handler: the code generator scans the handler's emitted code (and the
shared helpers it calls) for those registers and copies exactly those with `MOVFF` into
`__ISV<n>`, a static area that is never overlaid. `MOVFF` is never used to write interrupt
control registers while any interrupt is enabled (`[DS40002043F p.194]`); nothing here does. The
save and restore code is fenced from the peephole pass (`Keep`).

PIC18-Q41 (vectored interrupt controller, `docs/FACTS-18F-Q41.md` §4): the controller saves `STATUS`, `WREG`,
`BSR`, `FSR0..2`, `PRODL/H` and `PCLATH/U` on entry in two sets (main and low-priority handler) and
`RETFIE, FAST` restores all of them, in either priority, so a handler saves in software only `TBLPTR`,
`TABLAT` and the used bytes of `__A`..`__D`. The interrupt control register is `INTCON0`, `Enable` sets only
`GIE` without priorities, and `MVECEN` is forced off (a program with a handler that asks for `MVECEN = ON`
is an `E-CONFIG` error).

## 3. Calling convention (as implemented in M4)

The parameter-in-`WREG` idea of the draft was dropped for M4: with static frames the caller knows
every callee address, so a plain store into the callee's frame is as cheap and needs no
convention. Measured against the cost model (open question 3) in M5.

* **Arguments**: the caller stores each argument, converted to the parameter's type, directly
  into the callee's parameter variable (`<ROUTINE>__<PARAM>`), then `rcall`/`call`s. When more than
  one argument contains a call, all arguments are first evaluated into temporaries, so a nested
  call cannot overwrite a parameter already stored.
* **Return value**: the callee assigns the function's `Result` variable (`<ROUTINE>__RESULT`); the
  caller reads it after the call. There are no return registers.
* **Clobbered**: everything. `WREG`, `STATUS`, `BSR`, `PRODH:PRODL`, `__A`..`__D` and the temporaries
  of the caller's frame are not preserved across a call; `BSR` is treated as unknown after one.
* **Expression values**: 8-bit in `WREG`; 16/24/32-bit in the accumulator `__A0..__A3`. `__B`
  (second operand), `__C` (remainder, and the product accumulator of multiplies) and `__D` (loop
  and shift counters) belong to the multiply/divide/shift helpers and to delay loops. All are Access Bank bytes, allocated only up to
  the highest byte actually used.
* **Structures**: stored field after field in declaration order, no padding or alignment; a union
  member shares the bytes of the field it names. An array of structures is its elements back to
  back. A `ByRef` structure parameter holds the 16-bit address of the argument and fields are
  reached through FSR0 at a constant offset. Block `Clear` and `a = b` (1 to 255 bytes) are unrolled
  `CLRF`/`MOVFF` when small, otherwise an FSR0 (destination) / FSR1 (source) loop using `WREG` as
  the counter.
* **Temporaries** (partial results saved while a second operand is evaluated) live in the
  routine's own frame, symbol `<ROUTINE>__TMP`, sized to the deepest use. A callee therefore cannot
  clobber its caller's temporaries.
* **Helpers**: `__mulN`, `__divN`, `__sdivN`, `__shlN`, `__shrN`, `__sarN` (N = bytes) are emitted
  only when reached. `__mulN` uses the hardware multiplier (partial products `A[i]*B[j]`, `i+j < N`,
  summed in `__C`); a multiply by a constant is expanded inline with `MULLW` and calls no helper. Both
  clobber `PRODH:PRODL` and `__C`. Division truncates toward zero; the remainder has the dividend's sign; division
  by zero yields an all-ones quotient and the dividend as remainder (no trap).
* **Frame overlay (done)**: two routines whose frames can never be live together (neither reaches
  the other through the call graph) are given the same addresses; a routine and anything it calls,
  directly or not, never overlap. The main program's own storage, globals and compiler scratch are
  never overlaid, and interrupt handlers (M6) must not be. Because the storage is shared, a local
  and `Result` start at zero on **every** entry (the clear is skipped when the body certainly assigns
  the variable first); parameters are written by the caller.
* **Tail calls, inlining**: not yet (M5).
* **Reentrant routines**: not yet (M9).

## 4. Symbol naming (needed by embedded assembly, LANGUAGE.md §13)

Emitted symbols are upper-cased and prefixed to avoid colliding with device register names and
pic-as keywords (pic-as is case-sensitive and has reserved words; this was a real problem in the
earlier assembler-translation experiment, where `IRP` is a directive). Scheme:

```
<module>_<name>            program/module-level variables and routines   (e.g. SERIAL_WRITE)
<routine>__<local>         locals                                        (e.g. MAIN__I)
__v_reset, __v_hi, __v_lo  vector psects
```
The compiler prints the symbol map with `--report` so `Asm` blocks can name variables reliably.

## 5. Program layout (implemented)

* **Vectors** are pinned explicitly (reset `0x0000`, high `0x0008`, low `0x0018`)
  `[DS40002043F p.108]`. In testing, a vector psect without an absolute/linker position was
  placed by pic-as at the *end* of flash; the code generator therefore emits absolute positions
  and the driver checks the map file.
* **Vectors** (only when the program has a handler): `0x0000` is `bra __reset`. One unprioritised
  handler (IPEN = 0) is placed at `0x0008`. With priorities (IPEN = 1) `0x0008` and `0x0018` each
  hold a branch to `__ISR_H` / `__ISR_L`, or spin when that level has no handler; the handlers
  follow, then the start-up code. Start-up sets IPEN before anything runs. On the PIC18-Q41 the word at each
  vector is always a `goto` (`MVECEN = 0` requires one, DS40002214G p.114), also for a single handler, which
  then follows the `goto` at `0x000C`.
* **`Save … Restore`**: byte-for-byte `MOVFF` copies into `__SAV<n>`; addresses are deduplicated so
  overlaid frames are copied once.
* **Start-up**: without interrupts the program begins at address 0 (no reset `goto`). The
  clock comes from the `Config` block alone; start-up clears every allocated global, local and
  `Result` byte (a loop through `FSR0` for runs over four bytes), stores initial values, runs module
  initialisation statements in include order, then the program body, then `__halt: bra __halt`.
* **Data layout**: the compiler assigns every address itself and writes `NAME equ 0xNNN` lines, so
  pic-as does not place data and `Data space used` in the map is 0. `--report` prints the real
  usage. Objects are placed hottest first (use count × 8^loop depth) into the Access Bank, then
  into banks, each inside one 256-byte bank; system RAM (bank 13) is never used. Unused
  variables get no storage.
* **Ports**: a write to `PORTx` is emitted as a write to `LATx` (reads stay on `PORTx`), so a
  bit-set never read-modify-writes the pins. `Input`/`Output` address `TRISx`.
* **Code placement**: one absolute psect `code` at `ORG 0`; the file ends `END __reset` (pic-as
  otherwise warns about a missing start record). Branches are relaxed to `bra`/`rcall`/short
  conditional forms when in range, else `goto`/`call` (inverted skip for conditionals).
* **Label table**: the generated file ends with `;SYM name 0xADDR` lines (byte addresses) for tools.
* **Interrupt entry**: see the vector and context-save notes above.

## 6. Open questions for M1/M4

1. ~~Exact Access Bank split and GPR ranges per bank~~ — resolved in M1 (FACTS §1–2).
2. Whether `FSR1`/`FSR2` may be left to the programmer outside the optional stack.
3. Cost model: static-frame argument passing vs. register passing (measured, not assumed).
4. Calling cost of the multiplier/divide helpers and whether they take arguments in `WREG`/frame
   slots or in dedicated Access Bank scratch.
