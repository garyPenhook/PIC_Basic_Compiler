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
* **Vectors with C linked:** see section 7. **Vectors** (only when the program has a handler): `0x0000` is `bra __reset`. One unprioritised
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

## 7. Calling C functions (implemented, 0.1.48)

`CFile "x.c"` and `Extern Sub|Function` (MANUAL, *Calling C* and *CFile, Extern*).

**Why not call the C function directly.** The MPLAB XC8 C Compiler User Guide for PIC (DS-50002737L, §5.8.5-5.8.6) says a
first one-byte parameter is passed in `W`, the others in `?_func`, and the result in `W` or `?_func`. That holds for an
unoptimised build only: with `-O1`/`-Os` XC8 compiles all the code at once and gives the parameters their own symbols
(`func@param`) and drops the `?_func` area when it is not needed (seen in 0.1.47: a function returning one byte read its
argument from the wrong place). The generated code therefore does not depend on XC8's convention.

**Bridge.** The driver writes `<name>_cstub.c` (`driver.rs::c_stub`):

* `volatile unsigned char basil_io[N]`, N = the largest argument list or result in bytes;
* for each `Extern` routine a wrapper `void basil_w_<name>(void)` in plain C that reads the arguments from `basil_io`
  (packed in order, little endian, as `*(volatile T *)(basil_io + offset)`), calls the function and writes the result to
  `basil_io` from offset 0;
* `main`, called by the XC8 start-up code: it calls `basil_entry` (the Basic program, which never returns), then every
  wrapper. Those calls never run; they put the wrappers and the C functions in the call graph XC8 builds from `main`,
  which keeps them and allocates their frames (calls from assembly are invisible to it).

**Thunk.** An `Extern` routine is an ordinary Basic routine (static frame, `<ROUTINE>__<PARAM>`, `<ROUTINE>__RESULT`)
whose body is generated `Asm`: `movff` of each parameter byte to `_basil_io+k`, `call _basil_w_<name>`, `movff` of the
result bytes back. Calls, frame overlay and the optimiser treat it as any routine with an `Asm` body.

**Link.** `xc8-cc -Os -mreserve=ram@a:b ...` (one range per RAM range the Basic program allocated) with the stub, the
`CFile`s and `<name>_basil.S`. Start-up is XC8's (`goto start` at 0, clear and copy of C data, `goto main`); the Basic code
is a relocatable psect `basilcode` instead of an absolute one at 0, and its own start-up code then runs from `main`.

**Arguments.** `CArg` (`ir.rs`): an integer of 1-4 bytes, a `Float` (4 bytes, XC8's `float` is IEEE 754 single), or a
pointer (the 16-bit address a `ByRef` parameter holds, cast to `T *` in the wrapper). The stub declares each C function
with the exact types, so XC8's whole-program check rejects a C definition that differs (`conflicting declarations`);
that is the only check there is. A structure is `struct <Basic name>` (forward-declared in the stub); a by-reference
array's length word is not passed.

**Interrupts.** With C linked the vectors are two absolute psects (`basilvhi` at 08h, `basilvlo` at 18h, written after
the code) holding a `goto` to `__ISR_H` / `__ISR_L`; the handlers are in `basilcode`. The XC8 `intcode` psects are not
used: the Q41 start-up does not place them at 08h. A handler cannot reach an `Extern` routine (`E-EXTERN`, sema
`check_isr_extern`), so C never runs inside a handler and `basil_io` is not shared with one. The handler saves the
registers its own code uses, which is all C needs; C's registers are never touched by it otherwise.

**C calls Basic (`Export`).** For each exported routine `R` the lowerer makes a thunk routine `_basil_x_R` (`ExportSig`):
`movff` of the argument bytes from `basil_io` into `R`'s parameters, a plain call of `R`, `movff` of the result back. The
stub defines `R` in C (the name C code calls, with the exported types) as: store the arguments into `basil_io`, call
`basil_x_R()`, return the result. Consequences in the compiler: the thunks are roots of code generation (`Gen::called`);
every `Extern` routine gets a call edge to every thunk, so frame overlay (`independent`) never shares storage between a
routine that waits for C and anything an exported routine runs, and the recursion check sees a cycle through C; the
optimiser treats an exported routine like a handler (no parameter propagation, no argument in WREG) because its calls
are not all visible. Frames are static, so there is no recursion through C.

Not supported: an `Extern` call from a handler, structure or array arguments by value, `Export` array parameters.

## 8. Enhanced mid-range core (PIC16F17126/46, implemented 0.1.50, library and `Float` in 0.1.51)

The calling convention of section 3 is unchanged: static frames that overlay when two routines are never live together, arguments
stored straight into the callee's parameters, the result in the callee's `Result` variable (read into `WREG` or `__A` by the
caller). What differs is the register file and the memory:

| | PIC18 | enhanced mid-range |
|---|---|---|
| Scratch `__A..__D` | Access Bank | common RAM (`70h..7Fh`, visible from every bank); only the bytes used are allocated |
| Bank | `movlb` + Access Bank | `movlb` for any address in `20h..6Fh` of a bank; core registers (`00h..0Bh`) and common RAM need none |
| Pointers | FSR0..FSR2, `TBLPTR` | FSR0 (work pointer, string/array access), FSR1 (second pointer, constant tables, copies); no FSR2 |
| A `ByRef` argument | 16-bit data address | the address an FSR uses: `2000h + bank * 80 + offset - 20h` for banked RAM (linear data memory), the plain address for common RAM and registers |
| Constant data | `TBLRD`, bytes packed two to a word | one `retlw` per byte, read through an FSR with bit 7 of `FSRnH` set (reads the low 8 bits of the word) |
| Calls and jumps | `rcall`/`bra`, `call`/`goto` with 20-bit targets | `bra` (+-256 words); `call`/`goto` carry 11 bits, so a program over 2K words sets PCLATH first (`movlp`) |
| Conditional branch | `bz`, `bnc` ... | a flag or bit test that skips a `bra` (`Item::SkipBr`); no `N`/`OV` flags |
| Return stack | 31 levels | 16 levels, one of them taken by an interrupt |
| Recursion (`Reentrant`) | frame pushed through FSR2 | frame pushed through FSR0 on `__SWSTK`, pointer `__SSP` (common RAM) |
| Interrupt entry | vectors at 08h/18h; hardware saves WREG/STATUS/BSR (fast) | one vector at 04h; hardware saves WREG, STATUS, BSR, FSR0/1 and PCLATH; software saves the scratch bytes the handler uses |
| Multiply | `mullw`/`mulwf` | shift and add (`__mul1..4`) |

`AddressOf` of a routine gives its program **word** address (15 bits). `AddressOf` of a `Const` array (0.1.51) gives the address an FSR
reads it at: the word address with bit 7 of the high byte set (DS40002343F Example 9-2), so `FSR1` loaded with the value reads the table with
`moviw 0[FSR1]`; the low 8 bits of each `retlw` word are the byte. RAM objects already give their FSR (linear data memory) address.

## 6. Open questions for M1/M4

1. ~~Exact Access Bank split and GPR ranges per bank~~ — resolved in M1 (FACTS §1–2).
2. Whether `FSR1`/`FSR2` may be left to the programmer outside the optional stack.
3. Cost model: static-frame argument passing vs. register passing (measured, not assumed).
4. Calling cost of the multiplier/divide helpers and whether they take arguments in `WREG`/frame
   slots or in dedicated Access Bank scratch.
