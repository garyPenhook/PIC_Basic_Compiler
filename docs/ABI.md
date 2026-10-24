# ABI (outline — to be finalised in M4)

Status: **outline only**. Nothing here is implemented. Every device-specific statement is marked
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
| Hardware return stack | Dedicated 31-level stack `[DS40002043F p.1, p.108]` | Depth proven at compile time; error if the proven maximum can exceed 31. |
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

Interrupts (verified M1, `docs/FACTS-18F27Q10.md` §4): `WREG`, `STATUS` and `BSR` are saved on
entry in a one-level fast register stack; with both priorities in use the low-priority handler
saves them in software. Everything else a handler touches (`PRODH:PRODL`, `FSRn`, `TBLPTR`,
`TABLAT`, compiler scratch) is saved by the handler. `MOVFF` is never used to write interrupt
control registers while any interrupt is enabled (`[DS40002043F p.194]`).

## 3. Calling convention (provisional)

* **Arguments**: first byte (or the only byte) in `WREG`; remaining bytes in the callee's frame
  slots, written by the caller directly (static frames mean the caller knows the callee's
  addresses). Multi-byte arguments are passed little-endian in consecutive frame bytes.
* **Return values**: 8-bit in `WREG`; 16/24/32-bit in a fixed scratch area in the Access Bank
  (`RET0..RET3`); larger values (strings, structures) by address of a caller-supplied buffer.
* **Callee-saved**: none by default (no registers survive a call); the compiler tracks what each
  routine clobbers and does not reload values that a callee provably leaves intact.
* **Tail calls**: a call immediately followed by return becomes a jump.
* **Inlining** decisions precede ABI lowering; an inlined routine has no ABI at all.
* **Reentrant routines**: arguments and locals are accessed through `FSR2` with indexed literal
  offset (extended instruction set), return address on the hardware stack.

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

## 5. Program layout

* **Vectors** are pinned explicitly (reset `0x0000`, high `0x0008`, low `0x0018`)
  `[DS40002043F p.108]`. In testing, a vector psect without an absolute/linker position was
  placed by pic-as at the *end* of flash; the code generator therefore emits absolute positions
  and the driver checks the map file.
* **Start-up** (`__v_reset` → `__start`): configure clock/ports per `Config` and `Clock`;
  zero only the RAM that needs it; run module initialisation statements in include order; then
  the program body; then a halt loop.
* **Interrupt entry**: priority and context-save code per LANGUAGE.md §8 and the M1 facts.

## 6. Open questions for M1/M4

1. ~~Exact Access Bank split and GPR ranges per bank~~ — resolved in M1 (FACTS §1–2).
2. Whether `FSR1`/`FSR2` may be left to the programmer outside the optional stack.
3. Cost model: static-frame argument passing vs. register passing (measured, not assumed).
4. Calling cost of the multiplier/divide helpers and whether they take arguments in `WREG`/frame
   slots or in dedicated Access Bank scratch.
